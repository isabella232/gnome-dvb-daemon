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

from gi.repository import Gtk
from gi.repository import GObject
import gnomedvb
from gnomedvb import global_error_handler
from gnomedvb.Callback import Callback
from cgi import escape
from gnomedvb import _

class ChannelsStore(Gtk.ListStore):

    (COL_NAME,
     COL_SID,) = list(range(2))

    __gsignals__ = {
        "loading-finished":  (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, []),
    }

    def __init__(self, device_group):
        """
        @param device_group: ID of device group the
        list of channels should be retrieved
        """

        Gtk.ListStore.__init__(self, str, int)

        self.set_sort_column_id(self.COL_NAME,
            Gtk.SortType.ASCENDING)

        self._add_channels(device_group)

    def _add_channels(self, device_group):
        channellist = device_group.get_channel_list()

        def append_channel(proxy, channels, user_data):
            for channel_id, name, is_radio in channels:
                self.append([name, channel_id])
            self.emit("loading-finished")

        channellist.get_channel_infos(result_handler=append_channel,
            error_handler=global_error_handler)


class ChannelsTreeStore(Gtk.TreeStore):

    (COL_GROUP_ID,
     COL_NAME,
     COL_SID,
     COL_GROUP,) = list(range(4))

    __gsignals__ = {
        "loading-finished":  (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [int]),
    }

    def __init__(self, use_channel_groups=False):
        Gtk.TreeStore.__init__(self, int, str, int, GObject.GObject)

        self.set_sort_order(Gtk.SortType.ASCENDING)

        self._use_channel_groups = use_channel_groups
        self._manager = gnomedvb.DVBManagerClient ()
        self._manager.connect('group-added', self._on_manager_group_added)
        self._manager.connect('group-removed', self._on_manager_group_removed)
        self._add_channels()

    def _add_channels(self):
        def append_groups(dev_groups):
            for dev_group in dev_groups:
                self._append_group(dev_group)

        self._manager.get_registered_device_groups(result_handler=append_groups,
            error_handler=global_error_handler)

    def _append_group(self, dev_group):
        group_id = dev_group.get_id()
        group_name = dev_group.get_name()

        group_iter = self.append(None, [group_id, group_name, 0, dev_group])
        channellist = dev_group.get_channel_list()

        d = Callback()
        if self._use_channel_groups:
            d.add_callback(self._append_channel_groups, channellist, group_id,
                group_iter, dev_group)
            self._manager.get_channel_groups(
                result_handler=lambda p,x,u: d.callback(x),
                error_handler=global_error_handler)
            # Put all available channels either in TV or radio group
            tv_group_iter = self.append(group_iter,
                [group_id, _("TV Channels"), 0, dev_group])
            radio_group_iter = self.append(group_iter,
                [group_id, _("Radio Channels"), 0, dev_group])
        else:
            # Do not distinguish between radio and TV
            tv_group_iter = group_iter
            radio_group_iter = group_iter

        d_all = Callback()
        d_all.add_callback(self._append_channels, group_id,
            dev_group, tv_group_iter, radio_group_iter)
        channellist.get_channel_infos(
            result_handler=lambda p,x,u: d_all.callback(x),
            error_handler=global_error_handler)

    def _append_channels(self, channels, group_id, dev_group, tv_group_iter, radio_group_iter):
        for channel_id, name, is_radio in channels:
            if is_radio:
                group_iter = radio_group_iter
            else:
                group_iter = tv_group_iter

            self.append(group_iter,
                [group_id,
                escape(name),
                channel_id,
                dev_group])
        self.emit("loading-finished", group_id)

    def _append_channel_groups(self, channel_groups, channellist, group_id, group_iter, dev_group):
        def append_channel(channels, chan_group_iter):
            for channel_id in channels:
                name, success = channellist.get_channel_name(channel_id)
                if success:
                    self.append(chan_group_iter,
                        [group_id,
                        escape(name),
                        channel_id,
                        dev_group])

        for chan_group_id, name in channel_groups:
            chan_group_iter = self.append(group_iter, [group_id, escape(name),
                0, dev_group])
            d = Callback()
            d.add_callback(append_channel, chan_group_iter)
            channellist.get_channels_of_group(chan_group_id,
                result_handler=lambda p,data,u: d.callback(data[1]),
                error_handler=global_error_handler)

        self.emit("loading-finished", group_id)

    def _on_manager_group_added(self, manager, group_id):
        group = manager.get_device_group(group_id)
        if group != None:
            self._append_group(group)

    def _on_manager_group_removed(self, manager, group_id):
        for row in self:
            if row[self.COL_GROUP_ID] == group_id:
                self.remove(row.iter)
                break

    def set_sort_order(self, order):
        self.set_sort_column_id(self.COL_NAME, order)

