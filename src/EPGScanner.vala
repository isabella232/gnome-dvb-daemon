/*
 * Copyright (C) 2008,2009 Sebastian Pölsterl
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

    public class EPGScanner : GLib.Object {

        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        // how long to wait after all channels have been scanned
        // before the next iteration is started
        private static int CHECK_EIT_INTERVAL = -1;
        // how long to wait for EIT data for each channel in seconds
        private static const int WAIT_FOR_EIT_DURATION = 10;
        // pids: 0=pat, 16=nit, 17=sdt, 18=eit
        private static const string PIPELINE_TEMPLATE =
        "dvbsrc name=dvbsrc adapter=%u frontend=%u pids=0:16:17:18 stats-reporting-interval=0 ! mpegtsparse ! fakesink silent=true";

        private unowned DVB.DeviceGroup DeviceGroup;

        private Gst.Element? pipeline;
        private GLib.Queue<Channel> channels;
        private Source scan_source;
        private Source queue_source;
        private int stop_counter;
        private MainContext context;
        private MainLoop loop;
        private Thread<void*> worker_thread;
        private uint bus_watch_id;
        private HashMap<uint, HashSet<Event>> channel_events;

        construct {
            this.channels = new GLib.Queue<Channel> ();
            this.stop_counter = 0;
            this.context = new MainContext ();
            this.channel_events = new HashMap<uint, HashSet<Event>> ();
        }

        /**
         * @device: The device where EPG should be collected from
         */
        public EPGScanner (DVB.DeviceGroup device) {
            this.DeviceGroup = device;
            // check if interval is unset
            if (CHECK_EIT_INTERVAL == -1) {
                Settings settings = new Factory().get_settings ();
                CHECK_EIT_INTERVAL = settings.get_epg_scan_interval ();
            }
        }

        /**
         * Stop collecting EPG data
         */
        public void stop () {
            log.debug ("Stopping EPG scan for group %u (%d)", this.DeviceGroup.Id, this.stop_counter);

            if (this.stop_counter == 0) {
                this.remove_timeouts ();
                this.reset ();
            }
            this.stop_counter += 1;
        }

        private void remove_timeouts () {
            if (this.scan_source != null) {
                this.scan_source.destroy ();
                this.scan_source = null;
            }
            if (this.queue_source != null) {
                this.queue_source.destroy ();
                this.queue_source = null;
            }

            if (this.loop != null) {
                this.loop.quit ();
                this.loop = null;
                this.worker_thread.join ();
                this.worker_thread = null;
            }
        }

        /* Main Thread */
        private void* worker () {
            this.loop.run ();

            return null;
        }

        private bool setup_pipeline () {
            DVB.Device? device = this.DeviceGroup.get_next_free_device ();
            if (device == null) return false;

            lock (this.pipeline) {
                try {
                    this.pipeline = Gst.parse_launch (PIPELINE_TEMPLATE.printf (
                        device.Adapter, device.Frontend));
                } catch (Error e) {
                    log.error ("Could not create pipeline: %s", e.message);
                    return false;
                }

                Gst.Bus bus = this.pipeline.get_bus ();
                this.bus_watch_id = cUtils.gst_bus_add_watch_context (bus,
                    this.bus_watch_func, this.context);
            }
            return true;
        }

        private void reset_pipeline() {
            lock (this.pipeline) {
                if (this.pipeline != null) {
                    Source bus_watch_source = this.context.find_source_by_id (
                        this.bus_watch_id);
                    if (bus_watch_source != null) {
                        bus_watch_source.destroy ();
                        this.bus_watch_id = 0;
                    }
                    this.pipeline.set_state (Gst.State.NULL);
                    this.pipeline.get_state (null, null, -1);
                    this.pipeline = null;
                }
            }
        }

        private void reset () {
            reset_pipeline ();

            // clear doesn't unref for us so we do this instead
            Channel c;
            while ((c = this.channels.pop_head ()) != null) {
                // Vala unref's Channel instances for us
            }
            this.channels.clear ();
            this.channel_events.clear ();
        }

        /**
         * Start collection EPG data for all channels
         */
        public bool start () {
            log.debug ("Starting EPG scan for group %u (%d)", this.DeviceGroup.Id, this.stop_counter);

            if (this.loop == null) {
            this.loop = new MainLoop (this.context, false);
            try {
                this.worker_thread = new Thread<void*>.try ("EPG-Worker-Thread", this.worker);
            } catch (Error e) {
                log.error ("Could not create thread: %s", e.message);
                return false;
            }
            }

            this.stop_counter -= 1;
            if (this.stop_counter > 0) return false;
            this.stop_counter = 0;

            foreach (Channel c in this.DeviceGroup.Channels) {
                this.channels.push_tail (c);
            }

            if (!setup_pipeline ()) return false;

            this.scan_source = new TimeoutSource.seconds (WAIT_FOR_EIT_DURATION);
            this.scan_source.set_callback (this.scan_new_frequency);
            this.scan_source.attach (this.context);

            return false;
        }

        /**
         * Scan the next frequency for EPG data
         */
        private bool scan_new_frequency () {
            lock (this.channel_events) {
                foreach (uint sid in this.channel_events.keys) {
                    Channel channel = this.DeviceGroup.Channels.get_channel (sid);
                    if (channel == null) {
                        warning ("Could not find channel %u for this device", sid);
                        continue;
                    }
                    HashSet<Event> list = this.channel_events.get (sid);

                    log.debug ("Adding %d events of channel %s (%u)",
                        list.size, channel.Name, sid);
                    channel.Schedule.add_all (list);
                }
                this.channel_events.clear ();
            }

            if (this.channels.is_empty ()) {
                log.debug ("Finished EPG scan for group %u", this.DeviceGroup.Id);

                this.reset ();
                // Time the next iteration
                this.queue_source = new TimeoutSource.seconds (CHECK_EIT_INTERVAL);
                this.queue_source.set_callback (this.start);
                this.queue_source.attach (this.context);
                return false;
            }

            Channel channel = this.channels.pop_head ();
            channel.Schedule.remove_expired_events ();
/*
            log.debug ("Scanning channel %s (%u left)",
                channel.Name, this.channels.get_length ());
*/
            lock (this.pipeline) {
                this.pipeline.set_state (Gst.State.READY);
                Gst.Element dvbsrc = ((Gst.Bin)this.pipeline).get_by_name ("dvbsrc");
                channel.setup_dvb_source (dvbsrc);

                this.pipeline.set_state (Gst.State.PLAYING);
            }

            return true;
        }

        private bool bus_watch_func (Gst.Bus bus, Gst.Message message) {
            switch (message.type) {
                case Gst.MessageType.ELEMENT:
                    Gst.Structure structure = message.get_structure ();
                    if (structure.get_name() == "dvb-read-failure") {
                        log.warning ("Could not read from DVB device");
                    } else if (structure.get_name() == "eit") {
                        this.on_eit_structure (structure);
                    }
                break;

                case Gst.MessageType.ERROR:
                    Error gerror;
                    string debug;
                    message.parse_error (out gerror, out debug);
                    log.error ("%s %s", gerror.message, debug);
                    reset_pipeline();
                    if (setup_pipeline()) {
                        return true;
                    } else {
                        reset();
                        return false;
                    }

                default:
                break;
            }
            return true;
        }

        public void on_eit_structure (Gst.Structure structure) {
            Value events = structure.get_value ("events");

            if (!events.holds (typeof(Gst.ValueList)))
                return;

            uint size = Gst.ValueList.get_size (events);
            Value val;
            weak Gst.Structure event;
            // Iterate over events
            lock (this.channel_events) {
                uint sid = get_uint_val (structure, "service-id");
                if (!this.channel_events.has_key (sid)) {
                    this.channel_events.set (sid,
                        new HashSet<Event> (Event.hash, Event.equal));
                }
                HashSet<Event> list = this.channel_events.get (sid);

                for (uint i=0; i<size; i++) {
                    val = Gst.ValueList.get_value (events, i);
                    event = Gst.Value.get_structure (val);

                    var event_class = new Event ();
                    event_class.id = get_uint_val (event, "event-id");
                    event_class.year = get_uint_val (event, "year");
                    event_class.month = get_uint_val (event, "month");
                    event_class.day = get_uint_val (event, "day");
                    event_class.hour = get_uint_val (event, "hour");
                    event_class.minute = get_uint_val (event, "minute");
                    event_class.second = get_uint_val (event, "second");
                    event_class.duration = get_uint_val (event, "duration");

                    if (event_class.has_expired ())
                        continue;

                    event_class.running_status = get_uint_val (event, "running-status");
                    string name = event.get_string ("name");
                    if (name != null && name.validate ())
                        event_class.name = name;
                    string desc = event.get_string ("description");
                    if (desc != null && desc.validate ())
                        event_class.description = desc;
                    string ext_desc = event.get_string ("extended-text");
                    if (ext_desc != null && ext_desc.validate ())
                        event_class.extended_description = ext_desc;
                    bool free_ca;
                    event.get_boolean ("free-ca-mode", out free_ca);
                    event_class.free_ca_mode = free_ca;
/*
                    Value components = event.get_value ("components");
                    add_components (components, event_class);
*/
                    //log.debug ("Adding new event: %s", event_class.to_string ());

                    list.add (event_class);
                }
            }
        }
/*
        private static void add_components (Value components, Event event_class) {
            uint components_len = components.list_get_size ();

            Value comp_val;
            weak Gst.Structure component;
            for (uint j=0; j<components_len; j++) {
                comp_val = components.list_get_value (j);
                component = comp_val.get_structure ();

                string comp_name = component.get_name ();
                if (comp_name == "audio") {
                    var audio = new Event.AudioComponent ();
                    audio.type = component.get_string ("type");

                    event_class.audio_components.append (audio);
                } else if (comp_name == "video") {
                    var video = new Event.VideoComponent ();

                    bool highdef;
                    component.get_boolean ("high-definition", out highdef);
                    video.high_definition = highdef;

                    video.aspect_ratio = component.get_string ("aspect-ratio");

                    int freq;
                    component.get_int ("frequency", out freq);
                    video.frequency = freq;

                    event_class.video_components.append (video);
                } else if (comp_name == "teletext") {
                    var teletext = new Event.TeletextComponent ();
                    teletext.type = component.get_string ("type");

                    event_class.teletext_components.append (teletext);
                }
            }
        }
*/
        private static uint get_uint_val (Gst.Structure structure, string name) {
            uint val;
            structure.get_uint (name, out val);
            return val;
        }
    }
}
