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

    public class SqliteConfigTimersStore : SqliteDatabase, ConfigStore, TimersStore {

        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        private static const int VERSION = 2;

        private static const string CREATE_DEVICE_GROUPS =
        """CREATE TABLE device_groups (
        group_id INTEGER,
        adapter_type INTEGER(1),
        channels_file VARCHAR(255),
        recordings_dir VARCHAR(255),
        name VARCHAR(255),
        PRIMARY KEY(group_id))""";

        private static const string CREATE_DEVICES =
        """CREATE TABLE devices (
        group_id INTEGER,
        adapter INTEGER,
        frontend INTEGER,
        PRIMARY KEY(group_id, adapter, frontend))""";

        private static const string CREATE_TIMERS =
        """CREATE TABLE timers (
        timer_id INTEGER,
        group_id INTEGER,
        channel_sid INTEGER,
        year INTEGER,
        month INTEGER,
        day INTEGER,
        hour INTEGER,
        minute INTEGER,
        duration INTEGER,
        event_id INTEGER,
        PRIMARY KEY(timer_id))""";

        private static const string UPDATE_TIMER  =
        """UPDATE timers SET
        year=?, month=?, day=?, hour=?, minute=?, duration=?
        WHERE timer_id=? AND group_id=?""";

        private static const string CREATE_GROUPS =
        """CREATE TABLE channel_groups (
        channel_group_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name VARCHAR(255))""";

        private static const string CREATE_CHANNELS =
        """CREATE TABLE channels (
        sid INTEGER,
        group_id INTEGER,
        channel_group_id INTEGER,
        PRIMARY KEY(sid, group_id, channel_group_id))""";

        private static const string SELECT_GROUP =
        "SELECT * FROM device_groups WHERE group_id=?";

        private static const string SELECT_ALL_GROUPS =
        "SELECT * FROM device_groups";

        private static const string SELECT_DEVICES =
        "SELECT * FROM devices WHERE group_id=?";

        private static const string SELECT_DEVICE =
        "SELECT * FROM devices WHERE group_id=? AND adapter=? AND frontend=?";

        private static const string DELETE_GROUP =
        "DELETE FROM device_groups WHERE group_id=?";

        private static const string INSERT_GROUP =
        "INSERT INTO device_groups VALUES (?, ?, ?, ?, ?)";

        private static const string CONTAINS_GROUP =
        "SELECT 1 FROM device_groups WHERE group_id=?";

        private static const string UPDATE_GROUP =
        "UPDATE device_groups SET adapter_type=?, channels_file=?, recordings_dir=?, name=? WHERE group_id=?";

        private static const string DELETE_DEVICE =
        "DELETE FROM devices WHERE adapter=? AND frontend=?";

        private static const string DELETE_GROUP_DEVICES =
        "DELETE FROM devices WHERE group_id=?";

        private static const string INSERT_DEVICE =
        "INSERT INTO devices VALUES (?, ?, ?)";

        private static const string SELECT_GROUP_OF_DEVICE =
        "SELECT group_id FROM devices WHERE adapter=? AND frontend=?";

        private static const string SELECT_TIMERS =
        "SELECT * FROM timers WHERE group_id=?";

        private static const string DELETE_TIMER =
        "DELETE FROM timers WHERE timer_id=?";

        private static const string DELETE_GROUP_TIMERS =
        "DELETE FROM timers WHERE group_id=?";

        private static const string INSERT_TIMER =
        "INSERT INTO timers VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        private static const string CONTAINS_TIMER =
        "SELECT 1 FROM timers WHERE timer_id=?";

        private static const string INSERT_CHANNEL_GROUP =
        "INSERT INTO channel_groups (name) VALUES (?)";

        private static const string DELETE_CHANNEL_GROUP =
        "DELETE FROM channel_groups WHERE channel_group_id=?";

        private static const string REMOVE_ALL_CHANNEL_GROUP =
        "DELETE FROM channels WHERE channel_group_id=?";

        private static const string SELECT_CHANNEL_GROUPS =
        "SELECT * FROM channel_groups";

        private static const string ADD_CHANNEL_GROUP =
        "INSERT INTO channels VALUES (?, ?, ?)";

        private static const string REMOVE_CHANNEL_GROUP =
        "DELETE FROM channels WHERE sid=? AND group_id=? AND channel_group_id=?";

        private static const string SELECT_CHANNELS =
        "SELECT sid FROM channels WHERE group_id=? AND channel_group_id=?";

        private Statement select_devices_statement;
        private Statement select_device_group_statement;
        private Statement delete_group_statement;
        private Statement insert_group_statement;
        private Statement update_group_statement;
        private Statement delete_device_statement;
        private Statement delete_group_devices_statement;
        private Statement insert_device_statement;
        private Statement select_group_of_device_statement;
        private Statement select_timers_statement;
        private Statement delete_timer_statement;
        private Statement delete_group_timers_statement;
        private Statement insert_timer_statement;
        private Statement contains_group_statement;
        private Statement contains_timer_statement;
        private Statement insert_channel_group_statement;
        private Statement delete_channel_group_statement;
        private Statement remove_all_channel_group_statement;
        private Statement select_channel_groups_statement;
        private Statement add_channel_group_statement;
        private Statement remove_channel_group_statement;
        private Statement select_channels_statement;
        private Statement update_timer_statement;

        public SqliteConfigTimersStore () {
            File config_dir = File.new_for_path (
                Environment.get_user_config_dir ());
            File config_cache = config_dir.get_child ("gnome-dvb-daemon");
            File dbfile = config_cache.get_child ("configtimers.sqlite3");

            base (dbfile, VERSION);
        }

        public override void create () throws SqlError {
            this.exec_sql (CREATE_DEVICE_GROUPS);
            this.exec_sql (CREATE_DEVICES);
            this.exec_sql (CREATE_TIMERS);
            this.exec_sql (CREATE_GROUPS);
            this.exec_sql (CREATE_CHANNELS);
        }

        public override void upgrade (int old_version, int new_version)
                throws SqlError
        {

        }

        public override void on_open () {
            this.db.prepare (SELECT_DEVICES, -1,
                out this.select_devices_statement);
            this.db.prepare (SELECT_GROUP, -1,
                out this.select_device_group_statement);
            this.db.prepare (DELETE_GROUP, -1,
                out this.delete_group_statement);
            this.db.prepare (INSERT_GROUP, -1,
                out this.insert_group_statement);
            this.db.prepare(UPDATE_GROUP, -1,
                out this.update_group_statement);
            this.db.prepare (DELETE_DEVICE, -1,
                out this.delete_device_statement);
            this.db.prepare (DELETE_GROUP_DEVICES, -1,
                out this.delete_group_devices_statement);
            this.db.prepare (INSERT_DEVICE, -1,
                out this.insert_device_statement);
            this.db.prepare (SELECT_GROUP_OF_DEVICE, -1,
                out this.select_group_of_device_statement);
            this.db.prepare (SELECT_TIMERS, -1,
                out this.select_timers_statement);
            this.db.prepare (DELETE_TIMER, -1,
                out this.delete_timer_statement);
            this.db.prepare (DELETE_GROUP_TIMERS, -1,
                out delete_group_timers_statement);
            this.db.prepare (INSERT_TIMER, -1,
                out this.insert_timer_statement);
            this.db.prepare (CONTAINS_GROUP, -1,
                out this.contains_group_statement);
            this.db.prepare (CONTAINS_TIMER, -1,
                out this.contains_timer_statement);
            this.db.prepare (INSERT_CHANNEL_GROUP, -1,
                out this.insert_channel_group_statement);
            this.db.prepare (DELETE_CHANNEL_GROUP, -1,
                out this.delete_channel_group_statement);
            this.db.prepare (REMOVE_ALL_CHANNEL_GROUP, -1,
                out this.remove_all_channel_group_statement);
            this.db.prepare (SELECT_CHANNEL_GROUPS, -1,
                out this.select_channel_groups_statement);
            this.db.prepare (ADD_CHANNEL_GROUP, -1,
                out this.add_channel_group_statement);
            this.db.prepare (REMOVE_CHANNEL_GROUP, -1,
                out this.remove_channel_group_statement);
            this.db.prepare (SELECT_CHANNELS, -1,
                out this.select_channels_statement);
            this.db.prepare (UPDATE_TIMER, -1,
                out this.update_timer_statement);
        }

        public Gee.List<DeviceGroup> get_all_device_groups () throws SqlError {
            Gee.List<DeviceGroup> groups = new ArrayList<DeviceGroup> ();

            Statement statement;
            if (this.db.prepare (SELECT_ALL_GROUPS, -1, out statement) != Sqlite.OK) {
                this.throw_last_error ();
                return groups;
            }

            while (statement.step () == Sqlite.ROW) {
                int group_id = statement.column_int (0);
                AdapterType type = (AdapterType)statement.column_int (1);

                File channels_file = File.new_for_path (
                    statement.column_text (2));

                File rec_dir = File.new_for_path (
                    statement.column_text (3));

                // Create device group
                DeviceGroup group = new DeviceGroup ((uint)group_id, channels_file, rec_dir,
                    type, !Main.get_disable_epg_scanner ());
                group.Name = statement.column_text (4);

                groups.add (group);
            }

            return groups;
        }

        public DeviceGroup? get_device_group (uint group_id) throws SqlError {
            DeviceGroup? group = null;

            if (this.select_device_group_statement.bind_int (1, (int)group_id) != Sqlite.OK) {
                this.throw_last_error ();
                log.debug ("cannot read device group data");
                return group;
            }


            this.begin_transaction ();
            if (this.select_device_group_statement.step () == Sqlite.ROW) {

                AdapterType type = (AdapterType)this.select_device_group_statement.column_int(1);

                File channels_file = File.new_for_path (
                    this.select_device_group_statement.column_text (2));

                File rec_dir = File.new_for_path (
                    this.select_device_group_statement.column_text (3));

                // Create device group
                group = new DeviceGroup ((uint)group_id, channels_file, rec_dir,
                    type, !Main.get_disable_epg_scanner());
                group.Name = this.select_device_group_statement.column_text (4);
            }

            this.select_device_group_statement.reset ();

            this.end_transaction ();

            return group;
        }

        public bool is_group_member (Device dev, DeviceGroup group) throws SqlError {
            Statement statement;

            if (this.db.prepare (SELECT_DEVICE, -1, out statement) != Sqlite.OK) {
                this.throw_last_error ();
                return false;
            }

            if (statement.bind_int (1, (int)group.Id) != Sqlite.OK
                || statement.bind_int (2, (int)dev.Adapter) != Sqlite.OK
                || statement.bind_int (3, (int)dev.Frontend) != Sqlite.OK) {
                this.throw_last_error ();
                return false;
            }

            if (statement.step () == Sqlite.ROW)
                return true;

            return false;
        }

        public bool is_last_device (uint group_id) throws SqlError {
            bool val = false;

            if (this.select_devices_statement.bind_int (1, (int)group_id) !=Sqlite.OK) {
                this.throw_last_error ();
                return val;
            }

            this.begin_transaction ();

            if (this.select_devices_statement.step() != Sqlite.ROW) {
                if (this.select_devices_statement.data_count () == 0)
                    val = true;
            }

            this.select_devices_statement.reset ();

            this.end_transaction ();
            return val;
        }

        public bool add_device_group (DeviceGroup dev_group) throws SqlError {
            if (this.contains_group (dev_group.Id)) return false;

            string channels = dev_group.Channels.channels_file.get_path ();
            string recdir = dev_group.RecordingsDirectory.get_path ();

            if (this.insert_group_statement.bind_int (1, (int)dev_group.Id) != Sqlite.OK
                || this.insert_group_statement.bind_int (2, (int)dev_group.Type) != Sqlite.OK
                || this.insert_group_statement.bind_text (3, channels) != Sqlite.OK
                || this.insert_group_statement.bind_text (4, recdir) != Sqlite.OK
                || this.insert_group_statement.bind_text (5, dev_group.Name) != Sqlite.OK) {
                this.throw_last_error ();
                return false;
            }

            this.begin_transaction ();
            if (this.insert_group_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.insert_group_statement);
                return false;
            }
            this.insert_group_statement.reset ();

            this.end_transaction ();

            return true;
        }

        public bool remove_device_group (DeviceGroup devgroup) throws SqlError {
            if (this.delete_group_statement.bind_int (1, (int)devgroup.Id) != Sqlite.OK) {
                this.throw_last_error ();
                return false;
            }

            if (this.delete_group_devices_statement.bind_int (1, (int)devgroup.Id) != Sqlite.OK) {
                this.throw_last_error ();
                return false;
            }

            this.begin_transaction ();
            if (this.delete_group_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.delete_group_statement);
                return false;
            }
            this.delete_group_statement.reset ();

            if (this.delete_group_devices_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.delete_group_devices_statement);
                return false;
            }
            this.delete_group_devices_statement.reset ();

            this.end_transaction ();

            return true;
        }

        public bool get_parent_groups (uint adapter, uint frontend, out uint[] group_ids) throws SqlError {
            group_ids = null;

            if (this.select_group_of_device_statement.bind_int (1, (int)adapter) != Sqlite.OK
                || this.select_group_of_device_statement.bind_int (2, (int)frontend) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            bool ret = false;
            int count = this.select_group_of_device_statement.column_count ();
            group_ids = new uint[count];
            while (this.select_group_of_device_statement.step () == Sqlite.ROW) {
                for (int i = 0; i < count; i++) {
                    group_ids[i] = this.select_group_of_device_statement.column_int (i);
                }
                ret = true;
            }
            this.select_group_of_device_statement.reset ();

            return ret;
        }

        public bool contains_group (uint group_id) throws SqlError {
            if (this.contains_group_statement.bind_int (1, (int)group_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            int c = 0;
            while (this.contains_group_statement.step () == Sqlite.ROW) {
                c = this.contains_group_statement.column_int (0);
            }
            this.contains_group_statement.reset ();

            return (c > 0);
        }

        public bool add_device_to_group (Device dev, DeviceGroup devgroup)
               throws SqlError
        {
            if (this.insert_device_statement.bind_int (1, (int)devgroup.Id) != Sqlite.OK
                || this.insert_device_statement.bind_int (2, (int)dev.Adapter) != Sqlite.OK
                || this.insert_device_statement.bind_int (3, (int)dev.Frontend) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            if (this.insert_device_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.insert_device_statement);
                return false;
            }
            this.insert_device_statement.reset ();

            return true;
        }

        public bool remove_device_from_group (Device dev, DeviceGroup devgroup)
                throws SqlError
        {
            if (this.delete_device_statement.bind_int (1, (int)dev.Adapter) != Sqlite.OK
                || this.delete_device_statement.bind_int (2, (int)dev.Frontend) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            if (this.delete_device_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.delete_device_statement);
                return false;
            }
            this.delete_device_statement.reset ();

            return true;
        }

        public Gee.List<Timer> get_all_timers_of_device_group (DeviceGroup dev)
                throws SqlError
        {
            Gee.List<Timer> timers = new ArrayList<Timer> ();

            if (this.select_timers_statement.bind_int (1, (int)dev.Id) != Sqlite.OK) {
                this.throw_last_error ();
                return timers;
            }

            while (this.select_timers_statement.step () == Sqlite.ROW) {
                uint tid, sid, duration, event_id;
                int year, month, day, hour, minute;

                tid = (uint)this.select_timers_statement.column_int (0);
                sid = (uint)this.select_timers_statement.column_int (2);
                year = this.select_timers_statement.column_int (3);
                month = this.select_timers_statement.column_int (4);
                day = this.select_timers_statement.column_int (5);
                hour = this.select_timers_statement.column_int (6);
                minute = this.select_timers_statement.column_int (7);
                duration = (uint)this.select_timers_statement.column_int (8);
                event_id = (uint)this.select_timers_statement.column_int (9);

                Channel channel = dev.Channels.get_channel (sid);
                Timer timer = new Timer (tid, channel, year, month, day, hour,
                    minute, duration);
                timer.EventID = event_id;
                timers.add (timer);
            }
            this.select_timers_statement.reset ();

            return timers;
        }

        public bool add_timer_to_device_group (Timer timer, DeviceGroup dev)
                throws SqlError
        {
            if (this.contains_timer (timer.Id)) return false;

            uint[] start = timer.get_start_time ();
            if (this.insert_timer_statement.bind_int (1, (int)timer.Id) != Sqlite.OK
                || this.insert_timer_statement.bind_int (2, (int)dev.Id) != Sqlite.OK
                || this.insert_timer_statement.bind_int (3, (int)timer.Channel.Sid) != Sqlite.OK
                || this.insert_timer_statement.bind_int (4, (int)start[0]) != Sqlite.OK
                || this.insert_timer_statement.bind_int (5, (int)start[1]) != Sqlite.OK
                || this.insert_timer_statement.bind_int (6, (int)start[2]) != Sqlite.OK
                || this.insert_timer_statement.bind_int (7, (int)start[3]) != Sqlite.OK
                || this.insert_timer_statement.bind_int (8, (int)start[4]) != Sqlite.OK
                || this.insert_timer_statement.bind_int (9, (int)timer.Duration) != Sqlite.OK
                || this.insert_timer_statement.bind_int (10, (int)timer.EventID) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            if (this.insert_timer_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.insert_timer_statement);
                return false;
            }
            this.insert_timer_statement.reset ();

            return true;
        }

        public bool remove_timer_from_device_group (uint timer_id,
                DeviceGroup dev) throws SqlError
        {
            if (this.delete_timer_statement.bind_int (1, (int)timer_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            if (this.delete_timer_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.delete_timer_statement);
                return false;
            }
            this.delete_timer_statement.reset ();

            return true;
        }

        public bool remove_all_timers_from_device_group (uint group_id)
                throws SqlError
        {
            if (this.delete_group_timers_statement.bind_int (1, (int)group_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            if (this.delete_group_timers_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.delete_group_timers_statement);
                return false;
            }
            this.delete_group_timers_statement.reset ();

            return true;
        }

        public bool update_timer (Timer timer, DeviceGroup dev)
                throws SqlError
        {
            uint[] start = timer.get_start_time ();
            if (this.update_timer_statement.bind_int (1, (int)start[0]) != Sqlite.OK
                || this.update_timer_statement.bind_int (2, (int)start[1]) != Sqlite.OK
                || this.update_timer_statement.bind_int (3, (int)start[2]) != Sqlite.OK
                || this.update_timer_statement.bind_int (4, (int)start[3]) != Sqlite.OK
                || this.update_timer_statement.bind_int (5, (int)start[4]) != Sqlite.OK
                || this.update_timer_statement.bind_int (6, (int)timer.Duration) != Sqlite.OK
                || this.update_timer_statement.bind_int (7, (int)timer.Id) != Sqlite.OK
                || this.update_timer_statement.bind_int (8, (int)dev.Id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            if (this.update_timer_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.update_timer_statement);
                return false;
            }
            this.update_timer_statement.reset ();

            return true;
        }

        private bool contains_timer (uint timer_id) throws SqlError {
            if (this.contains_timer_statement.bind_int (1, (int)timer_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            int c = 0;
            while (this.contains_timer_statement.step () == Sqlite.ROW) {
                c = this.contains_timer_statement.column_int (0);
            }
            this.contains_timer_statement.reset ();

            return (c > 0);
        }

        public bool update_from_group (DeviceGroup devgroup) throws SqlError {
            if (this.update_group_statement.bind_int (1, (int)devgroup.Type) != Sqlite.OK
                || this.update_group_statement.bind_text (2, devgroup.Channels.channels_file.get_path ()) != Sqlite.OK
                || this.update_group_statement.bind_text (3, devgroup.RecordingsDirectory.get_path ()) != Sqlite.OK
                || this.update_group_statement.bind_text (4, devgroup.Name) != Sqlite.OK
                || this.update_group_statement.bind_int (5, (int)devgroup.Id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            if (this.update_group_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.update_group_statement);
                return false;
            }
            this.update_group_statement.reset ();

            return true;
        }

        public bool add_channel_group (string name, out int channel_group_id) throws SqlError {
            channel_group_id = -1;

            if (this.insert_channel_group_statement.bind_text (1, name) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }
            if (this.insert_channel_group_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.insert_channel_group_statement);
                return false;
            }
            channel_group_id = (int)this.db.last_insert_rowid ();
            this.insert_channel_group_statement.reset ();
            return true;
        }

        public bool remove_channel_group (int group_id) throws SqlError {
            if (this.delete_channel_group_statement.bind_int (1, group_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }
            if (this.remove_all_channel_group_statement.bind_int (1, group_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }

            this.begin_transaction ();
            if (this.delete_channel_group_statement.step () != Sqlite.DONE)
            {
                this.throw_last_error_reset (this.delete_channel_group_statement);
                return false;
            }
            this.delete_channel_group_statement.reset ();
            if (this.remove_all_channel_group_statement.step () != Sqlite.DONE)
            {
                this.throw_last_error_reset (this.remove_all_channel_group_statement);
                return false;
            }
            this.remove_all_channel_group_statement.reset ();
            this.end_transaction ();

            return true;
        }

        public Gee.List<ChannelGroup> get_channel_groups ()
                throws SqlError
        {
            ArrayList<ChannelGroup> groups = new ArrayList<ChannelGroup> ();
            while (this.select_channel_groups_statement.step () == Sqlite.ROW) {
                int group_id = this.select_channel_groups_statement.column_int (0);
                string group_name = this.select_channel_groups_statement.column_text (1);
                ChannelGroup group = new ChannelGroup (group_id, group_name);
                groups.add (group);
            }
            this.select_channel_groups_statement.reset ();

            return groups;
        }

        public Gee.List<uint> get_channels_of_group (uint dev_group_id,
                int channel_group_id) throws SqlError
        {
            if (this.select_channels_statement.bind_int (1, (int)dev_group_id) != Sqlite.OK
                || this.select_channels_statement.bind_int (2, channel_group_id) != Sqlite.OK)
            {
                this.throw_last_error ();
            }

            ArrayList<uint> channels = new ArrayList<uint> ();
            while (this.select_channels_statement.step () == Sqlite.ROW) {
                channels.add (this.select_channels_statement.column_int (0));
            }
            this.select_channels_statement.reset ();

            return channels;
        }

        public bool add_channel_to_group (Channel channel, int group_id)
                 throws SqlError
        {
            // Check if channel is already in group
            if (this.add_channel_group_statement.bind_int (1, (int)channel.Sid) != Sqlite.OK
                || this.add_channel_group_statement.bind_int (2, (int)channel.GroupId) != Sqlite.OK
                || this.add_channel_group_statement.bind_int (3, group_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }
            if (this.add_channel_group_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.add_channel_group_statement);
                return false;
            }
            this.add_channel_group_statement.reset ();
            return true;
        }

        public bool remove_channel_from_group (Channel channel, int group_id)
                 throws SqlError
        {
            if (this.remove_channel_group_statement.bind_int (1, (int)channel.Sid) != Sqlite.OK
                || this.remove_channel_group_statement.bind_int (2, (int)channel.GroupId) != Sqlite.OK
                || this.remove_channel_group_statement.bind_int (3, group_id) != Sqlite.OK)
            {
                this.throw_last_error ();
                return false;
            }
            if (this.remove_channel_group_statement.step () != Sqlite.DONE) {
                this.throw_last_error_reset (this.remove_channel_group_statement);
                return false;
            }
            this.remove_channel_group_statement.reset ();
            return true;
        }
    }

}
