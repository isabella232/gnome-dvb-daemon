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

namespace DVB.database {

    public interface ConfigStore : GLib.Object {

        public abstract Gee.List<DeviceGroup> get_all_device_groups () throws SqlError;
        public abstract DeviceGroup? get_device_group (uint group_id) throws SqlError;
        public abstract bool is_last_device (uint group_id) throws SqlError;
        public abstract bool is_group_member (Device dev, DeviceGroup group) throws SqlError;
        public abstract bool add_device_group (DeviceGroup dev_group) throws SqlError;
        public abstract bool remove_device_group (DeviceGroup devgroup) throws SqlError;
        public abstract bool add_device_to_group (Device dev, DeviceGroup devgroup) throws SqlError;
        public abstract bool remove_device_from_group (Device dev, DeviceGroup devgroup) throws SqlError;
        public abstract bool update_from_group (DeviceGroup devgroup) throws SqlError;

        public abstract bool get_parent_groups (uint adapter, uint frontend, out uint[] group_ids) throws SqlError;

        public abstract bool add_channel_group (string name, out int channel_group_id) throws SqlError;
        public abstract bool remove_channel_group (int group_id) throws SqlError;
        public abstract Gee.List<ChannelGroup> get_channel_groups () throws SqlError;
        public abstract Gee.List<uint> get_channels_of_group (uint dev_group_id, int channel_group_id) throws SqlError;
        public abstract bool add_channel_to_group (Channel channel, int group_id) throws SqlError;
        public abstract bool remove_channel_from_group (Channel channel, int group_id) throws SqlError;

    }

}
