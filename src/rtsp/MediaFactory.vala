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
using DVB.Logging;

namespace DVB {

    public class MediaFactory : Gst.RTSPMediaFactory {

        private static Logger log = LogManager.getLogManager().getDefaultLogger();
        private DeviceGroup group;
        private Channel channel;
        private Gst.Element payloader;
        private PlayerThread player;

        construct {
            this.set_shared (true);
        }

        private void on_media_unprepared () {
            ChannelFactory channels_factory = this.group.channel_factory;
            channels_factory.stop_channel (this.channel, this.payloader);
            this.group = null;
            this.channel = null;
            this.payloader = null;
            this.player = null;
        }

        public override Gst.Element? create_element (Gst.RTSP.Url url) {
            uint sidnr = 0;
            uint grpnr = 0;
            log.debug ("create element");
            string[] path_elements = url.abspath.split ("/");
            int i = 0;
            string elem;
            while ((elem = path_elements[i]) != null) {
                if (i == 1)
                    grpnr = (uint)int.parse (elem);
                else if (i == 2)
                    sidnr = (uint)int.parse (elem);

                i++;
            }

            Manager manager = Manager.get_instance();

            this.group = manager.get_device_group_if_exists (grpnr);
            if (this.group == null) {
                warning ("Unknown group %u", grpnr);
                return null;
            }

            this.payloader = Gst.ElementFactory.make ("rtpmp2tpay", "pay0");
            if (this.payloader == null) {
                log.error ("Could not create rtpmp2tpay element");
                return null;
            }
            this.payloader.set ("pt", 96);

            this.channel = this.group.Channels.get_channel (sidnr);
            if (this.channel == null) {
                log.error ("No channel with SID %u", sidnr);
                return null;
            }
            ChannelFactory channels_factory = this.group.channel_factory;

            this.player = channels_factory.watch_channel (this.channel,
                this.payloader, false, DVB.RTSPServer.stop_streaming);
            if (this.player == null) {
               log.debug ("Could not create player");
               return null;
            }
            log.debug ("Retrieving sink bin with payloader");

            return this.player.get_sink_bin (sidnr, this.payloader);
        }

        protected override Gst.Element? create_pipeline (Gst.RTSPMedia media) {
            log.debug ("create pipeline");
            Gst.Element pipeline = this.player.get_pipeline ();

            media.unprepared.connect (this.on_media_unprepared);
            media.take_pipeline ((Gst.Pipeline)pipeline);

            return pipeline;
        }
    }
}
