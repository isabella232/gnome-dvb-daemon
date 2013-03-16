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

    public class TerrestrialScanner : Scanner, IDBusScanner {

        public TerrestrialScanner (DVB.Device device) {
            Object (Device: device);
        }

        /**
          * See enums in MpegTsEnums
          */
        public bool AddScanningData (GLib.HashTable<string, Variant> data)
                throws DBusError
        {
            uint frequency, hierarchy, bandwidth, guard;
            string transmode, code_rate_hp, code_rate_lp, constellation;

            unowned Variant _var;

            _var = data.lookup ("frequency");
            if (_var == null)
                return false;
            frequency = _var.get_uint32 ();

            _var = data.lookup ("hierarchy");
            if (_var == null)
                return false;
            hierarchy = _var.get_uint32 ();

            _var = data.lookup ("bandwidth");
            if (_var == null)
                return false;
            bandwidth = _var.get_uint32 ();

            _var = data.lookup ("transmission-mode");
            if (_var == null)
                return false;
            transmode = _var.get_string ();

            _var = data.lookup ("code-rate-hp");
            if (_var == null)
                return false;
            code_rate_hp = _var.get_string ();

            _var = data.lookup ("code-rate-lp");
            if (_var == null)
                return false;
            code_rate_lp = _var.get_string ();

            _var = data.lookup ("constellation");
            if (_var == null)
                return false;
            constellation = _var.get_string ();

            _var = data.lookup ("guard-interval");
            if (_var == null)
                return false;
            guard = _var.get_uint32 ();

            this.add_scanning_data (frequency, hierarchy,
                bandwidth, transmode, code_rate_hp,
                code_rate_lp, constellation, guard);
            return true;
        }

        private inline void add_scanning_data (uint frequency, uint hierarchy,
                uint bandwidth, string transmode, string code_rate_hp,
                string code_rate_lp, string constellation, uint guard) {

            Gst.Structure tuning_params = new Gst.Structure.empty ("tuning_params");
            tuning_params.set_value ("frequency", frequency);
            tuning_params.set_value ("hierarchy", hierarchy);
            tuning_params.set_value ("bandwidth", bandwidth);
            tuning_params.set_value ("ransmission-mode", transmode);
            tuning_params.set_value ("code-rate-hp", code_rate_hp);
            tuning_params.set_value ("code-rate-lp", code_rate_lp);
            tuning_params.set_value ("constellation", constellation);
            tuning_params.set_value ("guard-interval", guard);

            base.add_structure_to_scan (tuning_params);
        }

        protected override void add_scanning_data_from_string (string line) {
        	// line looks like:
            // T freq bw fec_hi fec_lo mod transmission-mode guard-interval hierarchy

            string[] cols = Regex.split_simple ("\\s+", line);

            if (cols.length < 9) {
                return;
            }

            uint freq = (uint)int.parse (cols[1]);

            uint hierarchy = 0;
            if (cols[8] == "1") {
                hierarchy = 1;
            } else if (cols[8] == "2") {
                hierarchy = 2;
            } else if (cols[8] == "4") {
                hierarchy = 3;
            }

            string bandwidth_str = cols[2].split("MHz")[0];
            uint bandwidth = (uint)int.parse (bandwidth_str);
            string transmode = cols[6];
            string code_rate_hp = cols[3];
            string code_rate_lp = cols[4];
            string constellation = cols[5];

            uint guard;
            if (cols[7].index_of ("/") == -1) {
                guard = 0;
            } else {
                string guard_str = cols[7].split("/")[1];
                guard = (uint)int.parse (guard_str);
            }

            this.add_scanning_data (freq, hierarchy,
                bandwidth, transmode, code_rate_hp,
                code_rate_lp, constellation, guard);
        }

        protected override void prepare () {
            debug("Setting up pipeline for DVB-T scan");

            Gst.Element dvbsrc = ((Gst.Bin)base.pipeline).get_by_name ("dvbsrc");

            set_uint_property (dvbsrc, base.current_tuning_params, "frequency");

            uint bandwidth;
            this.current_tuning_params.get_uint ("bandwidth", out bandwidth);
            dvbsrc.set ("bandwidth", get_bandwidth_val (bandwidth));

            uint hierarchy;
            this.current_tuning_params.get_uint ("hierarchy", out hierarchy);
            dvbsrc.set ("hierarchy", get_hierarchy_val (hierarchy));

            string constellation = this.current_tuning_params.get_string ("constellation");
            dvbsrc.set ("modulation", get_modulation_val (constellation));

            dvbsrc.set ("code-rate-hp", get_code_rate_val (
                this.current_tuning_params.get_string ("code-rate-hp")));
            dvbsrc.set ("code-rate-lp", get_code_rate_val (
                this.current_tuning_params.get_string ("code-rate-lp")));

            uint guard;
            this.current_tuning_params.get_uint ("guard-interval", out guard);
            dvbsrc.set ("guard", get_guard_interval_val (guard));

            string transmode = this.current_tuning_params.get_string ("transmission-mode");
            dvbsrc.set ("trans-mode", get_transmission_mode_val (transmode));
        }

        protected override ScannedItem get_scanned_item (Gst.Structure structure) {
            uint freq;
            structure.get_uint ("frequency", out freq);
            return new ScannedItem (freq);
        }

        protected override Channel get_new_channel () {
            return new TerrestrialChannel.without_schedule ();
        }

        protected override void add_values_from_structure_to_channel (
            Gst.Structure delivery, Channel channel) {
            if (!(channel is TerrestrialChannel)) return;

            TerrestrialChannel tc = (TerrestrialChannel)channel;

            // structure doesn't contain information about inversion
            // set it to auto
            tc.Inversion = DvbSrcInversion.INVERSION_AUTO;

            uint freq;
            delivery.get_uint ("frequency", out freq);
            tc.Frequency = freq;

            uint bandwidth;
            delivery.get_uint ("bandwidth", out bandwidth);
            tc.Bandwidth = get_bandwidth_val (bandwidth);

            uint hierarchy;
            delivery.get_uint ("hierarchy", out hierarchy);
            tc.Hierarchy = get_hierarchy_val (hierarchy);

            string constellation = delivery.get_string ("constellation");
            tc.Constellation = get_modulation_val (constellation);

            tc.CodeRateHP = get_code_rate_val (delivery.get_string ("code-rate-hp"));
            tc.CodeRateLP = get_code_rate_val (delivery.get_string ("code-rate-lp"));

            uint guard;
            delivery.get_uint ("guard-interval", out guard);
            tc.GuardInterval = get_guard_interval_val (guard);

            string transmode = delivery.get_string ("transmission-mode");
            tc.TransmissionMode = get_transmission_mode_val (transmode);
        }

    }

}
