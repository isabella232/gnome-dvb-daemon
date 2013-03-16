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
using Gst;
using DVB.Logging;

namespace DVB {

    public errordomain DeviceError {
    	UNKNOWN_TYPE
    }

    public enum AdapterType {
        UNKNOWN,
        DVB_T,
        DVB_S,
        DVB_C
    }

    public class Device : GLib.Object {

        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        private static const int PRIME = 31;

        public uint Adapter { get; construct; }
        public uint Frontend { get; construct; }
        public AdapterType Type {
            get { return adapter_type; }
        }
        public string Name {
            get { return adapter_name; }
        }
        public ChannelList Channels { get; set; }
        public File RecordingsDirectory { get; set; }

        private string adapter_name;
        private AdapterType adapter_type;

        public Device (uint adapter, uint frontend) {
            base (Adapter: adapter, Frontend: frontend);
        }

        public static Device new_set_type (uint adapter, uint frontend,
            File channels_conf, File recordings_dir, string name, AdapterType type) {
            Device dev = new Device (adapter, frontend);
            dev.adapter_name = name;
            dev.adapter_type = type;
            dev.RecordingsDirectory = recordings_dir;
            dev.Channels = new ChannelList (channels_conf);

            return dev;
        }

        public static Device new_with_type (uint adapter, uint frontend) {
        	var device = new Device (adapter, frontend);

            device.setAdapterTypeAndName(adapter, frontend);

            return device;
        }

        public static Device? new_full (uint adapter, uint frontend,
                File channels_conf, File recordings_dir)
                throws DeviceError
        {
            Device device = Device.new_with_type (adapter, frontend);

            /* The type of the device is checked in creation of
             * Device class. If the device does not exist the type
             * will be AdapterType.UNKNOWN
             */
            if (device.Type == AdapterType.UNKNOWN)
                throw new DeviceError.UNKNOWN_TYPE (
                    "device %u,%u has unknown type", adapter, frontend);

            device.RecordingsDirectory = recordings_dir;

            device.Channels = new ChannelList (channels_conf);

            return device;
        }

        public static bool equal (Device dev1, Device dev2) {
            if (dev1 == null || dev2 == null) return false;

            return (dev1.Adapter == dev2.Adapter
                    && dev2.Frontend == dev2.Frontend);
        }

        public static uint hash (Device device) {
            if (device == null) return 0;

            return hash_without_device (device.Adapter, device.Frontend);
        }

        public static uint hash_without_device (uint adapter, uint frontend) {
            return 2 * PRIME + PRIME * adapter + frontend;
        }

        public bool is_busy () {
            Element dvbsrc = ElementFactory.make ("dvbsrc", "text_dvbsrc");
            if (dvbsrc == null) {
                log.error ("Could not create dvbsrc element");
                return true;
            }
            dvbsrc.set ("adapter", this.Adapter);
            dvbsrc.set ("frontend", this.Frontend);

            Element pipeline = new Pipeline ("");
            ((Bin)pipeline).add (dvbsrc);
            pipeline.set_state (State.READY);

            Gst.Bus bus = pipeline.get_bus();

            bool busy_val = false;

            while (bus.have_pending()) {
                Message msg = bus.pop();

                if (msg.type == MessageType.ERROR && msg.src == dvbsrc) {
                    Error gerror;
                    string debug_text;
                    msg.parse_error (out gerror, out debug_text);

                    log.debug ("Error tuning: %s; %s", gerror.message, debug_text);

                    busy_val = true;
                }
            }

            pipeline.set_state(State.NULL);

            return busy_val;
        }

        private bool setAdapterTypeAndName (uint adapter, uint frontend) {
            Element dvbsrc = ElementFactory.make ("dvbsrc", "test_dvbsrc");
            if (dvbsrc == null) {
                log.error ("Could not create dvbsrc element");
                return false;
            }
            dvbsrc.set ("adapter", adapter);
            dvbsrc.set ("frontend", frontend);

            Element pipeline = new Pipeline ("type_name");
            ((Bin)pipeline).add (dvbsrc);
            pipeline.set_state (State.READY);

            Gst.Bus bus = pipeline.get_bus();

            bool success = false;
            string adapter_type = null;

            while (bus.have_pending()) {
                Message msg = bus.pop();

                if (msg.type == MessageType.ELEMENT && msg.src == dvbsrc) {
                    weak Structure structure = msg.get_structure ();

                    if (structure.get_name() == "dvb-adapter") {
                        adapter_type = "%s".printf (structure.get_string("type"));
                        this.adapter_name = "%s".printf (structure.get_string("name"));
                        success = true;
                        break;
                    }
                } else if (msg.type == MessageType.ERROR) {
                    Error gerror;
                    string debug;
                    msg.parse_error (out gerror, out debug);
                    warning ("%s %s", gerror.message, debug);
                }
            }

            pipeline.set_state(State.NULL);

            this.adapter_type = get_type_from_string (adapter_type);

            return success;
        }

        public static AdapterType get_type_from_string (string? adapter_type) {
            if (adapter_type == null)
                return AdapterType.UNKNOWN;

            AdapterType type;
            if (adapter_type == "DVB-T") type = AdapterType.DVB_T;
            else if (adapter_type == "DVB-S") type = AdapterType.DVB_S;
            else if (adapter_type == "DVB-C") type = AdapterType.DVB_C;
            else type = AdapterType.UNKNOWN;
            return type;
        }
    }

}
