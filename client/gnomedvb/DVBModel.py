# -*- coding: utf-8 -*-
# Copyright (C) 2008,2009 Sebastian Pölsterl
#
# This file is part of GNOME DVB Daemon.
#
# GNOME DVB Daemon is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# GNOME DVB Daemon is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GNOME DVB Daemon.  If not, see <http://www.gnu.org/licenses/>.

import gnomedvb
from gnomedvb import GROUP_UNKNOWN
from gnomedvb import GROUP_TERRESTRIAL
from gnomedvb import GROUP_SATELLITE
from gnomedvb import GROUP_CABLE
import re
from gnomedvb.Device import Device
import copy

class DVBModel (gnomedvb.DVBManagerClient):

    def __init__(self):
        gnomedvb.DVBManagerClient.__init__(self)

    def get_device_group(self, group_id):
        path, success = self.manager.GetDeviceGroup('(u)', group_id)
        if success:
            return DeviceGroup(path)
        else:
            return None

    def get_registered_device_groups(self, result_handler,
            error_handler=gnomedvb.global_error_handler):
        def groups_handler(proxy, paths, user_data):
            result_handler([DeviceGroup(path) for path in paths])

        if result_handler:
            self.manager.GetRegisteredDeviceGroups(result_handler=groups_handler,
                error_handler=error_handler)
        else:
            return [DeviceGroup(path) for path in self.manager.GetRegisteredDeviceGroups()]

    def get_all_devices(self, result_handler,
            error_handler=gnomedvb.global_error_handler):
        """
        @returns: list of Device
        """
        devs = []
        for info in gnomedvb.get_dvb_devices():
            dev = Device (0, "Unknown", info["adapter"], info["frontend"],
                GROUP_UNKNOWN)
            devs.append(dev)
        result_handler(devs)

    def get_unregistered_devices(self, result_handler,
            error_handler=gnomedvb.global_error_handler):
        """
        @returns: set of Device
        """
        def devices_handler(devices):
            unregistered = set()
            for dev in devices:
                if dev not in registered:
                    success, info = gnomedvb.get_adapter_info(dev.adapter,
                        dev.frontend)
                    if success:
                        if info["type_t"]:
                            dev_t = copy.copy(dev)
                            dev_t.name = info["name"]
                            dev_t.type = GROUP_TERRESTRIAL
                            unregistered.add(dev_t)
                        if info["type_s"]:
                            dev_s = copy.copy(dev)
                            dev_s.name = info["name"]
                            dev_s.type = GROUP_SATELLITE
                            unregistered.add(dev_s)
                        if info["type_c"]:
                            dev_c = copy.copy(dev)
                            dev_c.name = info["name"]
                            dev_c.type = GROUP_CABLE
                            unregistered.add(dev_c)
            result_handler(unregistered)

        def registered_handler(devgroups):
            for group in devgroups:
                for dev in group["devices"]:
                    registered.add(dev)
            self.get_all_devices(result_handler=devices_handler,
                error_handler=error_handler)

        registered = set()
        self.get_registered_device_groups(result_handler=registered_handler,
            error_handler=error_handler)

class DeviceGroup(gnomedvb.DVBDeviceGroupClient):

    def __init__(self, objpath):
        gnomedvb.DVBDeviceGroupClient.__init__(self, objpath)

        self._adapter_pattern = re.compile("adapter(\d+?)/frontend(\d+?)")
        self._name = self.get_name()
        self._type = self.get_type()
        self._members = self.get_members()

    def __getitem__(self, key):
        if key == "id":
            return self._id
        elif key == "name":
            return self._name
        elif key == "devices":
            return self._members
        elif key == "type":
            return self._type
        else:
            raise KeyError("Unknown key "+str(key))

    def get_members(self):
        devices = []
        manager = gnomedvb.DVBManagerClient()
        for device_path in gnomedvb.DVBDeviceGroupClient.get_members(self):
            match = self._adapter_pattern.search(device_path)
            if match != None:
                adapter = int(match.group(1))
                frontend = int(match.group(2))
                devname, success = manager.get_name_of_registered_device(adapter, frontend)
                dev = Device (self._id, devname, adapter, frontend, self._type)
                dev.group_name = self._name
                devices.append(dev)
        return devices

    def remove_device(self, device, **kwargs):
        return gnomedvb.DVBDeviceGroupClient.remove_device(self, device.adapter,
            device.frontend, **kwargs)
