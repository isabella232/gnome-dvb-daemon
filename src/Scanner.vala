/*
 * Copyright (C) 2008-2010 Sebastian Pölsterl
 *
 * This file is part of GNOME DVB Daemon.
 *
 * GNOME DVB Daemon is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * GNOME DVB Daemon is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with GNOME DVB Daemon.  If not, see <http://www.gnu.org/licenses/>.
 */

using GLib;
using Gee;
using DVB.Logging;

namespace DVB {

    /**
     * An abstract class responsible for scanning for new channels
     */
    public abstract class Scanner : GLib.Object {

        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        /**
         * Emitted when the Destroy () method is called
         */
        public signal void destroyed ();

        /**
         * Emitted when a frequency has been scanned.
         * Whether a new channel has been found on that frequency or not.
         */
        public signal void frequency_scanned (uint frequency, uint freq_left);

        /**
         * @frequency: Frequency of the channel
         * @sid: SID of the channel
         * @name: Name of the channel
         * @network: Name of network the channel is part of
         * @type: What type of channel this is (Radio or TV)
         * @scrambled: Whether the channel is scrambled
         *
         * Emitted when a new channel has been found
         */
        public signal void channel_added (uint frequency, uint sid,
            string name, string network, string type, bool scrambled);

        public signal void frontend_stats (double signal_strength,
            double signal_noise_ratio);

        /**
         * Emitted when all frequencies have been scanned
         */
        public signal void finished ();

        /**
         * The DVB device the scanner should use
         */
        [DBus (visible = false)]
        public DVB.Device Device { get; construct; }

        [DBus (visible = false)]
        public ChannelList Channels {
            get { return this.channels; }
        }

        protected ChannelList channels;

        /**
         * The Gst pipeline used for scanning
         */
        protected Gst.Element pipeline;

        /**
         * Contains the tuning parameters we use for scanning
         */
        protected GLib.Queue<Gst.Structure> frequencies;

        /**
         * The tuning paramters we're currently using
         */
        protected Gst.Structure? current_tuning_params;

        /**
         * All the frequencies that have been scanned already
         */
        protected HashSet<ScannedItem> scanned_frequencies;

        private static const string BASE_PIDS = "16:17"; // NIT, SDT
        private static const string PIPELINE_TEMPLATE = "dvbsrc name=dvbsrc adapter=%u frontend=%u pids=%s stats-reporting-interval=100 ! mpegtsparse ! fakesink silent=true";

        // Contains SIDs
        private ArrayList<uint> new_channels;
        private Source check_for_lock_source;
        private Source wait_for_tables_source;
        private Source start_scan_source;
        private bool nit_arrived;
        private bool sdt_arrived;
        private bool pat_arrived;
        private bool pmt_arrived;
        private bool locked;
        private MainContext context;
        private MainLoop loop;
        private Thread<void*> worker_thread;
        private bool running;
        private uint bus_watch_id;

        construct {
            this.scanned_frequencies =
                new HashSet<ScannedItem> (ScannedItem.hash, ScannedItem.equal);
            this.new_channels = new ArrayList<uint> ();
            this.frequencies = new GLib.Queue<Gst.Structure> ();
            this.context = new MainContext ();
            this.running = false;
        }

        /**
         * Setup the pipeline correctly
         */
        protected abstract void prepare();

        /**
         * Use the frequency and possibly other data to
         * mark the tuning paramters as already used
         */
        protected abstract ScannedItem get_scanned_item (Gst.Structure structure);

        /**
         * Return a new empty channel
         */
        protected abstract Channel get_new_channel ();

        /**
         * Retrieve the data from structure and add it to the Channel
         */
        protected abstract void add_values_from_structure_to_channel (Gst.Structure delivery, Channel channel);

        /**
         * Called to parse a line from the initial tuning data
         */
        protected abstract void add_scanning_data_from_string (string line);

        /**
         * Start the scanner
         */
        public void Run () throws DBusError {
            if (this.running) return;
            this.running = true;

            this.loop = new MainLoop (this.context, false);
            try {
                this.worker_thread = new Thread<void*>.try ("Scanner-Worker-Thread", this.worker);
            } catch (Error e) {
                log.error ("Could not create thread: %s", e.message);
                return;
            }

            this.channels = new ChannelList ();
            // pids: 0=pat, 16=nit, 17=sdt, 18=eit
            try {
                this.pipeline = Gst.parse_launch(
                    PIPELINE_TEMPLATE.printf (this.Device.Adapter,
                        this.Device.Frontend, BASE_PIDS));
            } catch (Error e) {
                log.error ("Could not create pipeline: %s", e.message);
                return;
            }

            Gst.Bus bus = this.pipeline.get_bus();
            this.bus_watch_id = cUtils.gst_bus_add_watch_context (bus,
                    this.bus_watch_func, this.context);

            this.pipeline.set_state(Gst.State.READY);

            this.queue_start_scan ();
        }

        /**
         * Abort scanning and cleanup
         */
        public void Destroy () throws DBusError {
            this.do_destroy ();
        }

        public void do_destroy () {
            this.destroy_start_scan_source ();
            this.remove_check_for_lock_timeout ();
            this.remove_wait_for_tables_timeout ();
            this.clear_and_reset_all ();
            this.channels.clear ();
            this.channels = null;

            if (this.loop != null) {
                this.loop.quit ();
                this.loop = null;
                this.worker_thread.join ();
                this.worker_thread = null;
            }
            this.destroyed ();
        }

        /**
         * @path: Location where the file will be stored
         *
         * Write all the channels stored in this.Channels to file
         */
        public bool WriteAllChannelsToFile (string path) throws DBusError {
            bool success = true;
            var writer = new io.ChannelListWriter (File.new_for_path (path));
            foreach (DVB.Channel c in this.channels) {
                try {
                    writer.write (c);
                } catch (Error e) {
                    log.error ("Could not write to file: %s", e.message);
                    success = false;
                }
            }

            try {
                writer.close ();
            } catch (Error e) {
                log.error ("Could not close file handle: %s", e.message);
                success = false;
            }

            return success;
        }

        /**
         * @channel_sids: A list of channels' SIDs
         * @path: Location where the file will be stored
         *
         * Write the channels with the given SIDs to file @path
         */
        public bool WriteChannelsToFile (uint[] channel_sids, string path)
                throws DBusError
        {
            bool success = true;
            var writer = new io.ChannelListWriter (File.new_for_path (path));
            foreach (uint sid in channel_sids) {
                DVB.Channel? c = this.channels.get_channel (sid);
                if (c == null) {
                    log.warning ("Channel with SID 0x%x does not exist", sid);
                    continue;
                }
                try {
                    writer.write (c);
                } catch (Error e) {
                    log.error ("Could not write to file: %s", e.message);
                    success = false;
                }
            }

            try {
                writer.close ();
            } catch (Error e) {
                log.error ("Could not close file handle: %s", e.message);
                success = false;
            }

            return success;
        }

        public bool AddScanningDataFromFile (string path) throws DBusError {
            File datafile = File.new_for_path(path);

            log.debug ("Reading scanning data from %s", path);

            if (!Utils.is_readable_file (datafile)) return false;

            DataInputStream reader;
            try {
                reader = new DataInputStream (datafile.read (null));
            } catch (Error e) {
                log.error ("Could not open %s: %s", path, e.message);
                return false;
            }

            string line = null;
        	size_t len;
            try {
                while ((line = reader.read_line (out len, null)) != null) {
                    if (len == 0) continue;

                    line = line.chug ();
                    if (line.has_prefix ("#")) continue;

                    this.add_scanning_data_from_string (line);
                }
            } catch (Error e) {
                log.error ("Could not read %s: %s", path, e.message);
                return false;
            }

            try {
                reader.close (null);
            } catch (Error e) {
                log.error ("Could not close file handle: %s", e.message);
                return false;
            }

            return true;
        }

        /* Main Thread */
        private void* worker () {
            this.loop.run ();

            return null;
        }

        protected void clear_and_reset_all () {
            if (this.pipeline != null) {
               Source bus_watch_source = this.context.find_source_by_id (
                    this.bus_watch_id);
                if (bus_watch_source != null) {
                    bus_watch_source.destroy ();
                    this.bus_watch_id = 0;
                }
                log.debug ("Disposing pipeline");
                this.pipeline.set_state (Gst.State.NULL);
                // Free pipeline
                this.pipeline = null;
            }

            this.scanned_frequencies.clear ();
            this.clear_frequencies ();
            this.current_tuning_params = null;
            this.new_channels.clear ();
            this.running = false;
        }

        protected void clear_frequencies () {
            while (!this.frequencies.is_empty ()) {
                Gst.Structure? s = this.frequencies.pop_head ();
                // Force that gst_structure_free is called
                s = null;
            }
            this.frequencies.clear ();
        }

        protected void add_structure_to_scan (owned Gst.Structure structure) {
            if (structure == null) return;

            ScannedItem item = this.get_scanned_item (structure);

            if (!this.scanned_frequencies.contains (item)) {
                log.debug ("Queueing new frequency %u", item.Frequency);
                this.frequencies.push_tail ((owned) structure);
                this.scanned_frequencies.add (item);
            }
        }

        /**
         * Pick up the next tuning paramters from the queue
         * and start scanning with them
         */
        protected bool start_scan () {
            bool all_tables = (this.sdt_arrived && this.nit_arrived
                && this.pat_arrived && this.pmt_arrived);
            log.debug ("Received all tables: %s (pat: %s, sdt: %s, nit: %s, pmt: %s)",
                all_tables.to_string (), this.pat_arrived.to_string (),
                this.sdt_arrived.to_string (), this.nit_arrived.to_string (),
                this.pmt_arrived.to_string ());

            this.nit_arrived = false;
            this.sdt_arrived = false;
            this.pat_arrived = false;
            this.pmt_arrived = false;
            this.locked = false;

            if (this.current_tuning_params != null) {
                uint old_freq;
                this.current_tuning_params.get_uint ("frequency", out old_freq);
                this.frequency_scanned (old_freq, this.frequencies.length);
            }

            if (this.frequencies.is_empty()) {
                message("Finished scanning");
                // We don't have all the information for those channels
                // remove them
                lock (this.new_channels) {
                    log.debug ("%u channels still have missing or invalid information",
                        this.new_channels.size);
                    foreach (uint sid in this.new_channels) {
                        this.channels.remove (sid);
                    }
                }
                this.clear_and_reset_all ();
                this.finished ();
                return false;
            }

            this.current_tuning_params = this.frequencies.pop_head();

            // Remember that we already scanned this frequency
            uint freq;
            this.current_tuning_params.get_uint ("frequency", out freq);

            log.debug("Starting scanning frequency %u (%u left)", freq,
                this.frequencies.get_length ());

            this.pipeline.set_state (Gst.State.READY);

            this.prepare ();

            // Reset PIDs
            Gst.Element dvbsrc = ((Gst.Bin)this.pipeline).get_by_name ("dvbsrc");
            dvbsrc.set ("pids", BASE_PIDS);

            this.check_for_lock_source =
                new TimeoutSource.seconds (5);
            this.check_for_lock_source.set_callback (this.check_for_lock);
            this.check_for_lock_source.attach (this.context);

            this.pipeline.set_state (Gst.State.PLAYING);

            return false;
        }

        /**
         * Check if we received a lock with the currently
         * used tuning parameters
         */
        protected bool check_for_lock () {
            if (!this.locked) {
                this.pipeline.set_state (Gst.State.READY);
                this.queue_start_scan ();
            }
            return false;
        }

        protected bool wait_for_tables () {
            if (!(this.sdt_arrived && this.nit_arrived && this.pat_arrived
                    && this.pmt_arrived)) {
                this.pipeline.set_state (Gst.State.READY);
                this.queue_start_scan ();
            }
            return false;
        }

        protected void destroy_start_scan_source () {
            if (this.start_scan_source != null &&
                    !this.start_scan_source.is_destroyed ()) {
                this.start_scan_source.destroy ();
                this.start_scan_source = null;
            }
        }

        protected void remove_check_for_lock_timeout () {
            if (this.check_for_lock_source != null &&
                    !this.check_for_lock_source.is_destroyed ()) {
                this.check_for_lock_source.destroy ();
                this.check_for_lock_source = null;
            }
        }

        protected void remove_wait_for_tables_timeout () {
            if (this.wait_for_tables_source != null &&
                    !this.wait_for_tables_source.is_destroyed ()) {
                this.wait_for_tables_source.destroy ();
                this.wait_for_tables_source = null;
            }
        }

        protected void queue_start_scan () {
            /* Avoid creating source multiple times */
            if (this.start_scan_source == null ||
                    this.start_scan_source.is_destroyed ()) {
                log.debug ("Queueing start_scan");
                this.start_scan_source = new IdleSource ();
                this.start_scan_source.set_callback (this.start_scan);
                this.start_scan_source.attach (this.context);
            }
        }

        protected static void set_uint_property (Gst.Element src,
            Gst.Structure params, string key) {
            uint val;
            params.get_uint (key, out val);
            src.set (key, val);
        }

        protected void on_dvb_frontend_stats_structure (Gst.Structure structure) {
            bool has_lock;
            structure.get_boolean ("lock", out has_lock);
            if (has_lock && !this.locked) {
                log.debug ("Got lock");

                this.remove_check_for_lock_timeout ();
                this.wait_for_tables_source =
                    new TimeoutSource.seconds (10);
                this.wait_for_tables_source.set_callback (this.wait_for_tables);
                this.wait_for_tables_source.attach (this.context);
            }
            int _signal;
            structure.get_int ("signal", out _signal);
            int _snr;
            structure.get_int ("snr", out _snr);
            this.frontend_stats ((_signal / (double)0xffff),
                (_snr / (double)0xffff));
        }

        protected void on_dvb_read_failure_structure () {
            log.warning ("Read failure");
            /*
            this.Destroy ();
            */
        }

        protected void on_pat_structure (Gst.Structure structure) {
            log.debug("Received PAT");

            Set<uint> pid_set = new HashSet<uint> ();
            // add BASE_PIDS
            pid_set.add (16);
            pid_set.add (17);

            Value programs = structure.get_value ("programs");
            uint size = Gst.ValueList.get_size (programs);
            Value val;
            weak Gst.Structure program;
            // Iterate over programs
            for (uint i=0; i<size; i++) {
                val = Gst.ValueList.get_value (programs, i);
                program = Gst.Value.get_structure (val);

                uint sid;
                program.get_uint ("program-number", out sid);

                uint pmt;
                program.get_uint ("pid", out pmt);

                pid_set.add (pmt);
            }

            StringBuilder new_pids = new StringBuilder ();
            int i = 0;
            foreach (uint pid in pid_set) {
                if (i+1 == pid_set.size)
                    new_pids.append ("%u".printf (pid));
                else
                    new_pids.append ("%u:".printf (pid));
                i++;
            }

            log.debug ("Setting %d pids: %s", pid_set.size, new_pids.str);
            // We want to parse the pmt as well
            Gst.Element dvbsrc = ((Gst.Bin)this.pipeline).get_by_name ("dvbsrc");
            dvbsrc.set ("pids", new_pids.str);

            this.pat_arrived = true;
        }

        protected void on_sdt_structure (Gst.Structure structure) {
            uint tsid;
            structure.get_uint ("transport-stream-id", out tsid);

            log.debug("Received SDT (0x%x)", tsid);

            Value services = structure.get_value ("services");
            uint size = Gst.ValueList.get_size (services);

            Value val;
            weak Gst.Structure service;
            // Iterate over services
            for (uint i=0; i<size; i++) {
                val = Gst.ValueList.get_value (services, i);
                service = Gst.Value.get_structure (val);

                // Returns "service-%d"
                string name = service.get_name ();
                // Get the number at the end
                int sid = int.parse (name.substring (8, name.length - 8));

                if (service.has_field ("name"))
                    name = service.get_string ("name");

                if (!this.channels.contains (sid)) {
                    this.add_new_channel (sid);
                }

                Channel channel = this.channels.get_channel (sid);

                if (service.has_field ("scrambled")) {
                    bool scrambled;
                    service.get_boolean ("scrambled", out scrambled);
                    channel.Scrambled = scrambled;
                } else {
                    channel.Scrambled = false;
                }

                if (name.validate ()) {
                    channel.Name = name.replace ("\\s", " ");
                }

                channel.TransportStreamId = tsid;
                string provider = service.get_string ("provider-name");
                if (provider != null && provider.validate ()) {
                    channel.Network = provider;
                } else {
                    channel.Network = "";
                }

                log.debug ("Found service 0x%x, %s, scrambled: %s", sid,
                    channel.Name, channel.Scrambled.to_string ());
            }

            this.sdt_arrived = true;
        }

        protected void on_nit_structure (Gst.Structure structure) {
            bool actual;
            structure.get_boolean ("actual-network", out actual);
            if (!actual)
                return;

            log.debug("Received NIT");

            string name;
            if (structure.has_field ("network-name")) {
                name = structure.get_string ("network-name");
            } else {
                uint nid;
                structure.get_uint ("network-id", out nid);
                name = "%u".printf (nid);
            }
            log.debug ("Network name '%s'", name);

            Value transports = structure.get_value ("transports");
            uint size = Gst.ValueList.get_size (transports);
            Value val;
            weak Gst.Structure transport;
            // Iterate over transports
            for (uint i=0; i<size; i++) {
                val = Gst.ValueList.get_value (transports, i);
                transport = Gst.Value.get_structure (val);

                uint tsid;
                transport.get_uint ("transport-stream-id", out tsid);

                if (transport.has_field ("delivery")) {
                    Value delivery_val = transport.get_value ("delivery");
                    unowned Gst.Structure delivery = Gst.Value.get_structure (
                        delivery_val);

                    log.debug ("Received TS 0x%x", tsid);

                    uint freq;
                    delivery.get_uint ("frequency", out freq);
                    // Takes care of duplicates
                    this.add_structure_to_scan (delivery.copy());
                }

                if (transport.has_field ("channels")) {
                    Value channels = transport.get_value ("channels");
                    uint channels_size = Gst.ValueList.get_size (channels);

                    Value channel_val;
                    weak Gst.Structure channel_struct;
                    // Iterate over channels
                    for (int j=0; j<channels_size; j++) {
                        channel_val = Gst.ValueList.get_value (channels, j);
                        channel_struct = Gst.Value.get_structure (channel_val);

                        uint sid;
                        channel_struct.get_uint ("service-id", out sid);

                        if (!this.channels.contains (sid)) {
                            this.add_new_channel (sid);
                        }

                        Channel dvb_channel = this.channels.get_channel (sid);

                        if (name.validate ()) {
                            dvb_channel.Network = name;
                        } else {
                            dvb_channel.Network = "";
                        }

                        uint lcnumber;
                        channel_struct.get_uint ("logical-channel-number", out lcnumber);
                        dvb_channel.LogicalChannelNumber = lcnumber;
                    }
                }
            }

            this.nit_arrived = true;
        }

        protected void on_pmt_structure (Gst.Structure structure) {
            log.debug ("Received PMT");

            uint program_number;
            structure.get_uint ("program-number", out program_number);

            if (!this.channels.contains (program_number)) {
                this.add_new_channel (program_number);
            }

            Channel dvb_channel = this.channels.get_channel (program_number);

            Value streams = structure.get_value ("streams");
            uint size = Gst.ValueList.get_size (streams);

            Value stream_val;
            weak Gst.Structure stream;
            // Iterate over streams
            for (int i=0; i<size; i++) {
                stream_val = Gst.ValueList.get_value (streams, i);
                stream = Gst.Value.get_structure (stream_val);

                uint pid;
                stream.get_uint ("pid", out pid);

                // See ISO/IEC 13818-1 Table 2-29
                uint stream_type;
                stream.get_uint ("stream-type", out stream_type);

                switch (stream_type) {
                    case 0x01:
                    case 0x02:
                    case 0x1b: /* H.264 video stream */
                        log.debug ("Found video PID 0x%x for channel 0x%x",
                            pid, program_number);
                        dvb_channel.VideoPID = pid;
                    break;
                    case 0x03:
                    case 0x04:
                    case 0x0f:
                    case 0x11:
                        log.debug ("Found audio PID 0x%x for channel 0x%x",
                            pid, program_number);
                        dvb_channel.AudioPIDs.add (pid);
                    break;
                    default:
                        log.debug ("Other stream type: 0x%02x", stream_type);
                    break;
                }
            }

            this.pmt_arrived = true;
        }

        protected bool bus_watch_func (Gst.Bus bus, Gst.Message message) {
            switch (message.type) {
                case Gst.MessageType.ELEMENT: {
                    unowned Gst.Structure structure = message.get_structure ();
                    string structure_name = structure.get_name();
                    if (structure_name == "dvb-frontend-stats")
                        this.on_dvb_frontend_stats_structure (structure);
                    else if (structure_name == "dvb-read-failure")
                        this.on_dvb_read_failure_structure ();
                    else if (structure_name == "sdt")
                        this.on_sdt_structure (structure);
                    else if (structure_name == "nit")
                        this.on_nit_structure (structure);
                    else if (structure_name == "pat")
                        this.on_pat_structure (structure);
                    else if (structure_name == "pmt")
                        this.on_pmt_structure (structure);
                    else
                        return true; /* We are not interested in the message */
                break;
                }
                case Gst.MessageType.ERROR: {
                    Error gerror;
                    string debug;
                    message.parse_error (out gerror, out debug);
                    log.warning ("%s %s", gerror.message, debug);
                    return true;
                }
                default:
                    return true; /* We are not interested in the message */
            }

            // NIT gives us the transport stream, SDT links SID and TS ID
            if (this.nit_arrived && this.sdt_arrived && this.pat_arrived) {
                // We received all tables at least once. Add valid channels.
                lock (this.new_channels) {
                    ArrayList<uint> del_channels = new ArrayList<uint> ();
                    foreach (uint sid in this.new_channels) {
                        DVB.Channel channel = this.channels.get_channel (sid);

                        // If this fails we may miss video or audio pid,
                        // because we didn't came across the sdt or pmt, yet
                        if (channel.is_valid ()) {
                            string type = (channel.is_radio ()) ? "Radio" : "TV";
                            log.debug ("Channel added: %s", channel.to_string ());
                            this.channel_added (channel.Frequency, sid,
                                channel.Name, channel.Network, type,
                                channel.Scrambled);
                            // Mark channel for deletion of this.new_channels
                            del_channels.add (sid);
                        } else {
                            log.debug ("Channel 0x%x is not valid: %s", sid,
                                channel.to_string ());
                            this.pmt_arrived = false;
                        }
                    }

                    // Only remove those channels we have all the information for
                    foreach (uint sid in del_channels) {
                        this.new_channels.remove (sid);
                    }
                }
            }

            // If we collect all information we can continue scanning
            // the next frequency
            if (this.sdt_arrived && this.nit_arrived && this.pat_arrived
                    && this.pmt_arrived) {
                this.remove_wait_for_tables_timeout ();

                this.queue_start_scan ();
            }

            return true;
        }

        protected void add_new_channel (uint sid) {
            log.debug ("Adding new channel with SID 0x%x", sid);
            Channel new_channel = this.get_new_channel ();
            new_channel.Sid = sid;
            // add values from Gst.Structure to Channel
            this.add_values_from_structure_to_channel (
                this.current_tuning_params,
                new_channel);
            this.channels.add (new_channel);
            lock (this.new_channels) {
                this.new_channels.add (sid);
            }
        }
    }

}
