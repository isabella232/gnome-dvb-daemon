/*
 * DvbSParameter.vala
 *
 * Copyright (C) 2014 Stefan Ringel
 *
 * GNOME DVB Daemon is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * GNOME DVB Daemon is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with GNOME DVB Daemon.  If not, see <http://www.gnu.org/licenses/>.
 */

using GLib;
using GstMpegts;
using DVB.Logging;

namespace DVB {
    public class DvbSParameter : Parameter {
        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        public uint SymbolRate { get; private set; }
        public float OrbitalPosition { get; private set; }
        public SatellitePolarizationType Polarization { get; private set; }
        public int DiseqcSource { get; set; }
        public DVBCodeRate InnerFEC { get; private set; }

        // Constructor
        public DvbSParameter () {
            base (DvbSrcDelsys.SYS_DVBS);
            this.DiseqcSource = -1;
        }

        public DvbSParameter.with_parameter (uint frequency, uint symbol_rate,
                float position, SatellitePolarizationType polarization,
                DVBCodeRate inner_fec) {
            base (DvbSrcDelsys.SYS_DVBS);
            this.Frequency = frequency;
            this.SymbolRate = symbol_rate;
            this.OrbitalPosition = position;
            this.Polarization = polarization;
            this.InnerFEC = inner_fec;
            this.DiseqcSource = -1;
        }

        public override bool add_scanning_data (HashTable<string, Variant> data) {

            unowned Variant _var;

            _var = data.lookup ("frequency");
            if (_var == null)
                return false;
            this.Frequency = _var.get_uint32 ();

            _var = data.lookup ("symbol-rate");
            if (_var == null)
                return false;
            this.SymbolRate = _var.get_uint32 ();

            _var = data.lookup ("polarization");
            if (_var == null)
                return false;
            this.Polarization = getPolarizationEnum (_var.get_string ());

            _var = data.lookup ("inner-fec");
            if (_var == null)
                return false;
            this.InnerFEC = getCodeRateEnum (_var.get_string ());

            _var = data.lookup ("orbital-position");
            if (_var == null)
                return false;
            this.OrbitalPosition = (float)_var.get_double ();

            _var = data.lookup ("diseqc-source");
            if (_var == null)
                return false;
            this.DiseqcSource = (int)_var.get_int16 ();

            return true;
        }

        public override bool equal (Parameter param) {
            if (param == null)
                return false;

            if (param.Delsys != this.Delsys)
                return false;

            DvbSParameter sparam = (DvbSParameter)param;

            if (sparam.Frequency == this.Frequency &&
                sparam.SymbolRate == this.SymbolRate &&
                sparam.InnerFEC == this.InnerFEC &&
                sparam.Polarization == this.Polarization &&
                sparam.OrbitalPosition == this.OrbitalPosition &&
                sparam.DiseqcSource == this.DiseqcSource)
                return true;

            return false;
        }

        public override void prepare (Gst.Element source) {
            log.debug ("Prepare DVB-S Scanning Parameter");
            source.set ("frequency", this.Frequency);
            source.set ("symbol-rate", this.SymbolRate);
            switch (this.Polarization) {
                case SatellitePolarizationType.LINEAR_HORIZONTAL:
                    source.set ("polarity", "H");
                    break;
                case SatellitePolarizationType.LINEAR_VERTICAL:
                    source.set ("polarity", "V");
                    break;
                default:
                    break;
            }
            source.set ("code-rate-hp", this.InnerFEC);
            source.set ("diseqc-source", this.DiseqcSource);
            source.set ("delsys", this.Delsys);
        }

        public override string to_string () {
            return "DVBS:%f:%d:%u:%u:%s:%s".printf (this.OrbitalPosition, this.DiseqcSource,
                this.Frequency, this.SymbolRate, getCodeRateString (this.InnerFEC),
                getPolarizationString (this.Polarization));
        }
    }
}
