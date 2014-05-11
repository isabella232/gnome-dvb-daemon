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

from gi.repository import GObject
import re
import sys
from gi.repository import Gio

__all__ = [
    "global_error_handler",
    "get_adapter_info",
    "get_dvb_devices",
    "DVBManagerClient",
    "DVBDeviceGroupClient",
    "DVBScannerClient",
    "DVBRecordingsStoreClient",
    "DVBRecorderClient",
    "DVBChannelListClient",
    "DVBScheduleClient",
]

SERVICE = "org.gnome.DVB"
MANAGER_IFACE = "org.gnome.DVB.Manager"
MANAGER_PATH = "/org/gnome/DVB/Manager"
DEVICE_GROUP_IFACE = "org.gnome.DVB.DeviceGroup"
RECSTORE_IFACE = "org.gnome.DVB.RecordingsStore"
RECSTORE_PATH = "/org/gnome/DVB/RecordingsStore"
RECORDER_IFACE = "org.gnome.DVB.Recorder"
CHANNEL_LIST_IFACE = "org.gnome.DVB.ChannelList"
SCHEDULE_IFACE = "org.gnome.DVB.Schedule"

def _default_error_handler_func(*args):
    print("Error: " + str(args)) #, file=sys.stderr)

global_error_handler = _default_error_handler_func

def get_adapter_info(adapter, frontend):
    manager = DVBManagerClient()
    info_t, success = manager.get_adapter_info(adapter, frontend)
    info = {"name": info_t[0], "type_t": info_t[1], "type_s": info_t[2], "type_c": info_t[3]}
    return (success, info)

def get_dvb_devices():
    manager = DVBManagerClient()
    devices = manager.get_devices()

    deviceslist = []
    for dev in devices:
        match = re.search("adapter(\d+?)/frontend(\d+?)", dev["device_file"])
        if match != None:
            adapter = int(match.group(1))
            info = {}
            info["adapter"] = adapter
            info["frontend"] = int(match.group(2))
            deviceslist.append(info)

    return deviceslist

def _get_proxy(object_path, iface_name):
    return Gio.DBusProxy.new_for_bus_sync(Gio.BusType.SESSION,
        Gio.DBusProxyFlags.NONE, None,
        SERVICE,
        object_path,
        iface_name, None)

class DVBManagerClient(GObject.GObject):

    __gsignals__ = {
        "group-added":  (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int]),
        "group-removed":  (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int]),
    }

    def __init__(self):
        GObject.GObject.__init__(self)

        self.manager = _get_proxy(MANAGER_PATH, MANAGER_IFACE)
        self.manager.connect("g-signal", self.on_g_signal)

    def get_scanner_for_device(self, adapter, frontend, type):
        objpath, scanner_iface, success = self.manager.GetScannerForDevice ('(uui)', adapter, frontend, type)
        if success:
            return DVBScannerClient(objpath, scanner_iface)
        else:
            return None

    def get_device_group(self, group_id):
        path, success = self.manager.GetDeviceGroup('(u)', group_id)
        if success:
            return DVBDeviceGroupClient(path)
        else:
            return None

    def get_registered_device_groups(self, **kwargs):
        if "result_handler" in kwargs:
            result_handler = kwargs["result_handler"]
        else:
            result_handler = None

        def groups_handler(proxy, paths, user_data):
            result_handler([DVBDeviceGroupClient(path) for path in paths])

        if result_handler != None:
            self.manager.GetRegisteredDeviceGroups(result_handler=groups_handler,
                error_handler=kwargs["error_handler"])
        else:
            return [DVBDeviceGroupClient(path) for path in self.manager.GetRegisteredDeviceGroups()]

    def add_device_to_new_group (self, adapter, frontend, type, channels_file, recordings_dir, name, **kwargs):
        return self.manager.AddDeviceToNewGroup('(uuisss)', adapter, frontend, type, channels_file, recordings_dir, name, **kwargs)

    def get_name_of_registered_device(self, adapter, frontend, **kwargs):
        return self.manager.GetNameOfRegisteredDevice('(uu)', adapter, frontend, **kwargs)

    def get_device_group_size(self, **kwargs):
        return self.manager.GetDeviceGroupSize(**kwargs)

    def get_channel_groups(self, **kwargs):
        return self.manager.GetChannelGroups(**kwargs)

    def add_channel_group(self, name, **kwargs):
        return self.manager.AddChannelGroup('(s)', name, **kwargs)

    def remove_channel_group(self, group_id, **kwargs):
        return self.manager.RemoveChannelGroup('(i)', group_id, **kwargs)

    def get_devices(self, **kwargs):
        return self.manager.GetDevices()

    def get_adapter_info(self, adapter, frontend, **kwargs):
        return self.manager.GetAdapterInfo('(uu)', adapter, frontend, **kwargs)

    def on_g_signal(self, proxy, sender_name, signal_name, params):
        params = params.unpack()
        if signal_name == "GroupAdded":
            self.emit("group-added", params[0])
        elif signal_name == "GroupRemoved":
            self.emit("group-removed", params[0])

class DVBDeviceGroupClient(GObject.GObject):

    __gsignals__ = {
        "device-added":  (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int, int]),
        "device-removed":  (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int, int]),
    }

    def __init__(self, objpath):
        GObject.GObject.__init__(self)

        elements = objpath.split("/")

        self._id = int(elements[5])

        self.devgroup = _get_proxy(objpath, DEVICE_GROUP_IFACE)
        self.devgroup.connect("g-signal", self.on_g_signal)

    def get_id(self):
        return self._id

    def get_recorder(self):
        path = self.devgroup.GetRecorder()
        return DVBRecorderClient(path)

    def add_device (self, adapter, frontend, **kwargs):
        return self.devgroup.AddDevice('(uu)', adapter, frontend, **kwargs)

    def remove_device(self, adapter, frontend, **kwargs):
        return self.devgroup.RemoveDevice('(uu)', adapter, frontend, **kwargs)

    def get_channel_list(self):
        path = self.devgroup.GetChannelList()
        return DVBChannelListClient(path)

    def get_members(self, **kwargs):
        return self.devgroup.GetMembers(**kwargs)

    def get_name(self, **kwargs):
        return self.devgroup.GetName(**kwargs)

    def set_name(self, name, **kwargs):
        return self.devgroup.SetName('(s)', name, **kwargs)

    def get_type(self, **kwargs):
        return self.devgroup.GetType(**kwargs)

    def get_schedule(self, channel_sid):
        path, success = self.devgroup.GetSchedule('(u)', channel_sid)
        if success:
            return DVBScheduleClient(path)
        else:
            return None

    def get_recordings_directory (self, **kwargs):
        return self.devgroup.GetRecordingsDirectory(**kwargs)

    def set_recordings_directory (self, location, **kwargs):
        return self.devgroup.SetRecordingsDirectory('(s)', location, **kwargs)

    def on_g_signal(self, proxy, sender_name, signal_name, params):
        params = params.unpack()
        if signal_name == "DeviceAdded":
            self.emit("device-added", *params)
        elif signal_name == "DeviceRemoved":
            self.emit("device-removed", *params)

class DVBScannerClient(GObject.GObject):

    __gsignals__ = {
        "finished":          (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, []),
        "frequency-scanned": (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int, int]),
        "channel-added":     (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int, int, str, str, str, bool]),
        "destroyed":         (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, []),
        "frontend-stats":    (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [float, float]),
    }

    def __init__(self, objpath, scanner_iface):
        GObject.GObject.__init__(self)

        self.scanner = _get_proxy(objpath, scanner_iface)
        self.scanner.connect("g-signal", self.on_g_signal)

    def add_scanning_data(self, data, **kwargs):
        return self.scanner.AddScanningData ('(a{sv})', data, **kwargs)

    def add_scanning_data_from_file(self, path, **kwargs):
        return self.scanner.AddScanningDataFromFile('(s)', path, **kwargs)

    def run(self, **kwargs):
        self.scanner.Run(**kwargs)

    def destroy(self, **kwargs):
        self.scanner.Destroy(**kwargs)

    def write_channels_to_file(self, channel_sids, channelfile, **kwargs):
        self.scanner.WriteChannelsToFile('(aus)', channel_sids, channelfile, **kwargs)

    def write_all_channels_to_file(self, channelfile, **kwargs):
        self.scanner.WriteAllChannelsToFile('(s)', channelfile, **kwargs)

    def on_g_signal(self, proxy, sender_name, signal_name, params):
        params = params.unpack()
        if signal_name == "Finished":
            self.emit("finished")
        elif signal_name == "FrequencyScanned":
            self.emit("frequency-scanned", *params)
        elif signal_name == "ChannelAdded":
            self.emit("channel-added", *params)
        elif signal_name == "Destroyed":
            self.emit("destroyed")
        elif signal_name == "FrontendStats":
            self.emit("frontend-stats", *params)

class DVBRecordingsStoreClient(GObject.GObject):

    __gsignals__ = {
        "changed": (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int, int]),
    }

    def __init__(self):
        GObject.GObject.__init__(self)

        self.recstore = _get_proxy(RECSTORE_PATH, RECSTORE_IFACE)
        self.recstore.connect("g-signal", self.on_g_signal)

    def get_recordings(self, **kwargs):
        return self.recstore.GetRecordings(**kwargs)

    def get_location(self, rid, **kwargs):
        return self.recstore.GetLocation('(u)', rid, **kwargs)

    def get_name(self, rid, **kwargs):
        return self.recstore.GetName('(u)', rid, **kwargs)

    def get_description(self, rid, **kwargs):
        return self.recstore.GetDescription('(u)', rid, **kwargs)

    def get_length(self, rid, **kwargs):
        return self.recstore.GetLength('(u)', rid, **kwargs)

    def get_start_time(self, rid, **kwargs):
        return self.recstore.GetStartTime('(u)', rid, **kwargs)

    def get_start_timestamp(self, rid, **kwargs):
        return self.recstore.GetStartTimestamp('(u)', rid, **kwargs)

    def delete(self, rid, **kwargs):
        return self.recstore.Delete('(u)', rid, **kwargs)

    def get_channel_name(self, rid, **kwargs):
        return self.recstore.GetChannelName('(u)', rid, **kwargs)

    def get_all_informations(self, rid, **kwargs):
        return self.recstore.GetAllInformations('(u)', rid, **kwargs)

    def on_g_signal(self, proxy, sender_name, signal_name, params):
        params = params.unpack()
        if signal_name == "Changed":
            self.emit("changed", *params)

class DVBRecorderClient(GObject.GObject):

    __gsignals__ = {
        "recording-started": (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int]),
        "recording-finished": (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int]),
        "changed": (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int, int]),
    }

    def __init__(self, object_path):
        GObject.GObject.__init__(self)

        self.recorder = _get_proxy(object_path, RECORDER_IFACE)
        self.recorder.connect("g-signal", self.on_g_signal)
        self.object_path = object_path

    def get_path(self):
        return self.object_path

    def add_timer (self, channel, year, month, day, hour, minute, duration, **kwargs):
        return self.recorder.AddTimer('(uiiiiiu)', channel, year, month, day, hour, minute, duration, **kwargs)

    def add_timer_with_margin (self, channel, year, month, day, hour, minute, duration, **kwargs):
        return self.recorder.AddTimerWithMargin('(uiiiiiu)', channel, year, month, day, hour, minute, duration, **kwargs)

    def add_timer_for_epg_event(self, event_id, channel_sid, **kwargs):
        return self.recorder.AddTimerForEPGEvent('(uu)', event_id, channel_sid, **kwargs)

    def delete_timer(self, tid, **kwargs):
        return self.recorder.DeleteTimer('(u)', tid, **kwargs)

    def get_timers(self, **kwargs):
        return self.recorder.GetTimers(**kwargs)

    def get_start_time(self, tid, **kwargs):
        return self.recorder.GetStartTime('(u)', tid, **kwargs)

    def set_start_time(self, tid, year, month, day, hour, minute, **kwargs):
        return self.recorder.SetStartTime ('(uiiiii)', tid, year, month, day, hour, minute)

    def get_end_time(self, tid, **kwargs):
        return self.recorder.GetEndTime('(u)', tid, **kwargs)

    def get_duration(self, tid, **kwargs):
        return self.recorder.GetDuration('(u)', tid, **kwargs)

    def set_duration(self, tid, duration, **kwargs):
        return self.recorder.SetDuration('(uu)', tid, duration, **kwargs)

    def get_channel_name(self, tid, **kwargs):
        return self.recorder.GetChannelName('(u)', tid, **kwargs)

    def get_title(self, tid, **kwargs):
        return self.recorder.GetTitle('(u)', tid, **kwargs)

    def get_all_informations(self, tid, **kwargs):
        return self.recorder.GetAllInformations('(u)', tid, **kwargs)

    def get_active_timers(self, **kwargs):
        return self.recorder.GetActiveTimers(**kwargs)

    def is_timer_active(self, tid, **kwargs):
        return self.recorder.IsTimerActive('(u)', tid, **kwargs)

    def has_timer(self, year, month, day, hour, minute, duration, **kwargs):
        return self.recorder.HasTimer('(uuuuuu)', year, month, day, hour, minute, duration, **kwargs)

    def has_timer_for_event(self, event_id, channel_sid, **kwargs):
        return self.recorder.HasTimerForEvent('(uu)', event_id, channel_sid, **kwargs)

    def on_g_signal(self, proxy, sender_name, signal_name, params):
        params = params.unpack()
        if signal_name == "Changed":
            self.emit("changed", *params)
        elif signal_name == "RecordingStarted":
            self.emit("recording-started", params[0])
        elif signal_name == "RecordingFinished":
            self.emit("recording-finished", params[0])

class DVBChannelListClient:

    def __init__(self, object_path):
        self.channels = _get_proxy(object_path, CHANNEL_LIST_IFACE)
        self.object_path = object_path

    def get_path(self):
        return self.object_path

    def get_channels(self, **kwargs):
        return self.channels.GetChannels(**kwargs)

    def get_radio_channels(self, **kwargs):
        return self.channels.GetRadioChannels(**kwargs)

    def get_tv_channels(self, **kwargs):
        return self.channels.GetTVChannels(**kwargs)

    def get_channel_name(self, cid, **kwargs):
        return self.channels.GetChannelName('(u)', cid, **kwargs)

    def get_channel_network(self, cid, **kwargs):
        return self.channels.GetChannelNetwork('(u)', cid, **kwargs)

    def is_radio_channel(self, cid, **kwargs):
        return self.channels.IsRadioChannel('(u)', cid, **kwargs)

    def get_channel_url(self, cid, **kwargs):
        return self.channels.GetChannelURL('(u)', cid, **kwargs)

    def get_channel_infos(self, **kwargs):
        return self.channels.GetChannelInfos(**kwargs)

    def get_channels_of_group(self, group_id, **kwargs):
        return self.channels.GetChannelsOfGroup('(i)', group_id, **kwargs)

    def add_channel_to_group(self, cid, group_id, **kwargs):
        return self.channels.AddChannelToGroup('(ui)', cid, group_id, **kwargs)

    def remove_channel_from_group(self, cid, group_id, **kwargs):
        return self.channels.RemoveChannelFromGroup('(ui)', cid, group_id, **kwargs)

class DVBScheduleClient(GObject.GObject):

    def __init__(self, object_path):
        GObject.GObject.__init__(self)

        # "/org/gnome/DVB/DeviceGroup/%u/Schedule/%u";
        elements = object_path.split("/")

        self._group = int(elements[5])
        self._sid = int(elements[7])

        self.schedule = _get_proxy(object_path, SCHEDULE_IFACE)

    def get_group_id(self):
        return self._group

    def get_channel_sid(self):
        return self._sid

    def get_all_events(self, **kwargs):
        return self.schedule.GetAllEvents(**kwargs)

    def get_all_event_infos(self, **kwargs):
        return self.schedule.GetAllEventInfos(**kwargs)

    def get_informations(self, eid, **kwargs):
        return self.schedule.GetInformations('(u)', eid, **kwargs)

    def now_playing(self, **kwargs):
        return self.schedule.NowPlaying(**kwargs)

    def next(self, eid, **kwargs):
        return self.schedule.Next('(u)', eid, **kwargs)

    def get_name(self, eid, **kwargs):
        return self.schedule.GetName('(u)', eid, **kwargs)

    def get_short_description(self, eid, **kwargs):
        return self.schedule.GetShortDescription('(u)', eid, **kwargs)

    def get_extended_description(self, eid, **kwargs):
        return self.schedule.GetExtendedDescription('(u)', eid, **kwargs)

    def get_duration(self, eid, **kwargs):
        return self.schedule.GetDuration('(u)', eid, **kwargs)

    def get_local_start_time(self, eid, **kwargs):
        return self.schedule.GetLocalStartTime('(u)', eid, **kwargs)

    def get_local_start_timestamp(self, eid, **kwargs):
        return self.schedule.GetLocalStartTimestamp('(u)', eid, **kwargs)

    def is_running(self, eid, **kwargs):
        return self.schedule.IsRunning('(u)', eid, **kwargs)

    def is_scrambled(self, eid, **kwargs):
        return self.schedule.IsScrambled('(u)', eid, **kwargs)

