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

    /**
     * A group of devices that share the same settings
     * (list of channels, recordings dir)
     */
    public class DeviceGroup : GLib.Object, IDBusDeviceGroup, Traversable<Device>, Iterable<Device> {

        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        public int size {
            get { return this.devices.size; }
        }
        public Set<Device> Devices {
            get { return this.devices; }
        }
        public uint Id {get; construct;}
        public ChannelList Channels { get; construct; }
        public File RecordingsDirectory { get; set; }

        public AdapterType Type { get; construct; }

        public Recorder recorder {
            get { return this._recorder; }
        }
        public EPGScanner epgscanner {
            get { return this._epgscanner; }
        }
        public ChannelFactory channel_factory {
            get { return this._channelfactory; }
        }
        public string Name {get; set;}

        private Set<Device> devices;
        private Recorder _recorder;
        private EPGScanner? _epgscanner;
        private ChannelFactory _channelfactory;

        // Containss object paths to Schedule
        private HashSet<string> schedules;

        construct {
            this.devices = new HashSet<Device> (Device.hash, Device.equal);
            this.schedules = new HashSet<string> (
                Gee.Functions.get_hash_func_for(typeof(string)),
                Gee.Functions.get_equal_func_for(typeof(string)));
            this._channelfactory = new ChannelFactory (this);
            this._recorder = new Recorder (this);
        }

        /**
         * @id: ID of group
         * @channels_conf: the channel list file name (dvbv5 format)
         * @recordings_dir: directory in which the records are saved
         * @type: the type of this group (terrestrial, cable, satellite)
         * @with_epg_scanner: Whether to provide an EPG scanner
         */
        public DeviceGroup (uint id, File channels_conf, File recordings_dir, AdapterType type,
                bool with_epg_scanner=true) {
            Object (Id: id, Channels: new ChannelList (channels_conf), RecordingsDirectory: recordings_dir, Type: type);

	    Channels.GroupId = this.Id;

            if (with_epg_scanner) {
                this._epgscanner = new EPGScanner (this);
            } else {
                this._epgscanner = null;
            }
            this.register_channel_list ();
            this.register_recorder ();
        }

        public void destroy () {
            log.debug ("Destroying group %u", this.Id);
            this.stop_epg_scanner ();
            this._recorder.stop ();
            this._channelfactory.destroy ();
            this.schedules.clear ();
            lock (this.devices) {
                this.devices.clear ();
            }
        }

        public void start_epg_scanner () {
            if (this._epgscanner != null)
                this._epgscanner.start ();
        }

        public void stop_epg_scanner () {
            if (this._epgscanner != null)
                this._epgscanner.stop ();
        }

        /**
         * Add device to group. The device's settings will be overridden
         * with those of the reference device.
         */
        public bool add (Device device) {
            switch (this.Type) {
                case AdapterType.TERRESTRIAL:
                   if (!device.isTerrestrial ()) {
                       warning ("Cannot add device, because it is not of same type");
                       return false;
                   }
                   break;
                case AdapterType.SATELLITE:
                   if (!device.isSatellite ()) {
                       warning ("Cannot add device, because it is not of same type");
                       return false;
                   }
                   break;
                case AdapterType.CABLE:
                   if (!device.isCable ()) {
                       warning ("Cannot add device, because it is not of same type");
                       return false;
                   }
                   break;
            }

            bool result;
            lock (this.devices) {
                result = this.devices.add (device);
            }
            return result;
        }

        public bool contains (Device device) {
            bool result;
            lock (this.devices) {
                result = this.devices.contains (device);
            }
            return result;
        }

        public bool remove (Device device) {
            bool result;
            lock (this.devices) {
                result = this.devices.remove (device);
            }
            return result;
        }

        /**
         * Get first device that isn't busy.
         * If all devices are busy NULL is returned.
         */
        public Device? get_next_free_device () {
            Device? result = null;
            lock (this.devices) {
                foreach (Device dev in this.devices) {
                    if (!dev.is_busy ()) {
                        result = dev;
                        break;
                    }
                }
            }

            return result;
        }

        /**
         * @returns: Name of adapter type the group holds
         * or an empty string when group with given id doesn't exist.
         */
        public AdapterType GetType () throws DBusError {
            return this.Type;
        }

        /**
         * @adapter: Number of the device's adapter
         * @frontend: Number of the device's frontend
         * @returns: TRUE when the device has been registered successfully
         *
         * Creates a new device and adds it to the DeviceGroup.
         * The new device will inherit all settings from the group's
         * reference device.
         */
        public bool AddDevice (uint adapter, uint frontend) throws DBusError {
            // When the device is already registered we
            // might see some errors if the device is
            // currently in use
            Manager manager = Manager.get_instance ();

            Device device = manager.get_device (adapter, frontend);

            if (device == null) return false;

            if (manager.device_is_in_any_group (device, this.Type)) {
                log.debug ("Device with adapter %u, frontend %u is" +
                    "already part of a group", adapter, frontend);
                return false;
            }

            log.debug ("Adding device with adapter %u, frontend %u to group %u",
                adapter, frontend, this.Id);

            if (this.add (device)) {
                try {
                    new Factory().get_config_store ().add_device_to_group (device,
                        this);
                } catch (SqlError e) {
                    log.error ("%s", e.message);
                    return false;
                }

                this.device_added (adapter, frontend);

                return true;
            }

            return false;
        }

        /**
         * @returns: Object path of the device's recorder
         *
         * Returns the object path to the device's recorder.
         */
        public ObjectPath GetRecorder () throws DBusError {
            return new ObjectPath (
                Constants.DBUS_RECORDER_PATH.printf (this.Id));
        }

        protected bool register_recorder () {
            log.debug ("Creating new Recorder D-Bus service for group %u",
                this.Id);

            Recorder recorder = this.recorder;

            string path = Constants.DBUS_RECORDER_PATH.printf (this.Id);
            Utils.dbus_register_object<IDBusRecorder> (Main.conn,
                path, recorder);

            return true;
        }

        /**
         * @adapter: Number of the device's adapter
         * @frontend: Number of the device's frontend
         * @returns: TRUE when device has been removed successfully
         *
         * Removes the device from the group. If the group contains
         * no devices after the removal it's removed as well.
         */
        public bool RemoveDevice (uint adapter, uint frontend) throws DBusError {
            Manager m = Manager.get_instance ();

            Device dev = m.get_device (adapter, frontend);

            if (dev == null) return false;

            if (this.contains (dev)) {
                if (this.remove (dev)) {
                    // Stop epgscanner, because it might use the
                    // device we want to unregister
                    this.stop_epg_scanner ();

                    try {
                        new Factory().get_config_store ().remove_device_from_group (
                            dev, this);
                    } catch (SqlError e) {
                        log.error ("%s", e.message);
                        return false;
                    }
                    // Group has no devices anymore, delete it
                    if (this.size > 0) {
                        // We still have a device, start EPG scanner again
                        this.start_epg_scanner ();
                    }

                    this.device_removed (adapter, frontend);

                    return true;
                }
            }

            return false;
        }

        /**
         * @returns: Name of the device group
         */
        public string GetName () throws DBusError {
            return this.Name;
        }

        /**
         * @name: Name of the group
         * @returns: TRUE on success
         */
        public bool SetName (string name) throws DBusError {
            this.Name = name;
            try {
                ConfigStore config = new Factory().get_config_store();
                config.update_from_group (this);
            } catch (SqlError e) {
                log.error ("%s", e.message);
                return false;
            }
            return true;
        }

        /**
         * @returns: Object path to the ChannelList service for this device
         */
        public ObjectPath GetChannelList () throws DBusError {
            return new ObjectPath (
                Constants.DBUS_CHANNEL_LIST_PATH.printf (this.Id));
        }

        protected bool register_channel_list () {
            log.debug ("Creating new ChannelList D-Bus service for group %u",
                this.Id);

            ChannelList channels = this.Channels;

            string path = Constants.DBUS_CHANNEL_LIST_PATH.printf (this.Id);
            Utils.dbus_register_object<IDBusChannelList> (Main.conn,
                path, channels);

            return true;
        }

        /**
         * @returns: List of paths to the devices that are part of
         * the group (e.g. /dev/dvb/adapter0/frontend0)
         */
        public string[] GetMembers () throws DBusError {
            string[] groupdevs = new string[this.size];

            int i=0;
            lock (this.devices) {
                foreach (Device dev in this.devices) {
                    groupdevs[i] = Constants.DVB_DEVICE_PATH.printf (
                        dev.Adapter, dev.Frontend);
                    i++;
                }
            }

            return groupdevs;
        }
        /**
         * @channel_sid: ID of the channel
         * @opath: Device group's DBus path
         * @returns: TRUE on success
         */
        public bool GetSchedule (uint channel_sid, out ObjectPath opath) throws DBusError {
            if (this.Channels.contains (channel_sid)) {
                string path = Constants.DBUS_SCHEDULE_PATH.printf (this.Id, channel_sid);

                if (!this.schedules.contains (path)) {
                    Schedule schedule = this.Channels.get_channel (
                        channel_sid).Schedule;

                    Utils.dbus_register_object<IDBusSchedule> (Main.conn,
                        path, schedule);

                    this.schedules.add (path);
                }

                opath = new ObjectPath (path);
                return true;
            }

            opath = new ObjectPath ("");
            return false;
        }

        /**
         * @returns: Location of the recordings directory
         */
        public string GetRecordingsDirectory () throws DBusError {
            return this.RecordingsDirectory.get_path ();
        }

        /**
         * @location: Location of the recordings directory
         * @returns: TRUE on success
         */
        public bool SetRecordingsDirectory (string location) throws DBusError {
            this.RecordingsDirectory = File.new_for_path (location);
            try {
                ConfigStore config = new Factory().get_config_store();
                config.update_from_group (this);
            } catch (SqlError e) {
                log.error ("%s", e.message);
                return false;
            }
            return true;
        }

        public Type element_type { get { return typeof (Device); } }

        public Iterator<Device> iterator () {
            return this.devices.iterator();
        }

        public bool foreach (ForallFunc<Device> f) {
            return this.devices.iterator().foreach(f);
        }

    }

}
