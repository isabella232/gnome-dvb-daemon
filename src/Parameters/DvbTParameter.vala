/*
 * DvbTParameter.vala
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
    public class DvbTParameter : Parameter {
        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        public uint Bandwidth { get; private set; }
        public TerrestrialGuardInterval GuardInterval { get; private set; }
        public TerrestrialTransmissionMode TransmissionMode { get; private set; }
        public TerrestrialHierarchy Hierarchy { get; private set; }
        public ModulationType Constellation { get; private set; }
        public DVBCodeRate CodeRateLP { get; private set; }
        public DVBCodeRate CodeRateHP { get; private set; }

        // Constructor
        public DvbTParameter () {
            base (DvbSrcDelsys.SYS_DVBT);
        }

        public DvbTParameter.with_parameter (uint frequency, uint bandwidth,
                TerrestrialGuardInterval interval, TerrestrialTransmissionMode transmission,
                TerrestrialHierarchy hierarchy, ModulationType constellation,
                DVBCodeRate code_rate_lp, DVBCodeRate code_rate_hp) {
            base (DvbSrcDelsys.SYS_DVBT);
            this.Frequency = frequency;
            this.Bandwidth = bandwidth;
            this.GuardInterval = interval;
            this.TransmissionMode = transmission;
            this.Hierarchy = hierarchy;
            this.Constellation = constellation;
            this.CodeRateLP = code_rate_lp;
            this.CodeRateHP = code_rate_hp;
        }

        public override bool add_scanning_data (HashTable<string, Variant> data) {
            unowned Variant _var;

            _var = data.lookup ("frequency");
            if (_var == null)
                return false;
            this.Frequency = _var.get_uint32 ();

            _var = data.lookup ("hierarchy");
            if (_var == null)
               return false;
            this.Hierarchy = getHierarchyEnum (_var.get_string ());

            _var = data.lookup ("bandwidth");
            if (_var == null)
                return false;
            this.Bandwidth = _var.get_uint32 () * 1000000;

            _var = data.lookup ("transmission-mode");
            if (_var == null)
                return false;
            this.TransmissionMode = getTransmissionModeEnum (_var.get_string ());

            _var = data.lookup ("code-rate-hp");
            if (_var == null)
                return false;
            this.CodeRateHP = getCodeRateEnum (_var.get_string ());

            _var = data.lookup ("code-rate-lp");
            if (_var == null)
                return false;
            this.CodeRateLP = getCodeRateEnum (_var.get_string ());

            _var = data.lookup ("constellation");
            if (_var == null)
                return false;
            this.Constellation = getModulationEnum (_var.get_string ());

            _var = data.lookup ("guard-interval");
            if (_var == null)
                return false;
            this.GuardInterval = getGuardIntervalEnum (_var.get_string ());

            return true;
        }

        public override bool equal (Parameter param) {
            if (param == null)
                return false;

            if (param.Delsys != this.Delsys)
                return false;

            DvbTParameter tparam = (DvbTParameter)param;

            if (tparam.Frequency == this.Frequency &&
                tparam.Bandwidth == this.Bandwidth &&
                tparam.Hierarchy == this.Hierarchy &&
                tparam.TransmissionMode == this.TransmissionMode &&
                tparam.CodeRateHP == this.CodeRateHP &&
                tparam.CodeRateLP == this.CodeRateLP &&
                tparam.Constellation == this.Constellation &&
                tparam.GuardInterval == this.GuardInterval)
                return true;

            return false;
        }

        public override void prepare (Gst.Element source) {
            log.debug ("Prepare DVB-T Scanning Parameter");
            source.set ("frequency", this.Frequency);
            source.set ("bandwidth-hz", this.Bandwidth);
            source.set ("hierarchy", this.Hierarchy);
            source.set ("modulation", this.Constellation);
            source.set ("code-rate-hp", this.CodeRateHP);
            source.set ("code-rate-lp", this.CodeRateLP);
            source.set ("guard", this.GuardInterval);
            source.set ("trans-mode", this.TransmissionMode);
            source.set ("delsys", this.Delsys);

        }

        public override string to_string () {
            return "DVBT:%u:%u:%s:%s:%s:%s:%s:%s".printf (this.Frequency, this.Bandwidth,
                getCodeRateString (this.CodeRateLP), getCodeRateString (this.CodeRateHP),
                getModulationString (this.Constellation), getTransmissionModeString (this.TransmissionMode),
                getGuardIntervalString (this.GuardInterval), getHierarchyString (this.Hierarchy));
        }
    }
}

