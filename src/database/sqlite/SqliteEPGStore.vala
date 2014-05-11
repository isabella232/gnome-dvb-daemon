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
using Gee;
using Sqlite;
using DVB.Logging;

namespace DVB.database.sqlite {

    public class SqliteEPGStore : SqliteDatabase, EPGStore {

        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        private static const int VERSION = 2;

        private static const string CREATE_EVENTS_TABLE_STATEMENT =
            """CREATE TABLE events (group_id INTEGER,
            sid INTEGER,
            event_id INTEGER,
            starttime JULIAN,
            duration INTEGER,
            running_status INTEGER(2),
            free_ca_mode INTEGER(1),
            name VARCHAR(255),
            description VARCHAR(255),
            extended_description TEXT,
            PRIMARY KEY (group_id, sid, event_id))""";

        private static const string INSERT_EVENT_SQL =
            "INSERT INTO events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        private static const string DELETE_EVENT_STATEMENT =
            "DELETE FROM events WHERE group_id=? AND sid=? AND event_id=?";

        private static const string SELECT_ALL_EVENTS_STATEMENT =
            """SELECT event_id, datetime(starttime),
            duration, running_status, free_ca_mode, name,
            description, extended_description
            FROM events WHERE group_id='%u' AND sid='%u'""";

        private static const string SELECT_MINIMAL_EVENTS_STATEMENT =
            """SELECT event_id, datetime(starttime),
            duration FROM events WHERE group_id='%u' AND sid='%u'
            ORDER BY starttime ASC""";

        private static const string HAS_EVENT_STATEMENT =
            "SELECT 1 FROM events WHERE group_id=? AND sid=? AND event_id=? LIMIT 1";

        private static const string UPDATE_EVENT_SQL =
            """UPDATE events SET starttime=?, duration=?, running_status=?,
            free_ca_mode=?, name=?, description=?,
            extended_description=? WHERE group_id=? AND sid=? AND event_id=?""";

        private static const string TO_JULIAN_SQL =
            "SELECT julianday(?)";

        private static const string SELECT_EVENT_SQL =
            """SELECT event_id, datetime(starttime),
            duration, running_status, free_ca_mode, name,
            description, extended_description
            FROM events WHERE group_id=? AND sid=? AND event_id=?""";

        private static const string DELETE_EVENTS_GROUP =
        "DELETE FROM events WHERE group_id=?";

        private static const string DELETE_EXPIRED_EVENTS =
        """DELETE FROM events WHERE starttime <= julianday(?, 'unixepoch')
        AND sid=? AND group_id=?""";

        private Statement to_julian_statement;
        private Statement insert_event_statement;
        private Statement update_event_statement;
        private Statement delete_event_statement;
        private Statement has_event_statement;
        private Statement select_event_statement;
        private Statement delete_events_group;
        private Statement delete_expired_events;

        public SqliteEPGStore () {
            File cache_dir = File.new_for_path (
            Environment.get_user_cache_dir ());
            File our_cache = cache_dir.get_child ("gnome-dvb-daemon");
            File database_file = our_cache.get_child ("eventsdb.sqlite3");

            base (database_file, VERSION);
        }

        public override void on_open () {
            this.db.prepare (TO_JULIAN_SQL, -1,
                out this.to_julian_statement);
            this.db.prepare (INSERT_EVENT_SQL, -1,
                out this.insert_event_statement);
            this.db.prepare (UPDATE_EVENT_SQL, -1,
                out this.update_event_statement);
            this.db.prepare (DELETE_EVENT_STATEMENT, -1,
                out this.delete_event_statement);
            this.db.prepare (HAS_EVENT_STATEMENT, -1,
                out this.has_event_statement);
            this.db.prepare (SELECT_EVENT_SQL, -1,
                out this.select_event_statement);
            this.db.prepare (DELETE_EVENTS_GROUP, -1,
                out this.delete_events_group);
            this.db.prepare (DELETE_EXPIRED_EVENTS, -1,
                out this.delete_expired_events);
        }

        public override void create () throws SqlError {
            this.exec_sql (CREATE_EVENTS_TABLE_STATEMENT);
            this.exec_sql ("PRAGMA synchronous=OFF");
        }

        public override void upgrade (int old_version, int new_version)
                throws SqlError
        {
            if (old_version == 1) {
                this.exec_sql ("PRAGMA synchronous=OFF");
            }
        }

        public bool add_or_update_event (Event event, uint channel_sid,
                uint group_id) throws SqlError
        {
            int free_ca_mode = (event.free_ca_mode) ? 1 : 0;

            string name = SqliteUtils.escape (event.name);
            string desc = SqliteUtils.escape (event.description);
            string ext_desc = SqliteUtils.escape (event.extended_description);
            double julian_start = this.to_julian (event.year, event.month,
                event.day, event.hour, event.minute, event.second);

            // Check if start time got converted correctly
            if (julian_start <= 0) {
                log.warning ("Failed to convert start time");
                return false;
            }

            if (this.contains_event (event, channel_sid, group_id)) {
                if (this.update_event_statement.bind_double (1, julian_start) != Sqlite.OK
                        || this.update_event_statement.bind_int (2, (int)event.duration) != Sqlite.OK
                        || this.update_event_statement.bind_int (3, (int)event.running_status) != Sqlite.OK
                        || this.update_event_statement.bind_int (4, free_ca_mode) != Sqlite.OK
                        || this.update_event_statement.bind_text (5, name) != Sqlite.OK
                        || this.update_event_statement.bind_text (6, desc) != Sqlite.OK
                        || this.update_event_statement.bind_text (7, ext_desc) != Sqlite.OK
                        || this.update_event_statement.bind_int (8, (int)group_id) != Sqlite.OK
                        || this.update_event_statement.bind_int (9, (int)channel_sid) != Sqlite.OK
                        || this.update_event_statement.bind_int (10, (int)event.id) != Sqlite.OK) {
                    this.throw_last_error ();
                    return false;
                }

                if (this.update_event_statement.step () != Sqlite.DONE) {
                    this.throw_last_error_reset (this.update_event_statement);
                    return false;
                }

                this.update_event_statement.reset ();
            } else {
                if (this.insert_event_statement.bind_int (1, (int)group_id) != Sqlite.OK
                        || this.insert_event_statement.bind_int (2, (int)channel_sid) != Sqlite.OK
                        || this.insert_event_statement.bind_int (3, (int)event.id) != Sqlite.OK
                        || this.insert_event_statement.bind_double (4, julian_start) != Sqlite.OK
                        || this.insert_event_statement.bind_int (5, (int)event.duration) != Sqlite.OK
                        || this.insert_event_statement.bind_int (6, (int)event.running_status) != Sqlite.OK
                        || this.insert_event_statement.bind_int (7, free_ca_mode) != Sqlite.OK
                        || this.insert_event_statement.bind_text (8, name) != Sqlite.OK
                        || this.insert_event_statement.bind_text (9, desc) != Sqlite.OK
                        || this.insert_event_statement.bind_text (10, ext_desc) != Sqlite.OK) {
                    this.throw_last_error ();
                    return false;
                }

                if (this.insert_event_statement.step () != Sqlite.DONE) {
                    this.throw_last_error_reset (this.insert_event_statement);
                    return false;
                }

                this.insert_event_statement.reset ();
            }
            return true;
        }

        public Event? get_event (uint event_id, uint channel_sid,
                uint group_id) throws SqlError
        {
            if (this.select_event_statement.bind_int (1, (int)group_id) != Sqlite.OK
                    || this.select_event_statement.bind_int (2, (int)channel_sid) != Sqlite.OK
                    || this.select_event_statement.bind_int (3, (int)event_id) != Sqlite.OK) {
                this.throw_last_error ();
                return null;
            }

            int rc = this.select_event_statement.step ();

            if (rc != Sqlite.ROW && rc != Sqlite.DONE) {
                this.throw_last_error_reset (this.select_event_statement);
                return null;
            }

            // ROW means there's data, DONE means there's none
            Event? event = null;
            if (rc != Sqlite.DONE) {
                event = this.create_event_from_statement (this.select_event_statement);
            }
            this.select_event_statement.reset ();

            return event;
        }

        public bool remove_event (uint event_id, uint channel_sid,
                uint group_id) throws SqlError
        {
            if (this.delete_event_statement.bind_int (1, (int)group_id) != Sqlite.OK
                    || this.delete_event_statement.bind_int (2, (int)channel_sid) != Sqlite.OK
                    || this.delete_event_statement.bind_int (3, (int)event_id) != Sqlite.OK) {
                this.throw_last_error ();
                return false;
            }

            if (this.delete_event_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.delete_event_statement);
                return false;
            }

            this.delete_event_statement.reset ();

            return true;
        }

        public bool remove_events_older_than (Event event, uint channel_sid,
                uint group_id) throws SqlError
        {
            time_t timestamp = event.get_end_timestamp ();

            if (this.delete_expired_events.bind_int64 (1, timestamp) != Sqlite.OK
                    || this.delete_expired_events.bind_int (2, (int)channel_sid) != Sqlite.OK
                    || this.delete_expired_events.bind_int (3, (int)group_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            if (this.delete_expired_events.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.delete_expired_events);
                return false;
            }

            this.delete_expired_events.reset ();

            return true;
        }

        public bool contains_event (Event event, uint channel_sid, uint group_id) throws SqlError
        {
            if (this.has_event_statement.bind_int (1, (int)group_id) != Sqlite.OK
                    || this.has_event_statement.bind_int (2, (int)channel_sid) != Sqlite.OK
                    || this.has_event_statement.bind_int (3, (int)event.id) != Sqlite.OK) {
                this.throw_last_error ();
                return false;
            }

            int c = 0;
            while (this.has_event_statement.step () == Sqlite.ROW) {
                c = this.has_event_statement.column_int (0);
            }

            this.has_event_statement.reset ();

            return (c > 0);
        }

        public Gee.List<Event> get_events (uint channel_sid, uint group_id)
                throws SqlError
        {
            Gee.List<Event> events = new ArrayList<Event> ();

            if (this.db == null) {
                log.warning ("DB not initialized");
                return events;
            }

            string statement_str = SELECT_MINIMAL_EVENTS_STATEMENT.printf (
                group_id, channel_sid);

            Statement statement;
            if (this.db.prepare (statement_str, -1, out statement) != Sqlite.OK) {
                this.throw_last_error ();
                return events;
            }

            while (statement.step () == Sqlite.ROW) {
                Event event = this.create_minimal_event (statement);
                events.add (event);
            }

            return events;
        }

        public bool remove_events_of_group (uint group_id) throws SqlError {
            if (this.delete_events_group.bind_int (1, (int)group_id) != Sqlite.OK) {
                this.throw_last_error ();
                return false;
            }

            if (this.delete_events_group.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.delete_events_group);
                return false;
            }

            this.delete_events_group.reset ();

            return true;
        }

        private Event create_minimal_event (Statement statement) {
            var event = new Event ();
            event.id = (uint)statement.column_int (0);

            weak string starttime = statement.column_text (1);
            starttime.scanf ("%04u-%02u-%02u %02u:%02u:%02u",
                &event.year,
                &event.month,
                &event.day,
                &event.hour,
                &event.minute,
                &event.second);

            event.duration = (uint)statement.column_int (2);

            return event;
        }

        private Event create_event_from_statement (Statement statement) {
            var event = new Event ();
            event.id = (uint)statement.column_int (0);

            weak string starttime = statement.column_text (1);
            starttime.scanf ("%04u-%02u-%02u %02u:%02u:%02u",
                &event.year,
                &event.month,
                &event.day,
                &event.hour,
                &event.minute,
                &event.second);

            event.duration = (uint)statement.column_int (2);
            event.running_status = (uint)statement.column_int (3);
            event.free_ca_mode = (statement.column_int (4) == 1);
            // Duplicate strings
            event.name = SqliteUtils.unescape (statement.column_text (5));
            event.description = SqliteUtils.unescape (
                statement.column_text (6));
            event.extended_description = SqliteUtils.unescape (
                statement.column_text (7));
            // We don't save those
            event.audio_components = null;
            event.video_component = null;
            event.teletext_components = null;

            return event;
        }

        private double to_julian (uint year, uint month, uint day,
                uint hour, uint minute, uint second) throws SqlError {

            string datetime_str = "%04u-%02u-%02u %02u:%02u:%02u".printf (
                year, month, day, hour, minute, second);

            if (this.to_julian_statement.bind_text (1, datetime_str)
                    != Sqlite.OK) {
                this.throw_last_error ();
                return 0;
            }

            if (this.to_julian_statement.step () != Sqlite.ROW) {
                this.throw_last_error ();
                return 0;
            }

            double val = this.to_julian_statement.column_double (0);

            this.to_julian_statement.reset ();

            return val;
        }

    }

}
