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
                return this.groups.values;
            }
        }

        public Gee.ArrayList<Device> devs {
            get {
                return this.devices;
            }
        }
        // Map object path to Scanner
        private HashMap<string, ScannerData> scanners;

        // Maps device group id to Device
        private HashMap<uint, DeviceGroup> groups;

        // Collection of devices
        private Gee.ArrayList<Device> devices;

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
            this.groups = new HashMap<uint, DeviceGroup> ();
            this.devices = new Gee.ArrayList<Device> ();
            this.device_group_counter = 0;
            this.udev_client = new GUdev.Client (UDEV_SUBSYSTEMS);
            this.udev_client.uevent.connect (this.on_udev_event);

            GLib.List<GUdev.Device> devs = this.udev_client.query_by_subsystem ("dvb");
            foreach (GUdev.Device dev in devs) this.first_add_device (dev);
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
                    m.devices.clear ();
                }

                lock (m.groups) {
                    foreach (DeviceGroup devgrp in m.groups.values) {
                        devgrp.destroy ();
                    }
                    m.groups.clear ();
                }

                instance = null;
            }
            instance_mutex.unlock ();
        }

        /**
         * @adapter: Number of the device's adapter
         * @frontend: Number of the device's frontend
         * @type: the type to scanned
         * @opath: Object path of the scanner service
         * @dbusiface: DBus interface of the scanner service
         * @returns: TRUE on success
         *
         * Get the object path of the channel scanner for this device.
         */
        public bool GetScannerForDevice (uint adapter, uint frontend, AdapterType type,
                out ObjectPath opath, out string dbusiface) throws DBusError
        {
            string path = Constants.DBUS_SCANNER_PATH.printf (adapter, frontend);
            opath = new ObjectPath (path);

            dbusiface = "";

            Device? device = this.get_device (adapter, frontend);
            if (device == null)
                return false;

            dbusiface = "org.gnome.DVB.Scanner";

            /* stop epgscanner for device if there's any */
            DeviceGroup[] groups = get_device_groups_of_device (device);
            foreach (DeviceGroup group in groups) {
                group.stop_epg_scanner ();
            }


            lock (this.scanners) {
                if (!this.scanners.has_key (path)) {
                    ScannerData data = new ScannerData ();
                    /* change to universal Scanner */
                    data.scanner = new Scanner (device, type);

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
            lock (this.groups) {
                if (this.groups.has_key (group_id)) {
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
            ObjectPath[] devs = new ObjectPath[this.groups.size];
            log.debug ("%d", this.groups.size);
            int i = 0;
            lock (this.groups) {
                foreach (uint key in this.groups.keys) {
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
         * @type: type of the new group
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
        public bool AddDeviceToNewGroup (uint adapter, uint frontend, AdapterType type,
                string channels_conf, string recordings_dir, string name)
                throws DBusError
        {
            File chan_file = File.new_for_path (channels_conf);
            File rec_dir = File.new_for_path (recordings_dir);

            /* search device */
            Device device = this.get_device (adapter, frontend);
            if (device == null) return false;

            // Check if device is already assigned to other group
            if (this.device_is_in_any_group (device, type)) return false;

            device_group_counter++;

            DeviceGroup devgroup = new DeviceGroup (device_group_counter, chan_file, rec_dir, type);
            if (devgroup == null) return false;

            devgroup.Name = name;

            this.add_device_group (devgroup, true);
            this.group_added (device_group_counter);

            if (devgroup.add (device)) {
                try {
                    new Factory().get_config_store ().add_device_to_group (device,
                        devgroup);
                } catch (SqlError e) {
                    log.error ("%s", e.message);
                    return false;
                }

            }

            devgroup.device_added (adapter, frontend);

            this.restore_device_group_and_timers (devgroup);

            devgroup.start_epg_scanner ();

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
            Device? dev = this.get_device (adapter, frontend);

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
            return this.groups.size;
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

            var arr = new GLib.HashTable<string, string>[devices.size];

            for (int i = 0; i < this.devices.size; i++) {
               Device dev = this.devices.get(i);
               var map = new HashTable<string, string>.full (GLib.str_hash,
                  GLib.str_equal, GLib.g_free, GLib.g_free);

               map.insert ("device_file", "/dev/dvb/adapter%u/frontend%u".printf(dev.Adapter, dev.Frontend));
               arr[i] = map;
            }
            return arr;
        }

        /**
         * @adapter: the adapter
         * @frontend: the frontend
         * @info: return the AdapterInfo structure
         * @returns: #false if device cannot found, otherwise #true
         */
        public bool GetAdapterInfo (uint adapter, uint frontend, out AdapterInfo info) throws DBusError {
            info = AdapterInfo ();

            Device? dev = this.get_device (adapter, frontend);

            if (dev == null) return false;

            info.name = dev.Name;
            info.type_t = dev.isTerrestrial ();
            info.type_s = dev.isSatellite ();
            info.type_c = dev.isCable ();

            return true;
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

            lock (this.groups) {
                this.groups.set (group_id, devgroup);
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

            return true;
        }

        public bool restore_device_group (DeviceGroup device_group, bool store = true) {
            log.info ("Restoring group %u", device_group.Id);

            try {
                device_group.Channels.load (device_group.Type);
            } catch (Error e) {
                log.error ("Error reading channels from file: %s", e.message);
                return false;
            }

            return this.add_device_group (device_group, false);
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

        public void restore_device_group_and_timers (DeviceGroup device_group) {
            if (this.restore_device_group (device_group)) {
                this.restore_timers (device_group);
            }
            log.debug ("add media factory");
            Gst.RTSPMountPoints points = DVB.RTSPServer.server.get_mount_points ();
            foreach (Channel channel in device_group.Channels) {
                MediaFactory factory = new MediaFactory ();
                points.add_factory ("/%u/%u".printf (device_group.Id, channel.Sid), factory);
            }
        }

        public DeviceGroup? get_device_group_if_exists (uint group_id) {
            DeviceGroup? result = null;
            lock (this.groups) {
                if (this.groups.has_key (group_id))
                    result = this.groups.get (group_id);
            }
            return result;
        }

        public bool device_is_in_any_group (Device device, AdapterType type) {
            bool result = false;
            lock (this.groups) {
                foreach (uint group_id in this.groups.keys) {
                    DeviceGroup devgroup = this.groups.get (group_id);
                    if (devgroup.contains (device) && devgroup.Type == type) {
                        result = true;
                        break;
                    }
                }
            }
            return result;
        }

        public Device? get_device (uint adapter, uint frontend) {
            Device? ret = null;
            lock (this.devices) {
                foreach (Device d in this.devices) {
                    if (d.Adapter == adapter && d.Frontend == frontend) {
                        ret = d;
                        break;
                    }
                }
            }
            return ret;
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
            DeviceGroup[]? devgroups = this.get_device_groups_of_device(scanner.Device);
            foreach (DeviceGroup group in devgroups) {
                if (group != null)
                    group.start_epg_scanner ();
            }
        }

        private DeviceGroup[]? get_device_groups_of_device (Device device) {
            DeviceGroup[]? ret = new DeviceGroup[this.groups.size];
            lock (this.groups) {
                uint i = 0;
                foreach (uint group_id in this.groups.keys) {
                    DeviceGroup devgroup = this.groups.get (group_id);
                    if (devgroup.contains (device)) {
                        ret[i] = devgroup;
                        i++;
                    }
                }
            }
            return ret;
        }

        private void on_device_removed_from_group (IDBusDeviceGroup idevgroup,
                uint adapter, uint frontend) {
            DeviceGroup devgroup = (DeviceGroup)idevgroup;
            uint group_id = devgroup.Id;
            if (devgroup.size == 0) {
                bool success;
                lock (this.groups) {
                    success = this.groups.unset (group_id);
                }
                if (success) {
                    bool lastest = false;
                    try {
                        lastest = new Factory().get_config_store ().is_last_device (group_id);
                    } catch (SqlError e) {
                        log.error ("%s", e.message);
                    }

                    if ( lastest ) {
                        Gst.RTSPMountPoints points = DVB.RTSPServer.server.get_mount_points ();
                        foreach (Channel channel in devgroup.Channels)
                            points.remove_factory ("/%u/%u".printf (devgroup.Id, channel.Sid));

                        try {
                            new Factory().get_config_store ().remove_device_group (
                                devgroup);
                            new Factory().get_epg_store ().remove_events_of_group (
                                devgroup.Id
                            );
                            new Factory().get_timers_store ().remove_all_timers_from_device_group (
                                devgroup.Id
                            );

                        } catch (SqlError e) {
                               log.error ("%s", e.message);
                        }
                    }
                    devgroup.destroy ();
                    this.group_removed (group_id);
                }
            }
        }

        private DeviceGroup? create_device_group_by_id (uint group_id) {
            ConfigStore config_store = new Factory().get_config_store ();

            DeviceGroup? group = null;

            try {
                group = config_store.get_device_group (group_id);
            } catch (SqlError e) {
                log.error ("Error restoring group %u: %s", group_id,
                    e.message);
                return group;
            }
            if (group == null)
                log.debug ("device group is null");
            add_device_group(group, false);

            this.restore_device_group_and_timers (group);
            this.group_added (group.Id);
            return group;
        }

        private void first_add_device (GUdev.Device device) {
            string dev_file = device.get_device_file ();

            if (device.get_property ("DVB_DEVICE_TYPE") != "frontend")
                return;

            uint adapter = (uint)device.get_property_as_uint64 ("DVB_ADAPTER_NUM");
            uint frontend = (uint)device.get_property_as_uint64 ("DVB_DEVICE_NUM");

            Device dvb_device = new Device.with_udev (device, dev_file, adapter, frontend);
            this.devices.add(dvb_device);
        }

        private void on_udev_event (string action, GUdev.Device device) {
            if (action == "add" || action == "remove") {
                string dev_file = device.get_device_file ();

                if (device.get_property ("DVB_DEVICE_TYPE") != "frontend")
                    return;

                uint adapter = (uint)device.get_property_as_uint64 ("DVB_ADAPTER_NUM");
                uint frontend = (uint)device.get_property_as_uint64 ("DVB_DEVICE_NUM");

                /* Search all groups in which this device is */
                uint[] group_ids;
                bool found = false;
                ConfigStore config_store = new Factory().get_config_store ();
                try {
                    found = config_store.get_parent_groups (adapter,
                            frontend, out group_ids);
                } catch (SqlError e) {
                    critical ("%s", e.message);
                }

                log.debug ("%s device %s", action, dev_file);

                if (found) {
                    foreach (uint group_id in group_ids) {
                        log.debug ("DeviceGroup ID: %u", group_id);

                        DeviceGroup? group = this.get_device_group_if_exists (group_id);

                        if (group == null)
                            group = this.create_device_group_by_id (group_id);

                        if (group != null)
                            group.stop_epg_scanner ();
                    }
                }

                if (action == "add") {
                    Device dvb_device = new Device.with_udev (device, dev_file, adapter, frontend);
                    this.devices.add(dvb_device);

                    if (found) {
                        foreach (uint group_id in group_ids) {
                            DeviceGroup? group = this.get_device_group_if_exists (group_id);
                            if (group != null) {
                               if (group.add (dvb_device))
                                   group.device_added (dvb_device.Adapter, dvb_device.Frontend);
                            }
                        }
                    }
                } else {

                    /* Search device in devices */
                    foreach (Device d in this.devices) {
                        if (d.Frontend == frontend && d.Adapter == adapter) {

                            this.devices.remove(d);

                        }
                        if (found) {
                            foreach (uint group_id in group_ids) {
                                DeviceGroup? group = this.get_device_group_if_exists (group_id);
                                if (group != null) {
                                    if (group.remove (d))
                                        group.device_removed (d.Adapter, d.Frontend);

                                }
                            }
                        }
                    }

                }

                log.debug("Numbers of devices %u", this.devices.size);

                if (found) {
                    foreach (uint group_id in group_ids) {
                        DeviceGroup? group = this.get_device_group_if_exists (group_id);
                        if (group != null)
                            group.start_epg_scanner ();
                    }
                }
            }
        }

    }

}
