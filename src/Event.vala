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

namespace DVB {

    /**
     * Represents an EPG event (i.e. a show with all its information)
     */
    public class Event {

        // See EN 300 486 Table 6
        public static const uint RUNNING_STATUS_UNDEFINED = 0;
        public static const uint RUNNING_STATUS_NOT_RUNNING = 1;
        public static const uint RUNNING_STATUS_STARTS_SOON = 2;
        public static const uint RUNNING_STATUS_PAUSING = 3;
        public static const uint RUNNING_STATUS_RUNNING = 4;

        public uint id;
        /* Time is stored in UTC */
        public uint year;
        public uint month;
        public uint hour;
        public uint day;
        public uint minute;
        public uint second;
        public uint duration; // in seconds
        public uint running_status;
        public bool free_ca_mode;
        public string name;
        public string description;
        public string extended_description;
        /* Components */
        public SList<AudioComponent> audio_components;
        public VideoComponent video_component;
        public SList<TeletextComponent> teletext_components;

        public Event () {
            this.audio_components = new SList<AudioComponent> ();
            this.video_component = null;
            this.teletext_components = new SList<TeletextComponent> ();

            this.year = 0;
            this.month = 0;
            this.hour = 0;
            this.day = 0;
            this.minute = 0;
            this.second = 0;
            this.duration = 0;
            this.running_status = RUNNING_STATUS_UNDEFINED;
        }

        /**
         * Whether the event has started and ended in the past
         */
        public bool has_expired () {
            Time current_utc = Time.gm (time_t ());
            // set day light saving time to undefined
            // otherwise mktime will add an hour,
            // because it respects dst
            current_utc.isdst = -1;

            time_t current_time = current_utc.mktime ();

            time_t end_timestamp = this.get_end_timestamp ();

            return (end_timestamp < current_time);
        }

        public bool is_running () {
            Time time_now = Time.gm (time_t ());
            Time time_start = this.get_utc_start_time ();

            time_t timestamp_now = cUtils.timegm (time_now);
            time_t timestamp_start = cUtils.timegm (time_start);

            if (timestamp_now - timestamp_start >= 0) {
                // Has started, check if it's still running
                return (!this.has_expired ());
            } else {
                // Has not started, yet
                return false;
            }
        }

        public string to_string () {
            string text = "ID: %u\nDate: %04u-%02u-%02u %02u:%02u:%02u\n".printf (this.id,
            this.year, this.month, this.day, this.hour, this.minute, this.second)
            + "Duration: %u\nName: %s\nDescription: %s\n".printf (
            this.duration, this.name, this.description);

            if (this.video_component != null) {
                text += "Video: HD = %s, 3D = %s, Aspect-Ratio = %s, ".printf(this.video_component.has_hd.to_string(),
                        this.video_component.has_3d.to_string(), this.video_component.aspect_ratio);
                text += "Frequency = %s Hz, Type = %s\n".printf(this.video_component.frequency.to_string(),
                        this.video_component.type);
            }
            for (int i=0; i<this.audio_components.length (); i++) {
                text += "Audio: Type = %s, Text = %s\n".printf(this.audio_components.nth_data (i).type, this.audio_components.nth_data(i).text);
            }

            for (int i=0; i<this.teletext_components.length (); i++) {
                text += "Teletext, VBI, Subpicture: Type = %s, Text = %s\n".printf(this.teletext_components.nth_data (i).type,
                         this.teletext_components.nth_data (i).text);
            }
            return text;
        }

        public Time get_local_start_time () {
            // Initialize time zone and set values
            Time utc_time = this.get_utc_start_time ();

            time_t utc_timestamp = cUtils.timegm (utc_time);
            Time local_time = Time.local (utc_timestamp);

            return local_time;
        }

        public Time get_utc_start_time () {
            Time utc_time = Utils.create_utc_time ((int)this.year, (int)this.month,
                (int)this.day, (int)this.hour, (int)this.minute,
                (int)this.second);
            return utc_time;
        }

        public time_t get_start_timestamp () {
            Time utc_time = this.get_utc_start_time ();
            return utc_time.mktime ();
        }

        /**
         * @returns: UNIX time stamp
         */
        public time_t get_end_timestamp () {
            Time end_time = Utils.create_utc_time ((int)this.year, (int)this.month,
                (int)this.day, (int)this.hour, (int)this.minute,
                (int)this.second);

            time_t before = end_time.mktime ();

            end_time.second += (int)this.duration;

            time_t after = end_time.mktime ();

            assert (after - before == this.duration);

            return after;
        }

        public double get_overlap_percentage (Event other) {
            time_t this_start = this.get_start_timestamp ();
            time_t this_end = this.get_end_timestamp ();

            time_t other_start = other.get_start_timestamp ();
            time_t other_end = other.get_end_timestamp ();

            if (this_start <= other_end && this_end >= other_start) {
                time_t start = Utils.t_max (this_start, other_start);
                time_t end = Utils.t_min (this_end, other_end);
                return Math.fabs (start - end) / (this_end - this_start);
            }

            return 0;
        }

        /**
         * @returns: negative value if event1 starts before event2,
         * positive value if event1 starts after event2 and zero else
         *
         * Compare the starting time of two events
         */
        public static int compare (Event* event1, Event* event2) {
            if (event1 == null && event2 == null) return 0;
            else if (event1 == null && event2 != null) return +1;
            else if (event1 != null && event2 == null) return -1;

            time_t event1_time = event1->get_end_timestamp ();
            time_t event2_time = event2->get_end_timestamp ();

            if (event1_time < event2_time) return -1;
            else if (event1_time > event2_time) return +1;
            else return 0;
        }

        /**
         * @returns: TRUE if event1 and event2 represent the same event,
         * else FALSE
         *
         * event1 and event2 must be part of the same transport stream
         */
        public static bool equal (Event event1, Event event2) {
            if (event1 == null || event2 == null) return false;

            return (event1.id == event2.id);
        }

        public static uint hash (Event event) {
            return event.id;
        }

        public class AudioComponent {
            public string type;
            public string language;
            public uint tag;
            public string content;
            public string text;
        }

        public class VideoComponent {
            public bool has_hd;
            public bool has_3d;
            public string aspect_ratio;
            public int frequency;
            public string type;
            public uint tag;
            public string content;
            public string text;
        }

        public class TeletextComponent {
            public string type;
            public string content;
            public uint tag;
            public string text;
        }
    }

}
