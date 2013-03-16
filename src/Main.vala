/*
 * Copyright (C) 2008-2011 Sebastian Pölsterl
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

namespace Main {

    private static weak DVB.Manager manager;
    private static DVB.RecordingsStore recstore;
    private static bool has_debug;
    private static bool has_version;
    private static bool disable_epg_scanner;
    private static bool disable_mediaserver;
    private static MainLoop mainloop;
    public static DVB.Logging.Logger log;
    public static DBusConnection conn;

    const OptionEntry[] options =  {
        { "debug", 'd', 0, OptionArg.NONE, out has_debug,
        "Display debug statements on stdout", null},
        { "version", 0, 0, OptionArg.NONE, out has_version,
        "Display version number", null},
        { "disable-epg-scanner", 0, 0, OptionArg.NONE,
        out disable_epg_scanner, "Disable scanning for EPG data", null},
        { "disable-mediaserver2", 0 ,0, OptionArg.NONE, out disable_mediaserver,
        "Disable exporting devices and channels according to Rygel's MediaServer2 specification",
        null},
        { null }
    };

    private static void start_manager () {
        manager = DVB.Manager.get_instance ();
        DVB.Utils.dbus_own_name (DVB.Constants.DBUS_SERVICE,
            on_bus_acquired);
    }

    private static void on_bus_acquired (DBusConnection _conn) {
        DVB.Utils.dbus_register_object<DVB.IDBusManager> (_conn,
            DVB.Constants.DBUS_MANAGER_PATH, manager);
        conn = _conn;
        start_recordings_store ();

        restore_device_groups ();
    }

    private static void start_recordings_store () {
        log.info ("Creating new RecordingsStore D-Bus service");

        recstore = DVB.RecordingsStore.get_instance ();
        DVB.Utils.dbus_register_object<DVB.IDBusRecordingsStore> (conn,
                DVB.Constants.DBUS_RECORDINGS_STORE_PATH, recstore);
    }

    private static void on_exit (int signum) {
        log.info ("Exiting");

        DVB.RTSPServer.shutdown ();
        DVB.Manager.shutdown ();
        new DVB.Factory().shutdown ();
        DVB.RecordingsStore.shutdown ();
        DVB.Logging.LogManager.getLogManager().cleanup ();

        recstore = null;
        manager = null;

        mainloop.quit ();
    }

    public static bool get_disable_epg_scanner () {
        return Main.disable_epg_scanner;
    }

    private static bool check_feature_version (string name, uint major,
            uint minor, uint micro) {
        Gst.Registry reg = Gst.Registry.get ();
        Gst.PluginFeature feature = reg.lookup_feature (name);
        bool ret;
        if (feature == null)
            ret = false;
        else
            ret = feature.check_version (major, minor, micro);
        log.debug ("Has %s >= %u.%u.%u: %s", name, major, minor, micro, ret.to_string ());
        return ret;
    }

    private static bool check_requirements () {
        bool val;
        val = check_feature_version ("dvbsrc", 0, 10, 13);
        if (!val) return false;

        val = check_feature_version ("dvbbasebin", 0, 10, 13);
        if (!val) return false;

        val = check_feature_version ("mpegtsparse", 0, 10, 13);
        if (!val) return false;

        val = check_feature_version ("rtpmp2tpay", 0, 10, 14);
        return val;
    }

    private static void restore_device_groups () {
        DVB.database.ConfigStore config_store = new DVB.Factory().get_config_store ();

        Gee.List<DVB.DeviceGroup> device_groups;
        try {
            device_groups = config_store.get_all_device_groups ();
        } catch (DVB.database.SqlError e) {
            critical ("%s", e.message);
            return;
        }

        uint max_group_id = 0;
        log.info ("Restoring %d device groups", device_groups.size);
        foreach (DVB.DeviceGroup device_group in device_groups) {
            manager.restore_device_group_and_timers (device_group);
            if (device_group.Id > max_group_id)
                max_group_id = device_group.Id;
        }

        restore_fake_devices (max_group_id);
    }

    private static void restore_fake_devices (uint max_group_id) {
        DVB.Settings settings = new DVB.Factory().get_settings ();
        Gee.List<DVB.Device> devices = settings.get_fake_devices ();
        if (devices.size > 0) {
            DVB.Device ref_dev = devices.get (0);
            DVB.DeviceGroup group = new DVB.DeviceGroup (max_group_id + 1,
                ref_dev, false);
            group.Name = "Fake Devices";
            for (int i=1; i<devices.size; i++) {
                group.add (devices.get (i));
            }

            manager.restore_device_group (group, false);
        }
    }

    private static void configure_logging () {
        DVB.Logging.LogManager manager = DVB.Logging.LogManager.getLogManager ();
        log = manager.getDefaultLogger ();

        File cache_dir = File.new_for_path (Environment.get_user_cache_dir ());
        File our_cache = cache_dir.get_child ("gnome-dvb-daemon");
        File log_file = our_cache.get_child ("debug%d.log");

        try {
            DVB.Logging.FileHandler fhandler = new DVB.Logging.FileHandler (
                log_file.get_path ());
            fhandler.limit = 1024 * 1024; /* 1 MB */
            if (has_debug) {
                fhandler.limit = fhandler.limit * 5;
            } else {
                fhandler.threshold = DVB.Logging.LogLevel.WARNING;
            }

            log.addHandler (fhandler);
        } catch (Error e) {
            stderr.printf ("*** Failed creating DVB.Logging.FileHandler: %s\n", e.message);
        }

        DVB.Logging.ConsoleHandler chandler = new DVB.Logging.ConsoleHandler();
        chandler.formatter = new DVB.Logging.ColorFormatter ();
        if (!has_debug) {
            chandler.threshold = DVB.Logging.LogLevel.ERROR;
        }
        log.addHandler (chandler);
    }

    public static int main (string[] args) {
        // set timezone to avoid that strftime stats /etc/localtime on every call
        Environment.set_variable ("TZ", "/etc/localtime", false);

        Process.signal(ProcessSignal.INT, on_exit);
        Process.signal(ProcessSignal.TERM, on_exit);

        OptionContext context = new OptionContext ("- record and watch TV shows using one or more DVB adapters");
        context.add_main_entries (options, null);
        context.add_group (Gst.init_get_option_group ());

        try {
            context.parse (ref args);
        } catch (OptionError e) {
            stderr.printf ("%s\n", e.message);
            stderr.printf ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
            return 1;
        }

        if (has_version) {
            stdout.printf (Config.PACKAGE_NAME);
            stdout.printf (" %s\n", Config.PACKAGE_VERSION);
            return 0;
        }

        // Creating a GLib main loop with a default context
        mainloop = new MainLoop (null, false);

        // Initializing GStreamer
        Gst.init (ref args);

        configure_logging ();

        if (!check_requirements ()) {
            stderr.printf ("You don't have all of the necessary requirements to run %s.\n",
                Config.PACKAGE_NAME);
            stderr.printf ("Start the daemon with the --debug flag for more details.\n");
            return -1;
        }

        start_manager ();

        DVB.RTSPServer.start.begin ();

        if (!disable_mediaserver) {
            DVB.MediaServer2.start_rygel_services.begin ();
        }

        // Start GLib mainloop
        mainloop.run ();

        return 0;
    }

}
