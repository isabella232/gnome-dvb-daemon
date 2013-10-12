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

namespace DVB {

    public class CableScanner : Scanner, IDBusScanner {

        public CableScanner (DVB.Device device) {
            Object (Device: device);
        }

        public bool AddScanningData (GLib.HashTable<string, Variant> data) throws DBusError {
            uint frequency, symbol_rate;
            string modulation, code_rate;

            unowned Variant _var;

            _var = data.lookup ("frequency");
            if (_var == null)
                return false;
            frequency = _var.get_uint32 ();

            _var = data.lookup ("symbol-rate");
            if (_var == null)
                return false;
            symbol_rate = _var.get_uint32 ();

            _var = data.lookup ("inner-fec");
            if (_var == null)
                return false;
            code_rate = _var.get_string ();

            _var = data.lookup ("modulation");
            if (_var == null)
                return false;
            modulation = _var.get_string ();

            this.add_scanning_data (frequency, modulation, symbol_rate, code_rate);
            return true;
        }

        private inline void add_scanning_data (uint frequency, string modulation,
                uint symbol_rate, string code_rate) {
            var tuning_params = new Gst.Structure.empty ("tuning_params");
            tuning_params.set_value ("frequency", frequency);
            tuning_params.set_value ("symbol-rate", symbol_rate);
            tuning_params.set_value ("inner-fec", code_rate);
            tuning_params.set_value ("modulation", modulation);

            base.add_structure_to_scan ((owned) tuning_params);
        }

        protected override void add_scanning_data_from_string (string line) {
            // line looks like:
            // C freq sr fec mod
            string[] cols = Regex.split_simple ("\\s+", line);

            if (cols.length < 5) return;

            uint freq = (uint)int.parse (cols[1]);
            string modulation = cols[4];
            uint symbol_rate = (uint)(int.parse (cols[2]) / 1000);
            string code_rate = cols[3];

            this.add_scanning_data (freq, modulation, symbol_rate, code_rate);
        }

        protected override void prepare () {
            debug("Setting up pipeline for DVB-C scan");

            Gst.Element dvbsrc = ((Gst.Bin)this.pipeline).get_by_name ("dvbsrc");

            string[] keys = new string[] {
                "frequency",
                "symbol-rate"
            };

            foreach (string key in keys) {
                set_uint_property (dvbsrc, this.current_tuning_params, key);
            }

            dvbsrc.set ("modulation",
                get_modulation_val (this.current_tuning_params.get_string ("modulation")));

            dvbsrc.set ("code-rate-hp", get_code_rate_val (
                this.current_tuning_params.get_string ("inner-fec")));
        }

        protected override ScannedItem get_scanned_item (Gst.Structure structure) {
            // TODO
            uint freq;
            structure.get_uint ("frequency", out freq);
            return new ScannedItem (freq);
        }

        protected override Channel get_new_channel () {
            return new CableChannel.without_schedule ();
        }

        protected override void add_values_from_structure_to_channel (
            Gst.Structure delivery, Channel channel) {
            if (!(channel is CableChannel)) return;

            CableChannel cc = (CableChannel)channel;

            // structure doesn't contain information about inversion
            // set it to auto
            cc.Inversion = DvbSrcInversion.INVERSION_AUTO;

            cc.Modulation = get_modulation_val (delivery.get_string ("modulation"));

            uint freq;
            delivery.get_uint ("frequency", out freq);
            cc.Frequency = freq;

            uint symbol_rate;
            delivery.get_uint ("symbol-rate", out symbol_rate);
            cc.SymbolRate = symbol_rate;

            cc.CodeRate = get_code_rate_val (delivery.get_string ("inner-fec"));
        }
    }

}
