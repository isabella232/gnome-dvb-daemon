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
using GstMpegts;

namespace DVB {

    /**
     * A class responsible for scanning for new channels
     */
    public class Scanner : GLib.Object, IDBusScanner {

        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        /**
         * Emitted when the Destroy () method is called
         */
        public signal void destroyed ();

        /**
         * The DVB device the scanner should use
         */
        [DBus (visible = false)]
        public DVB.Device Device { get; construct; }

        [DBus (visible = false)]
        public ChannelList Channels {
            get { return this.channels; }
        }

        public AdapterType Type { get; construct; }

        protected ChannelList channels;

        /**
         * The Gst pipeline used for scanning
         */
        protected Gst.Element pipeline;

        /**
         * Contains the tuning parameters we use for scanning
         */
        private GLib.Queue<Parameter> queue_scanning_params;

        /**
         * The tuning paramters we're currently using
         */
        private Parameter? current_scanning_param;

        /**
         * All the frequencies that have been scanned already
         */
        private Gee.HashSet<Parameter> scanned_scanning_params;

        private static const string BASE_PIDS = "16:17"; // NIT, SDT
        private static const string PIPELINE_TEMPLATE = "dvbsrc name=dvbsrc adapter=%u frontend=%u stats-reporting-interval=100 ! tsparse ! fakesink silent=true";

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
            this.scanned_scanning_params = new Gee.HashSet<Parameter> ();
            this.new_channels = new ArrayList<uint> ();
            this.queue_scanning_params = new GLib.Queue<Parameter> ();
            this.context = new MainContext ();
            this.running = false;
        }

        public Scanner (DVB.Device device, AdapterType type) {
            Object (Device: device, Type: type);
        }

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
                        this.Device.Frontend));
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
         * @data: all scanning parameter
         *
         * in progress
         */
        public bool AddScanningData (GLib.HashTable<string, Variant> data) throws DBusError {
            unowned Variant _var = data.lookup ("delsys");
            if (_var != null) {
                switch (_var.get_string ()) {
                    case "DVBT":
                        DvbTParameter param = new DvbTParameter ();
                        if (param.add_scanning_data (data)) {
                            this.add_to_queue (param);
                            return true;
                        }
                        break;
                    case "DVBC/ANNEX_A":
                        DvbCEuropeParameter param = new DvbCEuropeParameter ();
                        if (param.add_scanning_data (data)) {
                            this.add_to_queue (param);
                            return true;
                        }
                        break;
                    case "DVBS":
                        DvbSParameter param = new DvbSParameter ();
                        if (param.add_scanning_data (data)) {
                            this.add_to_queue (param);
                            return true;
                        }
                        break;
                    default:
                        break;
                }
            }
            return false;
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

            DVB.io.ScanningListReader reader = new DVB.io.ScanningListReader (path);

            try {
                reader.read_data ();
            } catch (KeyFileError e) {
                log.error ("could not read init file");
            } catch (FileError e) {
                log.error ("could not read init file");
            }

            unowned GLib.List<Parameter> scanning_params = reader.Parameters;
            log.debug ("read %u scanning parameter", scanning_params.length());

            // add to queue
            foreach (Parameter s in scanning_params) {
                this.add_to_queue (s);
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

            this.scanned_scanning_params.clear ();
            this.clear_queue ();
            this.current_scanning_param = null;
            this.new_channels.clear ();
            this.running = false;
        }

        protected void clear_queue () {
            while (!this.queue_scanning_params.is_empty ()) {
                Parameter? s = this.queue_scanning_params.pop_head ();
                s = null;
            }
            this.queue_scanning_params.clear ();
        }

        protected void add_to_queue (Parameter param) {
            if (param == null) return;

            if (!isSupported(param.Delsys, this.Type))
                return;

            bool eq = false;
            foreach (Parameter s in this.scanned_scanning_params) {
                if (s.equal(param)) {
                    eq = true;
                    break;
                }
            }

            if (!eq) {
                log.debug ("Queueing new frequency %u", param.Frequency);
                this.queue_scanning_params.push_tail (param);
                this.scanned_scanning_params.add (param);
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

            if (this.current_scanning_param != null) {
                this.frequency_scanned (this.current_scanning_param.Frequency, this.queue_scanning_params.length);
            }

            if (this.queue_scanning_params.is_empty()) {
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

            this.current_scanning_param = this.queue_scanning_params.pop_head();

            // Remember that we already scanned this frequency
            uint freq = this.current_scanning_param.Frequency;

            log.debug("Starting scanning frequency %u (%u left)", freq,
                this.queue_scanning_params.get_length ());

            this.pipeline.set_state (Gst.State.READY);

            // Reset PIDs and parameters
            Gst.Element dvbsrc = ((Gst.Bin)this.pipeline).get_by_name ("dvbsrc");

            this.current_scanning_param.prepare (dvbsrc);

//            dvbsrc.set ("pids", BASE_PIDS);

            this.check_for_lock_source =
                new TimeoutSource.seconds (20);
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
                this.locked = true;
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

        protected void on_pat_structure (Section section) {
            /* parse if we have the right nit */

            log.debug("Received PAT, version %d, section number %d, last section number %d",
                section.version_number, section.section_number, section.last_section_number);

            GenericArray<weak PatProgram> pats = section.get_pat();

            Set<uint> pid_set = new HashSet<uint> ();
            // add BASE_PIDS
            pid_set.add (16);
            pid_set.add (17);

            PatProgram pat;
            for (int i = 0; i < pats.length; i++) {
                pat = pats.@get(i);

                uint pmt = pat.network_or_program_map_PID;

                pid_set.add(pmt);
            }

            StringBuilder new_pids = new StringBuilder ();
            int i = 0;
            foreach (uint pid in pid_set) {
                if (i + 1 == pid_set.size)
                    new_pids.append ("%u".printf (pid));
                else
                    new_pids.append ("%u:".printf (pid));
                i++;
            }

            log.debug ("Setting %d pids: %s", pid_set.size, new_pids.str);
            // We want to parse the pmt as well
//            Gst.Element dvbsrc = ((Gst.Bin)this.pipeline).get_by_name ("dvbsrc");
//            dvbsrc.set ("pids", new_pids.str);

            this.pat_arrived = true;
        }

        protected void on_sdt_structure (Section section) {

            unowned SDT sdt = section.get_sdt();

            if (!sdt.actual_ts)
                return;

            uint tsid = section.subtable_extension;
            uint onid = sdt.original_network_id;
            log.debug("Received SDT (0x%04x.0x%04x) , version %d, section number %d, last section number %d", onid, tsid,
                section.version_number, section.section_number, section.last_section_number);

            SDTService service;
            for (int i = 0; i < sdt.services.length; i++) {
                service = sdt.services.@get(i);

                uint sid = service.service_id;

                if (!this.channels.contains (sid)) {
                    this.add_new_channel (sid);
                }

                Channel channel = this.channels.get_channel (sid);

                channel.Scrambled = service.free_CA_mode;

                channel.TransportStreamId = tsid;

                Descriptor desc;
                for (int j = 0; j < service.descriptors.length; j++) {
                    desc = service.descriptors.@get(j);
                    if (desc.tag == DVBDescriptorType.EXTENSION)
                        log.debug ("Extentend descriptor 0x%02x", desc.tag_extension);
                    else
                        log.debug ("Descriptor 0x%02x", desc.tag);

                    switch (desc.tag) {
                        case DVBDescriptorType.SERVICE: {
                            DVBServiceType type;
                            string name, provider;
                            desc.parse_dvb_service(out type, out name,
                                 out provider);

                            channel.Name = name;
                            channel.Network = provider;
                            channel.ServiceType = type;
                            break;
                        }
                        default:
                            break;

                    }


                }

                    log.debug ("Found service 0x%04x, %s, scrambled: %s", sid,
                    channel.Name, channel.Scrambled.to_string ());

            }
            if (sdt.actual_ts)
                this.sdt_arrived = true;
        }

        protected void on_nit_structure (Section section) {

            unowned NIT nit = section.get_nit();

            if (!nit.actual_network)
                return;

            log.debug("Received NIT, version %d, section number %d, last section number %d",
                section.version_number, section.section_number, section.last_section_number);

            Descriptor desc;
            string name = null;
            for (int i = 0; i < nit.descriptors.length; i++) {
                desc = nit.descriptors.@get (i);
                if (desc.tag == DVBDescriptorType.NETWORK_NAME) {
                   desc.parse_dvb_network_name (out name);
                   break;
                }
            }

            uint nid = nit.network_id;
            if (name == null)
                name = "%u".printf (nid);

            log.debug ("Network name '%s', id = 0x%04x", name, nid);

            NITStream stream;
            for (int i = 0; i < nit.streams.length; i++) {
                stream = nit.streams.@get (i);

                uint tsid = stream.transport_stream_id;
                uint onid = stream.original_network_id;

                log.debug ("Received TS 0x%04x, on_id = 0x%04x", tsid, onid);
                // descriptors

                for (int j = 0; j < stream.descriptors.length; j++) {
                    desc = stream.descriptors.@get (j);

                    if (desc.tag == DVBDescriptorType.EXTENSION)
                        log.debug ("Extentend desriptor 0x%02x", desc.tag_extension);
                    else
                        log.debug ("Desriptor 0x%02x", desc.tag);

                    switch (desc.tag) {
                        case DVBDescriptorType.TERRESTRIAL_DELIVERY_SYSTEM:
                            TerrestrialDeliverySystemDescriptor tdesc;
                            desc.parse_terrestrial_delivery_system (out tdesc);
                            DVBCodeRate ratehp, ratelp;

                            if (tdesc.priority) {
                                ratehp = tdesc.code_rate_hp;
                                ratelp = DVBCodeRate.NONE;
                            } else {
                                ratehp = DVBCodeRate.NONE;
                                ratelp = tdesc.code_rate_lp;
                            }

                            DvbTParameter dvbtp = new DvbTParameter.with_parameter (
                                tdesc.frequency, tdesc.bandwidth, tdesc.guard_interval,
                                tdesc.transmission_mode, tdesc.hierarchy, tdesc.constellation,
                                ratelp, ratehp);

                            if (this.current_scanning_param.Frequency == tdesc.frequency) {
                                lock (this.channels) {
                                    foreach (Channel channel in this.channels) {
                                        if (channel.Param.Frequency == tdesc.frequency)
                                            channel.Param = dvbtp;
                                    }
                                }
                                this.current_scanning_param = dvbtp;
                            } else
                                this.add_to_queue (dvbtp);

                            break;
                        case DVBDescriptorType.CABLE_DELIVERY_SYSTEM:
                            CableDeliverySystemDescriptor cdesc;
                            desc.parse_cable_delivery_system (out cdesc);

                            DvbCEuropeParameter dvbcp = new DvbCEuropeParameter.with_parameter (
                                cdesc.frequency, cdesc.symbol_rate, cdesc.modulation,
                                cdesc.fec_inner);

                            if (this.current_scanning_param.Frequency == cdesc.frequency)
                                this.current_scanning_param = dvbcp;
                            else
                                this.add_to_queue (dvbcp);

                            break;
                        case DVBDescriptorType.SATELLITE_DELIVERY_SYSTEM:
                            SatelliteDeliverySystemDescriptor sdesc;
                            desc.parse_satellite_delivery_system (out sdesc);
                            float position;

                            if (!sdesc.modulation_system) {
                                if (sdesc.modulation_type != ModulationType.QPSK) {
                                    // TODO: Turbo
                                } else {
                                    // DVB-S
                                    position = sdesc.orbital_position;
                                    if (!sdesc.west_east) {
                                       // west
                                       position *= -1;
                                    }
                                    log.debug ("Orbital position: %f", position);

                                    DvbSParameter dvbsp = new DvbSParameter.with_parameter (
                                        sdesc.frequency, sdesc.symbol_rate, position,
                                        sdesc.polarization, sdesc.fec_inner);

                                    if (this.current_scanning_param.Frequency == sdesc.frequency)
                                        this.current_scanning_param = dvbsp;
                                    else
                                        this.add_to_queue (dvbsp);
                                }
                            } else {
                               // TODO:  DVB-S2
                            }
                            break;
                        default:
                            break;
                    }

                }

            }

            if (nit.actual_network)
                this.nit_arrived = true;
        }

        protected void on_pmt_structure (Section section) {

            log.debug ("Received PMT, version %d, section number %d, last section number %d",
                section.version_number, section.section_number, section.last_section_number);

            unowned PMT pmt = section.get_pmt();

            uint program_number = pmt.program_number;

            if (!this.channels.contains (program_number)) {
                this.add_new_channel (program_number);
            }

            Channel dvb_channel = this.channels.get_channel (program_number);

            PMTStream stream;
            for (int i = 0; i < pmt.streams.length; i++) {
                stream = pmt.streams.@get(i);

                uint pid = stream.pid;

                switch (stream.stream_type) {
                    case StreamType.VIDEO_MPEG1:
                    case StreamType.VIDEO_MPEG2:
                    case StreamType.VIDEO_H264:
                        log.debug ("Found video PID 0x%04x for channel 0x%04x",
                            pid, program_number);
                        dvb_channel.VideoPID = pid;
                        break;
                    case StreamType.AUDIO_MPEG1:
                    case StreamType.AUDIO_MPEG2:
                    case StreamType.AUDIO_AAC_ADTS:
                    case StreamType.AUDIO_AAC_LATM:
                    case 0x81: // ATSC AC3
                    case 0x87: // ATSC EAC3
                        log.debug ("Found audio PID 0x%04x for channel 0x%04x",
                            pid, program_number);
                        // check is pid added ?
                        if (!dvb_channel.AudioPIDs.contains (pid))
                            dvb_channel.AudioPIDs.add (pid);
                        break;
                    case StreamType.PRIVATE_PES_PACKETS:
                        // we must looking for dts or ac3 descriptors
                        if (find_descriptor (stream.descriptors, DVBDescriptorType.DTS) != null
                            || find_descriptor (stream.descriptors, DVBDescriptorType.AC3) != null
                            || find_descriptor (stream.descriptors, DVBDescriptorType.ENHANCED_AC3) != null) {
                            log.debug ("Found audio PID 0x%04x for channel 0x%04x",
                                pid, program_number);
                            // check is pid added ?
                            if (!dvb_channel.AudioPIDs.contains (pid))
                                dvb_channel.AudioPIDs.add (pid);
                        }
                        break;
                    default:
                        log.debug ("Other stream type: 0x%04x", stream.stream_type);
                        break;
                }
            }

            this.pmt_arrived = true;
        }

        protected bool bus_watch_func (Gst.Bus bus, Gst.Message message) {
            switch (message.type) {
                case Gst.MessageType.ELEMENT: {
                    Section section = message_parse_mpegts_section(message);

                    if (section == null) {
                        weak Gst.Structure structure = message.get_structure ();
                        string structure_name = structure.get_name();
                        if (structure_name == "dvb-frontend-stats")
                            this.on_dvb_frontend_stats_structure (structure);
                        else if (structure_name == "dvb-read-failure")
                            this.on_dvb_read_failure_structure ();
                        else return true;
                    }
                    else {
                        switch (section.section_type) {
                            case SectionType.PAT: {
                                this.on_pat_structure (section);
                                break;
                            }
                            case SectionType.PMT: {
                                this.on_pmt_structure (section);
                                break;
                            }
                            case SectionType.NIT: {
                                this.on_nit_structure (section);
                                break;
                            }
                            case SectionType.SDT: {
                                this.on_sdt_structure (section);
                                break;
                            }
                            default: {
                                return true;
                            }
                        }
                    }

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
            if (this.nit_arrived && this.sdt_arrived && this.pat_arrived && this.pmt_arrived) {
                // We received all tables at least once. Add valid channels.
                lock (this.new_channels) {
                    ArrayList<uint> del_channels = new ArrayList<uint> ();
                    foreach (uint sid in this.new_channels) {
                        DVB.Channel channel = this.channels.get_channel (sid);

                        // If this fails we may miss video or audio pid,
                        // because we didn't came across the sdt or pmt, yet
                        if (channel.is_valid ()) {
                            string type = (channel.is_radio ()) ? "Radio" : "TV";
                            log.debug ("Channel added: %s", channel.Name);
                            this.channel_added (channel.Param.Frequency, sid,
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

        private void add_new_channel (uint sid) {
            log.debug ("Adding new channel with SID 0x%x", sid);
            Channel new_channel = new Channel.without_schedule ();
            new_channel.Sid = sid;
            // add values Parameters
            new_channel.Param = this.current_scanning_param;
            this.channels.add (new_channel);
            lock (this.new_channels) {
                this.new_channels.add (sid);
            }
        }
    }

}
