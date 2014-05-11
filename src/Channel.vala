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
using GstMpegTs;

namespace DVB {

    public class Channel : GLib.Object {

        public uint Sid {
            get { return this.sid; }
            set {
                this.sid = value;
                if (this.has_schedule) {
                    this.schedule = new DVB.Schedule (this);
                    this.schedule.restore.begin ();
                }
            }
        }
        /* delivery system depending settings */
        public Parameter Param { get; set; }
        public uint GroupId {get; construct;}
        public string Name {get; set;}
        public DVBServiceType ServiceType { get; set; }
        public uint TransportStreamId {get; set;}
        public string Network {get; set;}
        public uint? LogicalChannelNumber {get; set;}
        public uint VideoPID {get; set;}
        public Gee.List<uint> AudioPIDs {get; set;}
        public bool Scrambled {get; set;}
        public DVB.Schedule Schedule {
            get { return this.schedule; }
        }
        public string URL {
            owned get {
                return "rtsp://%s:8554/%u/%u/%s".printf (
                        RTSPServer.get_address (), this.GroupId, this.Sid,
                        Utils.remove_nonalphanums (this.Name));
            }
        }

        private DVB.Schedule schedule;
        private uint sid;
        private bool has_schedule;

        construct {
            this.AudioPIDs = new Gee.ArrayList<uint> ();
        }

        public Channel (uint group_id) {
            Object (GroupId: group_id);
            this.has_schedule = true;
        }

        public Channel.without_schedule () {
            this.has_schedule = false;
        }

        public string get_audio_pids_string () {
            StringBuilder apids = new StringBuilder ();
            int i = 1;
            foreach (uint pid in this.AudioPIDs) {
                if (i == this.AudioPIDs.size)
                    apids.append (pid.to_string ());
                else
                    apids.append ("%u,".printf (pid));
                i++;
            }

            return apids.str;
        }

        public bool is_radio () {
            return (this.VideoPID == 0);
        }

        public bool is_valid () {
            return (this.Name != null && this.Param.Frequency != 0 && this.Sid != 0
                && (this.VideoPID != 0 || this.AudioPIDs.size != 0));
        }

        /**
         * @returns: TRUE if both channels are part of the same
         * transport stream (TS).
         *
         * Channels that are part of the same TS can be viewed/recorded
         * at the same time with a single device.
         */
        public bool on_same_transport_stream (Channel channel) {
  //          return (this.TransportStreamId == channel.TransportStreamId);
            return (this.Param.Frequency == channel.Param.Frequency);
        }

        /**
         * @returns: TRUE of both channels are identical
         */
        public bool equals (Channel channel) {
            return (this.sid == channel.Sid);
        }

        /**
         * @source: Either dvbbasebin or dvbsrc
         *
         * Set properties of source so that the channel can be watched
         */
        public void setup_dvb_source (Gst.Element source) {
            this.Param.prepare (source);
        }

        public string to_string () {
            return this.Param.to_string () + ":%s:%s:%u:%u:%s".printf(this.Name,
                this.Network, this.Sid, this.VideoPID, get_audio_pids_string ());
        }
    }

}
