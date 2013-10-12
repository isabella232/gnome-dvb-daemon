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
using DVB.database;
using DVB.Logging;

namespace DVB {

    public class Manager : Object, IDBusManager {

        class ScannerData : Object {
            public Scanner scanner;
            public ulong signal_id;
        }

        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        public Gee.Collection<DeviceGroup> device_groups {
            owned get {
                return this.devices.values;
            }
        }
        // Map object path to Scanner
        private HashMap<string, ScannerData> scanners;

        // Maps device group id to Device
        private HashMap<uint, DeviceGroup> devices;

        private uint device_group_counter;
        private GUdev.Client udev_client;

        private static Manager instance;
        private static RecMutex instance_mutex = RecMutex ();
        private static const string[] UDEV_SUBSYSTEMS = {"dvb", null};

        construct {
            this.scanners = new HashMap<string, ScannerData> (
                Gee.Functions.get_hash_func_for(typeof(string)),
                Gee.Functions.get_equal_func_for(typeof(string)),
                Gee.Functions.get_equal_func_for(typeof(ScannerData)));
            this.devices = new HashMap<uint, DeviceGroup> ();
            this.device_group_counter = 0;
            this.udev_client = new GUdev.Client (UDEV_SUBSYSTEMS);
            this.udev_client.uevent.connect (this.on_udev_event);
        }

        public static unowned Manager get_instance () {
            instance_mutex.lock ();
            if (instance == null) {
                instance = new Manager ();
            }
            instance_mutex.unlock ();
            return instance;
        }

        public static void shutdown () {
            instance_mutex.lock ();
            Manager m = instance;

            if (instance != null) {
                m.udev_client = null;
                lock (m.scanners) {
                    foreach (ScannerData data in m.scanners.values) {
                        log.debug ("Stopping scanner");
                        data.scanner.disconnect (data.signal_id);
                        data.scanner.do_destroy ();
                    }
                    m.scanners.clear ();
                }

                lock (m.devices) {
                    foreach (DeviceGroup devgrp in m.devices.values) {
                        devgrp.destroy ();
                    }
                    m.devices.clear ();
                }

                instance = null;
            }
            instance_mutex.unlock ();
        }

        /**
         * @adapter: Number of the device's adapter
         * @frontend: Number of the device's frontend
         * @opath: Object path of the scanner service
         * @dbusiface: DBus interface of the scanner service
         * @returns: TRUE on success
         *
         * Get the object path of the channel scanner for this device.
         */
        public bool GetScannerForDevice (uint adapter, uint frontend,
                out ObjectPath opath, out string dbusiface) throws DBusError
        {
            string path = Constants.DBUS_SCANNER_PATH.printf (adapter, frontend);
            opath = new ObjectPath (path);

            Device device;
            Device? reg_dev = this.get_registered_device (adapter, frontend);

            if (reg_dev == null) {
                // Create new device
                device = Device.new_with_type (adapter, frontend);
            } else {
                // Stop epgscanner for device if there's any
                this.get_device_group_of_device (reg_dev).stop_epg_scanner ();

                // Assign existing device
                device = reg_dev;
            }

            switch (device.Type) {
                case AdapterType.DVB_C:
                case AdapterType.DVB_S:
                case AdapterType.DVB_T:
                    dbusiface = "org.gnome.DVB.Scanner";
                break;

                default:
                dbusiface = null;
                break;
            }

            if (dbusiface == null) {
                log.error ("Unknown adapter type");
                dbusiface = "";
                return false;
            }

            lock (this.scanners) {
                if (!this.scanners.has_key (path)) {
                    ScannerData data = new ScannerData ();
                    switch (device.Type) {
                        case AdapterType.DVB_T:
                        data.scanner = new TerrestrialScanner (device);
                        break;

                        case AdapterType.DVB_S:
                        data.scanner = new SatelliteScanner (device);
                        break;

                        case AdapterType.DVB_C:
                        data.scanner = new CableScanner (device);
                        break;
                    }

                    Utils.dbus_register_object (Main.conn, path, (IDBusScanner)data.scanner);

                    data.signal_id = data.scanner.destroyed.connect (this.on_scanner_destroyed);

                    this.scanners.set (path, data);

                    log.debug ("Created new Scanner D-Bus service for adapter %u, frontend %u (%s)",
                          adapter, frontend, dbusiface);
                }
            }

            return true;
        }

        /**
         * @group_id: A group ID
         * @path: Device group's DBus path
         * @returns: TRUE on success
         */
        public bool GetDeviceGroup (uint group_id, out ObjectPath opath)
                throws DBusError
        {
            bool ret;
            lock (this.devices) {
                if (this.devices.has_key (group_id)) {
                    opath = new ObjectPath (Constants.DBUS_DEVICE_GROUP_PATH.printf (group_id));
                    ret = true;
                } else {
                    opath = new ObjectPath ("");
                    ret = false;
                }
            }
            return ret;
        }

        /**
         * @returns: Device groups' DBus path
         */
        public ObjectPath[] GetRegisteredDeviceGroups () throws DBusError {
            ObjectPath[] devs = new ObjectPath[this.devices.size];
            int i = 0;
            lock (this.devices) {
                foreach (uint key in this.devices.keys) {
                    devs[i] = new ObjectPath (
                        Constants.DBUS_DEVICE_GROUP_PATH.printf (key));
                    i++;
                }
            }
            return devs;
        }

        /**
         * @adapter: Number of the device's adapter
         * @frontend: Number of the device's frontend
         * @channels_conf: Path to channels.conf for this device
         * @recordings_dir: Path where the recordings should be stored
         * @name: Name of group
         * @returns: TRUE when the device has been registered successfully
         *
         * Creates a new DeviceGroup and new DVB device whereas the
         * DVB device is the reference device of this group (i.e.
         * all other devices of this group will inherit the settings
         * of the reference device).
         */
        public bool AddDeviceToNewGroup (uint adapter, uint frontend,
                string channels_conf, string recordings_dir, string name)
                throws DBusError
        {
            File chan_file = File.new_for_path (channels_conf);
            File rec_dir = File.new_for_path (recordings_dir);

            Device device;
            try {
                device = Device.new_full (adapter, frontend, chan_file,
                    rec_dir);
            } catch (DeviceError e) {
            	log.error ("Could not create device: %s", e.message);
            	return false;
            }

            // Check if device is already assigned to other group
            if (this.device_is_in_any_group (device)) return false;

            device_group_counter++;

            DeviceGroup devgroup = new DeviceGroup (device_group_counter, device);
            devgroup.Name = name;

            this.restore_device_group (devgroup);

            this.group_added (device_group_counter);

            return true;
        }

        /**
         * @adapter: Adapter of device
         * @frontend: Frontend of device
         * @name: The name of the device or "Unknown"
         * @returns: TRUE on success
         *
         * The device must be part of group, otherwise "Unknown"
         * is returned.
         */
        public bool GetNameOfRegisteredDevice (uint adapter, uint frontend,
                out string name) throws DBusError
        {
            Device? dev = this.get_registered_device (adapter, frontend);

            if (dev == null) {
                name = "";
                return false;
            } else {
                name = dev.Name;
                return true;
            }
        }

        /**
         * @returns: the numner of configured device groups
         */
        public int GetDeviceGroupSize () throws DBusError {
            return this.devices.size;
        }

        /**
         * @returns: ID and name of each channel group
         */
		public ChannelGroupInfo[] GetChannelGroups () throws DBusError {
            ConfigStore config = new Factory().get_config_store ();
            Gee.List<ChannelGroup> groups;
            try {
                groups = config.get_channel_groups ();
            } catch (SqlError e) {
                log.error ("%s", e.message);
                return new ChannelGroupInfo[] {};
            }
            ChannelGroupInfo[] arr = new ChannelGroupInfo[groups.size];
            for (int i=0; i<arr.length; i++) {
                ChannelGroup cg = groups.get (i);
                arr[i] = ChannelGroupInfo ();
                arr[i].id = cg.id;
                arr[i].name = cg.name;
            }
            return arr;
        }

        /**
         * @name: Name of the new group
         * @returns: TRUE on success
         */
		public bool AddChannelGroup (string name, out int channel_group_id) throws DBusError {
            ConfigStore config = new Factory().get_config_store ();
            bool ret;
            try {
                ret = config.add_channel_group (name, out channel_group_id);
            } catch (SqlError e) {
                log.error ("%s", e.message);
                ret = false;
            }
            return ret;
        }

        /**
	     * @channel_group_id: ID of the ChannelGroup
         * @returns: TRUE on success
         */
		public bool RemoveChannelGroup (int channel_group_id) throws DBusError {
            ConfigStore config = new Factory().get_config_store ();
            bool ret;
            try {
                ret = config.remove_channel_group (channel_group_id);
            } catch (SqlError e) {
                log.error ("%s", e.message);
                ret = false;
            }
            return ret;
        }

        /**
         * @returns: informations about all connected
         * devices retrieved via udev
         */
        public GLib.HashTable<string, string>[] GetDevices () throws DBusError {
            GLib.List<GUdev.Device> devices =
                this.udev_client.query_by_subsystem ("dvb");
            var devices_list = new GLib.List<HashTable<string, string>> ();

            for (int i=0; i<devices.length (); i++) {
                GUdev.Device dev = devices.nth_data (i);
                string? device_file = dev.get_device_file ();

                if (device_file == null || !device_file.contains ("frontend"))
                    continue;

                var map = new HashTable<string, string>.full (GLib.str_hash,
                    GLib.str_equal, GLib.g_free, GLib.g_free);
                devices_list.prepend (map);

                map.insert ("device_file", device_file);

                GUdev.Device? parent = dev.get_parent ();
                if (parent != null) {
                    string attr;
                    attr = parent.get_sysfs_attr ("manufacturer");
                    if (attr != null) map.insert ("manufacturer", attr);

                    attr = parent.get_sysfs_attr ("product");
                    if (attr != null) map.insert ("product", attr);
                }
            }

            var arr = new GLib.HashTable<string, string>[devices_list.length ()];
            for (int i=0; i<devices_list.length (); i++) {
                arr[i] = devices_list.nth_data (i);
            }

            return arr;
        }

        public bool GetAdapterInfo (uint adapter, uint frontend, out AdapterInfo info) throws DBusError {
            Gst.Element dvbelement = Gst.ElementFactory.make ("dvbsrc", null);
            dvbelement.set("adapter", adapter);
            dvbelement.set("frontend", frontend);

            Gst.Element pipeline = new Gst.Pipeline("get-adapter-info");
            ((Gst.Bin)pipeline).add(dvbelement);
            pipeline.set_state(Gst.State.READY);

            Gst.Bus bus = pipeline.get_bus ();

            info = AdapterInfo();
            bool success = false;
            while (bus.have_pending()) {
                Gst.Message msg = bus.pop ();
                if (msg.type == Gst.MessageType.ELEMENT && msg.src == dvbelement) {
                    unowned Gst.Structure structure = msg.get_structure ();
                    if (structure.get_name () == "dvb-adapter") {
                        info.name = structure.get_string ("name");
                        info.type = structure.get_string ("type");
                        success = true;
                        break;
                    }
                } else if (msg.type == Gst.MessageType.ERROR) {
                    log.warning ("Could not retrieve adapter infos: %s",
                        msg.get_structure().to_string ());
                }
            }
            pipeline.set_state (Gst.State.NULL);

            if (!success) {
                info.name = "unknown";
                info.type = "unknown";
            }

            return success;
        }

        /**
         * @returns: Whether the device has been added successfully
         *
         * Register device, create Recorder and ChannelList D-Bus service
         */
        public bool add_device_group (DeviceGroup devgroup, bool store) {
            uint group_id = devgroup.Id;
            log.debug ("Adding device group %u with %d devices", group_id,
                devgroup.size);

            if (devgroup.Type == AdapterType.UNKNOWN) {
                log.warning ("Not adding device group %u of unknown type",
                    devgroup.Id);
                return false;
            }

            lock (this.devices) {
                this.devices.set (group_id, devgroup);
            }
            if (store) {
                try {
                    new Factory().get_config_store ().add_device_group (devgroup);
                } catch (SqlError e) {
                    log.error ("%s", e.message);
                    return false;
                }
            }
            devgroup.device_removed.connect (this.on_device_removed_from_group);

            string path = Constants.DBUS_DEVICE_GROUP_PATH.printf (group_id);
            Utils.dbus_register_object<IDBusDeviceGroup> (Main.conn,
                path, devgroup);

            if (group_id > device_group_counter)
                device_group_counter = group_id;

            devgroup.start_epg_scanner ();

            return true;
        }

        public bool restore_device_group (DeviceGroup device_group, bool store = true) {
            log.debug ("Restoring group %u", device_group.Id);

            try {
                device_group.Channels.load (device_group.Type);
            } catch (Error e) {
            	log.error ("Error reading channels from file: %s", e.message);
            	return false;
            }

            return this.add_device_group (device_group, store);
        }

        public void restore_timers (DeviceGroup device_group) {
            log.info ("Restoring timers of device group %u", device_group.Id);
            TimersStore timers_store = new Factory().get_timers_store ();

            Gee.List<Timer> timers;
            try {
                timers = timers_store.get_all_timers_of_device_group (
                    device_group);
            } catch (SqlError e) {
                log.error ("Failed retrieving timers of group %u: %s",
                    device_group.Id, e.message);
                return;
            }

            uint32 max_id = 0;
            Recorder rec = device_group.recorder;
            foreach (Timer t in timers) {
                if (t.Id > max_id) max_id = t.Id;
                uint32 rec_id;
                if (!rec.add_timer (t, out rec_id)) {
                    try {
                        timers_store.remove_timer_from_device_group (t.Id, device_group);
                    } catch (SqlError e) {
                        log.error ("Failed removing timer: %s", e.message);
                    }
                }
            }

            RecordingsStore recstore = RecordingsStore.get_instance ();
            recstore.update_last_id (max_id);
        }

        public void restore_device_group_and_timers (DeviceGroup device_group)
        {
            if (this.restore_device_group (device_group)) {
                this.restore_timers (device_group);
            }
        }

        public DeviceGroup? get_device_group_if_exists (uint group_id) {
            DeviceGroup? result = null;
            lock (this.devices) {
                if (this.devices.has_key (group_id))
                    result = this.devices.get (group_id);
            }
            return result;
        }

        public bool device_is_in_any_group (Device device) {
            bool result = false;
            lock (this.devices) {
                foreach (uint group_id in this.devices.keys) {
                    DeviceGroup devgroup = this.devices.get (group_id);
                    if (devgroup.contains (device)) {
                        result = true;
                        break;
                    }
                }
            }
            return result;
        }

        private void on_scanner_destroyed (Scanner scanner) {
            uint adapter = scanner.Device.Adapter;
            uint frontend = scanner.Device.Frontend;

            string path = Constants.DBUS_SCANNER_PATH.printf (adapter, frontend);
            lock (this.scanners) {
                this.scanners.unset (path);
            }

            log.debug ("Destroying scanner for adapter %u, frontend %u (%s)", adapter,
                frontend, path);

            // Start epgscanner for device again if there was one
            DeviceGroup? devgroup = this.get_device_group_of_device (scanner.Device);
            if (devgroup != null) {
                devgroup.start_epg_scanner ();
            }
        }

        private Device? get_registered_device (uint adapter, uint frontend) {
            Device? result = null;
            Device fake_device = new Device (adapter, frontend);
            lock (this.devices) {
                foreach (uint group_id in this.devices.keys) {
                    DeviceGroup devgroup = this.devices.get (group_id);
                    if (devgroup.contains (fake_device)) {
                        foreach (Device device in devgroup) {
                            if (Device.equal (fake_device, device)) {
                                result = device;
                                break;
                            }
                        }
                    }
                }
            }

            return result;
        }

        private DeviceGroup? get_device_group_of_device (Device device) {
            DeviceGroup? result = null;
            lock (this.devices) {
                foreach (uint group_id in this.devices.keys) {
                    DeviceGroup devgroup = this.devices.get (group_id);
                    if (devgroup.contains (device)) {
                        foreach (Device grp_device in devgroup) {
                            if (Device.equal (grp_device, device)) {
                                result = devgroup;
                                break;
                            }
                        }
                    }
                }
            }

            return result;
        }

        private void on_device_removed_from_group (IDBusDeviceGroup idevgroup,
                uint adapter, uint frontend) {
            DeviceGroup devgroup = (DeviceGroup)idevgroup;
            uint group_id = devgroup.Id;
            if (devgroup.size == 0) {
                bool success;
                lock (this.devices) {
                    success = this.devices.unset (group_id);
                }
                if (success) {
                    devgroup.destroy ();

                    try {
                        new Factory().get_config_store ().remove_device_group (
                            devgroup);
                        new Factory().get_epg_store ().remove_events_of_group (
                            devgroup.Id
                        );
                        new Factory().get_timers_store ().remove_all_timers_from_device_group (
                            devgroup.Id
                        );
                        this.group_removed (group_id);
                    } catch (SqlError e) {
                        log.error ("%s", e.message);
                    }
                }
           }
        }

        private void create_device_group_by_id (uint group_id) {
            ConfigStore config_store = new Factory().get_config_store ();

            Gee.List<DeviceGroup> groups;
            try {
                groups = config_store.get_all_device_groups ();
            } catch (SqlError e) {
                log.error ("Error restoring group %u: %s", group_id,
                    e.message);
                return;
            }

            foreach (DeviceGroup group in groups) {
                if (group.Id == group_id) {
                    this.restore_device_group_and_timers (group);
                }
            }
        }

        private void on_udev_event (string action, GUdev.Device device) {
            if (action == "add" || action == "remove") {
                string dev_file = device.get_device_file ();

                uint adapter = -1, frontend = -1;
                if (dev_file.scanf ("/dev/dvb/adapter%u/frontend%u",
                        &adapter, &frontend) != 2)
                    return;

                uint group_id;
                bool found = false;
                ConfigStore config_store = new Factory().get_config_store ();
                try {
                    found = config_store.get_parent_group (adapter,
                            frontend, out group_id);
                } catch (SqlError e) {
                    critical ("%s", e.message);
                }
                if (!found)
                    return;

                log.debug ("%s device %s, part of group %u", action, dev_file,
                    group_id);

                DeviceGroup? group = this.get_device_group_if_exists (group_id);
                if (group != null)
                    group.stop_epg_scanner ();

                if (action == "add") {
                    if (group == null) {
                        /* This is the first device part of the group
                         * that has been added. We have to create the
                         * whole group */
                        this.create_device_group_by_id (group_id);
                    } else {
                        Device dvb_device = Device.new_with_type (adapter,
                            frontend);
                        if (dvb_device == null) return;

                        group.add (dvb_device);
                    }
                } else {
                    Device dvb_device = new Device (adapter, frontend);

                    // FIXME emit signal without removing
                    // the device from the DB
                    group.remove (dvb_device);
                }

                if (group != null)
                    group.start_epg_scanner ();
            }
        }

    }

}
