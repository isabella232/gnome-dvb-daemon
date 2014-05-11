/*
 * Copyright (C) 2009 Sebastian Pölsterl
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

    [DBus (name = "org.gnome.DVB.DeviceGroup")]
    public interface IDBusDeviceGroup : GLib.Object {

        public abstract signal void device_added (uint adapter, uint frontend);
        public abstract signal void device_removed (uint adapter, uint frontend);

        /**
         * @returns: Name of adapter type the group holds
         * or an empty string when group with given id doesn't exist.
         */
        public abstract AdapterType GetType () throws DBusError;

        /**
         * @returns: Object path of the device's recorder
         *
         * Returns the object path to the device's recorder.
         */
        public abstract ObjectPath GetRecorder () throws DBusError;

         /**
         * @adapter: Number of the device's adapter
         * @frontend: Number of the device's frontend
         * @group_id: ID of device group
         * @returns: TRUE when the device has been registered successfully
         *
         * Creates a new device and adds it to the specified DeviceGroup.
         * The new device will inherit all settings from the group's
         * reference device.
         */
        public abstract bool AddDevice (uint adapter, uint frontend) throws DBusError;

        /**
         * @adapter: Number of the device's adapter
         * @frontend: Number of the device's frontend
         * @returns: TRUE when device has been removed successfully
         *
         * Removes the device from the group. If the group contains
         * no devices after the removal it's removed as well.
         */
        public abstract bool RemoveDevice (uint adapter, uint frontend) throws DBusError;

        /**
         * @returns: Object path to the ChannelList service for this device
         */
        public abstract ObjectPath GetChannelList () throws DBusError;

        /**
         * @returns: Name of the device group
         */
        public abstract string GetName () throws DBusError;

        /**
         * @name: Name of the group
         * @returns: TRUE on success
         */
        public abstract bool SetName (string name) throws DBusError;

        /**
         * @returns: List of paths to the devices that are part of
         * the group (e.g. /dev/dvb/adapter0/frontend0)
         */
        public abstract string[] GetMembers () throws DBusError;

        /**
         * @channel_sid: ID of the channel
         * @opath: Object path to Schedule service
         * @returns: TRUE on success
         */
        public abstract bool GetSchedule (uint channel_sid, out ObjectPath opath) throws DBusError;

        /**
         * @returns: Location of the recordings directory
         */
        public abstract string GetRecordingsDirectory () throws DBusError;

        /**
         * @location: Location of the recordings directory
         * @returns: TRUE on success
         */
        public abstract bool SetRecordingsDirectory (string location) throws DBusError;

    }

}
