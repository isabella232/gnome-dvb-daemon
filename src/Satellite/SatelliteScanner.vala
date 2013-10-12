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

    [DBus (name = "org.gnome.DVB.Scanner.Satellite")]
    public interface IDBusSatelliteScanner : GLib.Object {

        public abstract signal void frequency_scanned (uint frequency, uint freq_left);
        public abstract signal void finished ();
        public abstract signal void channel_added (uint frequency, uint sid,
            string name, string network, string type, bool scrambled);
        public abstract signal void frontend_stats (double signal_strength,
            double signal_noise_ratio);

        public abstract void Run () throws DBusError;
        public abstract void Destroy () throws DBusError;
        public abstract bool WriteAllChannelsToFile (string path) throws DBusError;
        public abstract bool WriteChannelsToFile (uint[] channel_sids, string path) throws DBusError;

        public abstract void AddScanningData (uint frequency,
                                     string polarization, // "horizontal", "vertical"
                                     uint symbol_rate) throws DBusError;

        /**
         * @path: Path to file containing scanning data
         * @returns: TRUE when the file has been parsed successfully
         *
         * Parses initial tuning data from a file as provided by dvb-apps
         */
        public abstract bool AddScanningDataFromFile (string path) throws DBusError;
    }

    public class SatelliteScanner : Scanner, IDBusScanner {

        public SatelliteScanner (DVB.Device device) {
            Object (Device: device);
        }

        public bool AddScanningData (GLib.HashTable<string, Variant> data) throws DBusError
         {
            uint frequency, symbol_rate;
            string polarization;

            unowned Variant _var;

            _var = data.lookup ("frequency");
            if (_var == null)
                return false;
            frequency = _var.get_uint32 ();

            _var = data.lookup ("symbol-rate");
            if (_var == null)
                return false;
            symbol_rate = _var.get_uint32 ();

            _var = data.lookup ("polarization");
            if (_var == null)
                return false;
            polarization = _var.get_string ();

            this.add_scanning_data (frequency, polarization, symbol_rate);
            return true;
        }

        private inline void add_scanning_data (uint frequency,
                string polarization, uint symbol_rate) {
            var tuning_params = new Gst.Structure.empty ("tuning_params");
            tuning_params.set_value ("frequency", frequency);
            tuning_params.set_value ("symbol-rate", symbol_rate);
            tuning_params.set_value ("polarization", polarization);

            base.add_structure_to_scan ((owned) tuning_params);
        }

        protected override void add_scanning_data_from_string (string line) {
            // line looks like:
            // S freq pol sr fec
            string[] cols = Regex.split_simple ("\\s+", line);

            if (cols.length < 5) return;

            uint freq = (uint)int.parse (cols[1]);
            uint symbol_rate = (uint)(int.parse (cols[3]) / 1000);

            string pol;
            string lower_pol = cols[2].down ();
            if (lower_pol == "h")
                pol = "horizontal";
            else if (lower_pol == "v")
                pol = "vertical";
            else
                return;

            // TODO what about fec?

            this.add_scanning_data (freq, pol, symbol_rate);
        }

        protected override void prepare () {
            debug("Setting up pipeline for DVB-S scan");

            Gst.Element dvbsrc = ((Gst.Bin)base.pipeline).get_by_name ("dvbsrc");

            string[] uint_keys = new string[] {"frequency", "symbol-rate"};

            foreach (string key in uint_keys) {
                set_uint_property (dvbsrc, base.current_tuning_params, key);
            }

            string polarity =
                base.current_tuning_params.get_string ("polarization")
                .substring (0, 1);
            dvbsrc.set ("polarity", polarity);

            uint code_rate;
            base.current_tuning_params.get_uint ("inner-fec", out code_rate);
            dvbsrc.set ("code-rate-hp", code_rate);
        }

        protected override ScannedItem get_scanned_item (Gst.Structure structure) {
            // dup string because get_string returns weak string
            string pol = "%s".printf (
                structure.get_string ("polarization"));

            uint freq;
            structure.get_uint ("frequency", out freq);
            return new ScannedSatteliteItem (freq, pol);
        }

        protected override Channel get_new_channel () {
            return new SatelliteChannel.without_schedule ();
        }

        protected override void add_values_from_structure_to_channel (
            Gst.Structure delivery, Channel channel) {
            if (!(channel is SatelliteChannel)) return;

            SatelliteChannel sc = (SatelliteChannel)channel;

            uint freq;
            delivery.get_uint ("frequency", out freq);
            sc.Frequency = freq;

            sc.Polarization = delivery.get_string ("polarization").substring (0, 1);

            uint srate;
            delivery.get_uint ("symbol-rate", out srate);
            sc.SymbolRate = srate;

            // TODO
            sc.DiseqcSource = -1;
        }
    }

}
