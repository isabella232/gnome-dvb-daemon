/*
 * Copyright (C) 2014 Stefan Ringel
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
using GstMpegTs;
using DVB;

namespace DVB.io {

    public class ScanningListReader : GLib.Object {

        private KeyFile file;
        private string path;
        private List<Parameter> parameters;

        public List<Parameter> Parameters { get { return this.parameters; }}

        public ScanningListReader (string keyfile) {
            this.file = new KeyFile();
            this.path = keyfile;
            this.parameters = new List<Parameter> ();
        }

        public void read_data () throws KeyFileError, FileError {

            // reading data from scanning file

            this.file.load_from_file (this.path, KeyFileFlags.NONE);

            foreach (unowned string group in this.file.get_groups ()) {

                switch (this.file.get_string (group, "DELIVERY_SYSTEM")) {
                    case "DVBT":
                        this.read_dvb_t (group);
                        break;
                    case "DVBC/ANNEX_A":
                        this.read_dvb_c (group);
                        break;
                    case "DVBS":
                        this.read_dvb_s (group);
                        break;
                    default:
                        break;
                }
            }
        }

        private void read_dvb_t (string group) throws KeyFileError, FileError {
            DvbTParameter param = new DvbTParameter.with_parameter (
                (uint)this.file.get_uint64 (group, "FREQUENCY"),
                (uint)this.file.get_uint64 (group, "BANDWIDTH_HZ"),
                getGuardIntervalEnum (this.file.get_string (group, "GUARD_INTERVAL")),
                getTransmissionModeEnum (this.file.get_string (group, "TRANSMISSION_MODE")),
                getHierarchyEnum (this.file.get_string (group, "HIERARCHY")),
                getModulationEnum (this.file.get_string (group, "MODULATION")),
                getCodeRateEnum (this.file.get_string (group, "CODE_RATE_LP")),
                getCodeRateEnum (this.file.get_string (group, "CODE_RATE_HP")));

            this.parameters.append (param);
        }

        private void read_dvb_c (string group) throws KeyFileError, FileError {
            DvbCEuropeParameter param = new DvbCEuropeParameter.with_parameter (
                (uint)this.file.get_uint64 (group, "FREQUENCY"),
                (uint)this.file.get_uint64 (group, "SYMBOL_RATE"),
                getModulationEnum (this.file.get_string (group, "MODULATION")),
                getCodeRateEnum (this.file.get_string (group, "INNER_FEC")));

            this.parameters.append (param);
        }

        private void read_dvb_s (string group) throws KeyFileError, FileError {
            DvbSParameter param = new DvbSParameter.with_parameter (
                (uint)this.file.get_uint64 (group, "FREQUENCY"),
                (uint)this.file.get_uint64 (group, "SYMBOL_RATE"),
                (float)this.file.get_double (group, "ORBITAL_POSITION"),
                getPolarizationEnum (this.file.get_string (group, "POLARIZATION")),
                getCodeRateEnum (this.file.get_string (group, "INNER_FEC")));

            if (this.file.has_key (group, "SAT_NUMBER"))
                param.DiseqcSource = this.file.get_integer (group, "SAT_NUMBER");

            this.parameters.append (param);
        }

    }
}
