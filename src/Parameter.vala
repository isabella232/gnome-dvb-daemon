/*
 * Parameter.vala
 *
 * Copyright (C) 2014 Stefan Ringel <linuxtv@stefanringel.de>
 *
 * This file is part of GNOME DVB Daemon.
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
 * You should have received a copy of the GNU General Public License
 * along with GNOME DVB Daemon.  If not, see <http://www.gnu.org/licenses/>.
 */

using GLib;

namespace DVB {
    /* base class for all tuning parameters */
    public abstract class Parameter : GLib.Object {

        /* delivery system which this tuning parameter has */
        public DvbSrcDelsys Delsys { get; construct; }

        /* center frequency */
        public uint Frequency { get; protected set; }

        // Constructor
        public Parameter (DvbSrcDelsys delsys) {
            base (Delsys: delsys);
        }

        public abstract void prepare (Gst.Element source);

        public abstract bool add_scanning_data (HashTable<string, Variant> data);

        public abstract bool equal (Parameter param);

        public abstract string to_string ();
    }
 }

