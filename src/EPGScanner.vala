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
using GstMpegts;

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
        "dvbsrc name=dvbsrc adapter=%u frontend=%u pids=0:16:17:18 stats-reporting-interval=0 ! tsparse ! fakesink silent=true";

        private DVB.DeviceGroup DeviceGroup;

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
            ChannelList clist = this.DeviceGroup.Channels;
            if (clist == null)
                return false;

            lock (this.channel_events) {
                foreach (uint sid in this.channel_events.keys) {
                    Channel channel = clist.get_channel (sid);
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
                    Section section = message_parse_mpegts_section (message);

                    if (section == null) {
                        unowned Gst.Structure structure = message.get_structure ();
                        if (structure.get_name() == "dvb-read-failure") {
                            log.warning ("Could not read from DVB device");
                        }
                    } else if (section.section_type == SectionType.EIT) {
                        this.on_eit_structure (section);
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

        public void on_eit_structure (Section section) {

            unowned EIT eit = section.get_eit();

            lock (this.channel_events) {
                uint sid = section.subtable_extension;

                if (!this.channel_events.has_key (sid)) {
                    this.channel_events.set (sid,
                        new HashSet<Event> (Event.hash, Event.equal));
                }
                HashSet<Event> list = this.channel_events.get (sid);

                EITEvent event;
                uint len = eit.events.length;
                for (uint i = 0; i < len; i++) {
                    event = eit.events.@get(i);
                    var event_class = new Event ();

                    event_class.id = event.event_id;
                    event_class.year = event.start_time.get_year ();
                    event_class.month = event.start_time.get_month ();
                    event_class.day = event.start_time.get_day ();
                    event_class.hour = event.start_time.get_hour ();
                    event_class.minute = event.start_time.get_minute ();
                    event_class.second = event.start_time.get_second ();
                    event_class.duration = event.duration;

                    if (event_class.has_expired ())
                        continue;

                    event_class.running_status = event.running_status;
                    event_class.free_ca_mode = event.free_CA_mode;

                    Descriptor desc;
                    for (uint j = 0 ;j < event.descriptors.length; j++) {
                         desc = event.descriptors.@get (j);

                         switch (desc.tag) {
                            case DVBDescriptorType.SHORT_EVENT:
                                string lang;
                                desc.parse_dvb_short_event ( out lang,
                                out event_class.name,
                                out event_class.description);
                                break;
                            case DVBDescriptorType.EXTENDED_EVENT:
                                ExtendedEventDescriptor ex_desc;

                                if (!desc.parse_dvb_extended_event (out ex_desc))
                                    log.debug ("Failed parse extended Event");

                                var builder = new StringBuilder ();
                                if (event_class.extended_description != null)
                                    builder.append (event_class.extended_description);
                                builder.append (ex_desc.text);
                                event_class.extended_description = builder.str;

                                break;
                            case DVBDescriptorType.COMPONENT:
                                ComponentDescriptor comp;

                                desc.parse_dvb_component(out comp);

                                decode_component (comp, event_class);
                                break;
                            case DVBDescriptorType.CONTENT:
                                GenericArray<Content?> conts;

                                desc.parse_dvb_content(out conts);
                                if (conts.length != 0) {
                                    for (uint k = 0; k < conts.length; k++) {
                                        Content cont = conts.@get(k);
                                        log.debug ("0x%01x, 0x%01x, 0x%02x",
                                            cont.content_nibble_1,
                                            cont.content_nibble_2,
                                            cont.user_byte);
                                    }
                                }
                                break;
                            default:
                                log.debug ("Unkown descriptor: 0x%02x",
                                    desc.tag);
                                break;
                        }

                    }

                    log.debug ("Adding new event: %s", event_class.to_string ());
                    list.add (event_class);

                }
            }
        }

        private static void decode_component (ComponentDescriptor comp, Event event_class)
        {

            switch (comp.stream_content) {
                case 0x01:
                case 0x05:
                    var video = new Event.VideoComponent ();

                    /* hd flag */
                    switch (comp.component_type) {
                        case 0x09:
                        case 0x0a:
                        case 0x0b:
                        case 0x0c:
                        case 0x0d:
                        case 0x0e:
                        case 0x0f:
                        case 0x10:
                        case 0x80:
                        case 0x81:
                        case 0x82:
                        case 0x83:
                        case 0x84:
                            video.has_hd = true;
                            break;
                        default:
                            video.has_hd = false;
                            break;
                    }

                    /* 3d flag */
                    switch (comp.component_type) {
                        case 0x80:
                        case 0x81:
                        case 0x82:
                        case 0x83:
                        case 0x84:
                            video.has_3d = true;
                            break;
                        default:
                            video.has_3d = false;
                            break;
                    }

                    /* aspect radio
                       passible value are
                       4:3, 16:9, 2.21:1
                    */
                    switch (comp.component_type) {
                        case 0x01:
                        case 0x05:
                        case 0x09:
                        case 0x0d:
                            video.aspect_ratio = "4:3";
                            break;
                        case 0x02:
                        case 0x06:
                        case 0x0a:
                        case 0x0e:
                            video.aspect_ratio = "16:9 with pan";
                            break;
                        case 0x03:
                        case 0x07:
                        case 0x0b:
                        case 0x0f:
                        case 0x80:
                        case 0x81:
                        case 0x82:
                        case 0x83:
                        case 0x84:
                            video.aspect_ratio = "16:9";
                            break;
                        case 0x04:
                        case 0x08:
                        case 0x0c:
                        case 0x10:
                            video.aspect_ratio = "2.21:1";
                            break;
                        default:
                            video.aspect_ratio = "unknown";
                            break;
                        }

                        switch (comp.component_type) {
                            case 0x05:
                            case 0x06:
                            case 0x07:
                            case 0x08:
                            case 0x0d:
                            case 0x0e:
                            case 0x0f:
                            case 0x10:
                            case 0x82:
                            case 0x83:
                                video.frequency = 30;
                                break;
                            default:
                                video.frequency = 25;
                                break;
                        }
                        if (comp.stream_content == 0x01)
                            video.content = "MPEG-2";
                        else
                            video.content = "AVC/MVC";
                        video.type = comp.component_type.to_string("0x%02x");
                        video.tag = comp.component_tag;
                        video.text = comp.text;
                        event_class.video_component =  video;
                        break;
                    case 0x02:
                    case 0x04:
                    case 0x06:
                    case 0x07:
                        var audio = new Event.AudioComponent ();

                        switch (comp.stream_content) {
                            case 0x02:
                                audio.content = "MPEG-1 Layer 2";
                                break;
                            case 0x04:
                                audio.content = "AC-3";
                                break;
                            case 0x06:
                                audio.content = "HE-AAC/HE-AACv2";
                                break;
                            case 0x07:
                                audio.content = "DTS";
                                break;
                        }

                        audio.type = comp.component_type.to_string("0x%02x");
                        audio.tag = comp.component_tag;
                        audio.text = comp.text;
                        audio.language = comp.language_code;
                        event_class.audio_components.append (audio);
                        break;
                    case 0x03:
                        var teletext = new Event.TeletextComponent ();

                        teletext.type = comp.component_type.to_string("0x%02x");
                        teletext.tag = comp.component_tag;
                        teletext.text = comp.text;
                        event_class.teletext_components.append (teletext);
                        break;
                    default:
                        break;
              }
        }

    }
}
