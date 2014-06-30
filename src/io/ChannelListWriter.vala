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
using DVB.Logging;
using GstMpegts;

namespace DVB.io {

    /**
     * Example:
     * try {
     *     var writer = new DVB.ChannelListWriter (File.new_for_path ("/path/to/channels.conf"));
     *     foreach (DVB.Channel c in reader.Channels) {
     *         writer.write (c);
     *     }
     *     writer.close ();
     * } catch (IOError e) {
     *     error (e.message);
     * }
     */
    public class ChannelListWriter : GLib.Object {

        public File file { get; construct; }

        private KeyFile keyfile;

        private OutputStream stream;

        private void open () throws Error {

            if (this.keyfile != null)
                return;

            this.keyfile = new KeyFile ();
            this.keyfile.set_list_separator (' ');

            FileOutputStream fostream = null;

            if (file.query_exists (null)) {
                fostream = this.file.replace (null, true, 0, null);
            } else {
                fostream = this.file.create (0, null);
            }

            this.stream = new BufferedOutputStream (fostream);
        }

        public ChannelListWriter (File file) {
            base (file: file);
        }

        public void write (Channel channel) throws Error {

            if (this.keyfile == null) this.open ();
            if (this.keyfile == null) return;

            switch (channel.Param.Delsys) {
                case DvbSrcDelsys.SYS_DVBT:
                    this.write_terrestrial_channel (channel);
                    break;
                case DvbSrcDelsys.SYS_DVBC_ANNEX_A:
                    this.write_cable_channel (channel);
                    break;
                case DvbSrcDelsys.SYS_DVBS:
                    this.write_satellite_channel (channel);
                    break;
                default:
                    return;
            }

            this.keyfile.set_uint64 (channel.Name, "SERVICE_ID", channel.Sid);
            this.keyfile.set_uint64 (channel.Name, "SERVICE_TYPE", channel.ServiceType);
            /* should remove ? */
            if (channel.VideoPID != 0)
                this.keyfile.set_uint64 (channel.Name, "VIDEO_PID", channel.VideoPID);
            /* should remove ? */
            if (channel.AudioPIDs.size > 0) {
                int[] apid = new int[channel.AudioPIDs.size];
                for (int i = 0; i < channel.AudioPIDs.size; i++) {
                    apid[i] = (int)channel.AudioPIDs.@get(i);
                }
                this.keyfile.set_integer_list (channel.Name, "AUDIO_PID", apid);
            }
            this.keyfile.set_boolean (channel.Name, "SCRAMBLED", channel.Scrambled);
            this.keyfile.set_string (channel.Name, "PROVIDER", channel.Network);
            this.keyfile.set_string (channel.Name, "SERVICE_NAME", channel.Name);
            this.keyfile.set_uint64 (channel.Name, "TRANSPORT_STREAM_ID", channel.TransportStreamId);
        }

        public bool close () throws Error {
          if (this.keyfile != null) {
              // write now data
              this.stream.write_all (this.keyfile.to_data ().data, null, null);
              this.keyfile = null;
          }

          if (this.stream == null) return true;

          return this.stream.close (null);

        }

        private void write_terrestrial_channel (Channel channel) throws Error {
            // write channel data
            DvbTParameter param = (DvbTParameter)channel.Param;

            this.keyfile.set_string (channel.Name, "DELIVERY_SYSTEM", "DVBT");
            this.keyfile.set_uint64 (channel.Name, "FREQUENCY", param.Frequency);
            this.keyfile.set_uint64 (channel.Name, "BANDWIDTH_HZ", param.Bandwidth);
            this.keyfile.set_string (channel.Name, "MODULATION", getModulationString (param.Constellation));
            this.keyfile.set_string (channel.Name, "CODE_RATE_HP", getCodeRateString (param.CodeRateHP));
            this.keyfile.set_string (channel.Name, "CODE_RATE_LP", getCodeRateString (param.CodeRateLP));
            this.keyfile.set_string (channel.Name, "GUARD_INTERVAL", getGuardIntervalString (param.GuardInterval));
            this.keyfile.set_string (channel.Name, "TRANSMISSION_MODE", getTransmissionModeString (param.TransmissionMode));
            this.keyfile.set_string (channel.Name, "HIERARCHY", getHierarchyString (param.Hierarchy));
        }

        private void write_satellite_channel (Channel channel) throws Error {
            // write channel data
            DvbSParameter param = (DvbSParameter)channel.Param;

            this.keyfile.set_string (channel.Name, "DELIVERY_SYSTEM", "DVBS");
            this.keyfile.set_uint64 (channel.Name, "FREQUENCY", param.Frequency);
            this.keyfile.set_uint64 (channel.Name, "SYMBOL_RATE", param.SymbolRate);
            this.keyfile.set_string (channel.Name, "INNER_FEC", getCodeRateString (param.InnerFEC));
            this.keyfile.set_string (channel.Name, "POLARIZATION", getPolarizationString (param.Polarization));
            this.keyfile.set_double (channel.Name, "ORBITAL_POSITION", (double)param.OrbitalPosition);
            if (param.DiseqcSource > -1)
                this.keyfile.set_uint64 (channel.Name, "SAT_NUMBER", param.DiseqcSource);
        }

        private void write_cable_channel (Channel channel) throws Error {
            // write channel data
            DvbCEuropeParameter param = (DvbCEuropeParameter)channel.Param;

            this.keyfile.set_string (channel.Name, "DELIVERY_SYSTEM", "DVBC/ANNEX_A");
            this.keyfile.set_uint64 (channel.Name, "FREQUENCY", param.Frequency);
            this.keyfile.set_uint64 (channel.Name, "SYMBOL_RATE", param.SymbolRate);
            this.keyfile.set_string (channel.Name, "INNER_FEC", getCodeRateString (param.InnerFEC));
            this.keyfile.set_string (channel.Name, "MODULATION", getModulationString (param.Modulation));

       }

    }

}
