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
using GstMpegTs;

namespace DVB {

    public enum DvbSrcDelsys {
        SYS_UNDEFINED,
        SYS_DVBC_ANNEX_A,
        SYS_DVBC_ANNEX_B,
        SYS_DVBT,
        SYS_DSS,
        SYS_DVBS,
        SYS_DVBS2,
        SYS_DVBH,
        SYS_ISDBT,
        SYS_ISDBS,
        SYS_ISDBC,
        SYS_ATSC,
        SYS_ATSCMH,
        SYS_DTMB,
        SYS_CMMB,
        SYS_DAB,
        SYS_DVBT2,
        SYS_TURBO,
        SYS_DVBC_ANNEX_C
    }

   /* mpegts converts */
    private DVBCodeRate getCodeRateEnum (string val) {
            switch (val) {
                case "1/2":
                    return DVBCodeRate.@1_2;
                case "2/3":
                    return DVBCodeRate.@2_3;
                case "2/5":
                    return DVBCodeRate.@2_5;
                case "3/4":
                    return DVBCodeRate.@3_4;
                case "3/5":
                    return DVBCodeRate.@3_5;
                case "4/5":
                    return DVBCodeRate.@4_5;
                case "5/6":
                    return DVBCodeRate.@5_6;
                case "6/7":
                    return DVBCodeRate.@6_7;
                case "7/8":
                    return DVBCodeRate.@7_8;
                case "8/9":
                    return DVBCodeRate.@8_9;
                case "9/10":
                    return DVBCodeRate.@9_10;
                case "NONE":
                    return DVBCodeRate.NONE;
                default:
                    return DVBCodeRate.AUTO;
            }
        }

        private string getCodeRateString (DVBCodeRate val) {
            switch (val) {
                case DVBCodeRate.@1_2:
                    return "1/2";
                case DVBCodeRate.@2_3:
                    return "2/3";
                case DVBCodeRate.@2_5:
                    return "2/5";
                case DVBCodeRate.@3_4:
                    return "3/4";
                case DVBCodeRate.@3_5:
                    return "3/5";
                case DVBCodeRate.@4_5:
                    return "4/5";
                case DVBCodeRate.@5_6:
                    return "5/6";
                case DVBCodeRate.@6_7:
                    return "6/7";
                case DVBCodeRate.@7_8:
                    return "7/8";
                case DVBCodeRate.@8_9:
                    return "8/9";
                case DVBCodeRate.@9_10:
                    return "9/10";
                case DVBCodeRate.NONE:
                    return "NONE";
                case DVBCodeRate.AUTO:
                default:
                    return "AUTO";
            }
        }


        private ModulationType getModulationEnum (string val) {
            switch (val) {
                case "QPSK":
                    return ModulationType.QPSK;
                case "QAM/16":
                    return ModulationType.QAM_16;
                case "QAM/32":
                    return ModulationType.QAM_32;
                case "QAM/64":
                    return ModulationType.QAM_64;
                case "QAM/128":
                    return ModulationType.QAM_128;
                case "QAM/256":
                    return ModulationType.QAM_256;
                case "QAM/AUTO":
                    return ModulationType.QAM_AUTO;
                case "VSB/8":
                    return ModulationType.VSB_8;
                case "VSB/16":
                    return ModulationType.VSB_16;
                case "PSK/8":
                    return ModulationType.PSK_8;
                case "APSK/16":
                    return ModulationType.APSK_16;
                case "APSK/32":
                    return ModulationType.APSK_32;
                case "DQPSK":
                    return ModulationType.DQPSK;
                case "QAM/4_NR":
                    return ModulationType.QAM_4_NR_;
                default:
                    return ModulationType.QAM_AUTO;
            }
        }

        private string getModulationString (ModulationType val) {
            switch (val) {
                case ModulationType.QPSK:
                    return "QPSK";
                case ModulationType.QAM_16:
                    return "QAM/16";
                case ModulationType.QAM_32:
                    return "QAM/32";
                case ModulationType.QAM_64:
                    return "QAM/64";
                case ModulationType.QAM_128:
                    return "QAM/128";
                case ModulationType.QAM_256:
                    return "QAM/256";
                case ModulationType.QAM_AUTO:
                    return "QAM/AUTO";
                case ModulationType.VSB_8:
                    return "VSB/8";
                case ModulationType.VSB_16:
                    return "VSB/16";
                case ModulationType.PSK_8:
                    return "PSK/8";
                case ModulationType.APSK_16:
                    return "APSK/16";
                case ModulationType.APSK_32:
                    return "APSK/32";
                case ModulationType.DQPSK:
                    return "DQPSK";
                case ModulationType.QAM_4_NR_:
                    return "QAM/4_NR";
                default:
                    return "QAM/AUTO";
            }
        }

        private TerrestrialGuardInterval getGuardIntervalEnum (string val) {
            switch (val) {
                case "1/32":
                    return TerrestrialGuardInterval.@1_32;
                case "1/16":
                    return TerrestrialGuardInterval.@1_16;
                case "1/8":
                    return TerrestrialGuardInterval.@1_8;
                case "1/4":
                    return TerrestrialGuardInterval.@1_4;
                case "AUTO":
                    return TerrestrialGuardInterval.AUTO;
                case "1/128":
                    return TerrestrialGuardInterval.@1_128;
                case "19/128":
                    return TerrestrialGuardInterval.@19_128;
                case "19/256":
                    return TerrestrialGuardInterval.@19_256;
                case "PN420":
                    return TerrestrialGuardInterval.PN420;
                case "PN595":
                    return TerrestrialGuardInterval.PN595;
                case "PN945":
                    return TerrestrialGuardInterval.PN945;
                default:
                    return TerrestrialGuardInterval.AUTO;
            }
        }

        private string getGuardIntervalString (TerrestrialGuardInterval val) {
            switch (val) {
                case TerrestrialGuardInterval.@1_32:
                    return "1/32";
                case TerrestrialGuardInterval.@1_16:
                    return "1/16";
                case TerrestrialGuardInterval.@1_8:
                    return "1/8";
                case TerrestrialGuardInterval.@1_4:
                    return "1/4";
                case TerrestrialGuardInterval.AUTO:
                    return "AUTO";
                case TerrestrialGuardInterval.@1_128:
                    return "1/128";
                case TerrestrialGuardInterval.@19_128:
                    return "19/128";
                case TerrestrialGuardInterval.@19_256:
                    return "19/256";
                case TerrestrialGuardInterval.PN420:
                    return "PN420";
                case TerrestrialGuardInterval.PN595:
                    return "PN595";
                case TerrestrialGuardInterval.PN945:
                    return "PN945";
                default:
                    return "AUTO";
            }
        }

        private TerrestrialHierarchy getHierarchyEnum (string val) {
            switch (val) {
                case "NONE":
                    return TerrestrialHierarchy.NONE;
                case "1":
                    return TerrestrialHierarchy.@1;
                case "2":
                    return TerrestrialHierarchy.@2;
                case "4":
                    return TerrestrialHierarchy.@4;
                case "AUTO":
                default:
                    return TerrestrialHierarchy.AUTO;
            }
        }

        private string getHierarchyString (TerrestrialHierarchy val) {
            switch (val) {
                case TerrestrialHierarchy.NONE:
                    return "NONE";
                case TerrestrialHierarchy.@1:
                    return "1";
                case TerrestrialHierarchy.@2:
                    return "2";
                case TerrestrialHierarchy.@4:
                    return "4";
                case TerrestrialHierarchy.AUTO:
                default:
                    return "AUTO";
            }
        }

        private TerrestrialTransmissionMode getTransmissionModeEnum (string val) {
            switch (val) {
                case "2K":
                    return TerrestrialTransmissionMode.@2K;
                case "8K":
                    return TerrestrialTransmissionMode.@8K;
                case "AUTO":
                    return TerrestrialTransmissionMode.AUTO;
                case "4K":
                    return TerrestrialTransmissionMode.@4K;
                case "1K":
                    return TerrestrialTransmissionMode.@1K;
                case "16K":
                    return TerrestrialTransmissionMode.@16K;
                case "32K":
                    return TerrestrialTransmissionMode.@32K;
                case "C1":
                    return TerrestrialTransmissionMode.C1;
                case "C3780":
                    return TerrestrialTransmissionMode.C3780;
                default:
                    return TerrestrialTransmissionMode.AUTO;
            }
        }

        private string getTransmissionModeString (TerrestrialTransmissionMode val) {
            switch (val) {
                case TerrestrialTransmissionMode.@2K:
                    return "2K";
                case TerrestrialTransmissionMode.@8K:
                    return "8K";
                case TerrestrialTransmissionMode.AUTO:
                    return "AUTO";
                case TerrestrialTransmissionMode.@4K:
                    return "4K";
                case TerrestrialTransmissionMode.@1K:
                    return "1K";
                case TerrestrialTransmissionMode.@16K:
                    return "16K";
                case TerrestrialTransmissionMode.@32K:
                    return "32K";
                case TerrestrialTransmissionMode.C1:
                    return "C1";
                case TerrestrialTransmissionMode.C3780:
                    return "C3780";
                default:
                    return "AUTO";
            }
        }

        private SatellitePolarizationType getPolarizationEnum (string val) {
            switch (val) {
                case "VERTICAL":
                    return SatellitePolarizationType.LINEAR_VERTICAL;
                case "HORIZONTAL":
                    return SatellitePolarizationType.LINEAR_HORIZONTAL;
                case "LEFT":
                    return SatellitePolarizationType.CIRCULAR_LEFT;
                case "RIGHT":
                    return SatellitePolarizationType.CIRCULAR_RIGHT;
                default:
                    return SatellitePolarizationType.LINEAR_VERTICAL;
            }
        }

        private string getPolarizationString (SatellitePolarizationType val) {
            switch (val) {
                case SatellitePolarizationType.LINEAR_VERTICAL:
                    return "VERTICAL";
                case SatellitePolarizationType.LINEAR_HORIZONTAL:
                    return "HORIZONTAL";
                case SatellitePolarizationType.CIRCULAR_LEFT:
                    return "LEFT";
                case SatellitePolarizationType.CIRCULAR_RIGHT:
                    return "RIGHT";
                default:
                    return "VERTICAL";
            }
        }

        private bool isSupported (DvbSrcDelsys delsys, AdapterType type) {
            switch (delsys) {
                case DvbSrcDelsys.SYS_DVBC_ANNEX_A:
                case DvbSrcDelsys.SYS_DVBC_ANNEX_B:
                case DvbSrcDelsys.SYS_DVBC_ANNEX_C:
                case DvbSrcDelsys.SYS_ISDBC:
                    return (type == AdapterType.CABLE);
                case DvbSrcDelsys.SYS_DVBT:
                case DvbSrcDelsys.SYS_DVBH:
                case DvbSrcDelsys.SYS_ISDBT:
                case DvbSrcDelsys.SYS_ATSC:
                case DvbSrcDelsys.SYS_ATSCMH:
                case DvbSrcDelsys.SYS_DVBT2:
                    return (type == AdapterType.TERRESTRIAL);
                case DvbSrcDelsys.SYS_DSS:
                case DvbSrcDelsys.SYS_DVBS:
                case DvbSrcDelsys.SYS_DVBS2:
                case DvbSrcDelsys.SYS_TURBO:
                case DvbSrcDelsys.SYS_ISDBS:
                    return (type == AdapterType.SATELLITE);
                case DvbSrcDelsys.SYS_DTMB:
                case DvbSrcDelsys.SYS_CMMB:
                case DvbSrcDelsys.SYS_DAB:
                case DvbSrcDelsys.SYS_UNDEFINED:
                default:
                    return false;
            }
        }
}
