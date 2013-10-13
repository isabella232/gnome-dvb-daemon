# -*- coding: utf-8 -*-
# Copyright (C) 2009 Sebastian Pölsterl
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
from gnomedvb import global_error_handler
from cgi import escape

class RunningNextStore(Gtk.ListStore):

    (COL_CHANNEL,
     COL_RUNNING_START,
     COL_RUNNING,
     COL_NEXT_START,
     COL_NEXT,
     COL_SID,
     COL_RUNNING_EVENT,
     COL_NEXT_EVENT) = list(range(8))

    def __init__(self, group):
        Gtk.ListStore.__init__(self, str, int, str, int, str, int, int, int)

        self.set_sort_column_id(self.COL_CHANNEL,
            Gtk.SortType.ASCENDING)

        self._group = group
        self._fill()

    def get_device_group(self):
        return self._group

    def _fill(self):
        channellist = self._group.get_channel_list()

        def add_channels(proxy, channels, user_data):
            for sid, name, is_radio in channels:
                aiter = self.append()
                self.set_value(aiter, self.COL_CHANNEL, name)
                self.set_value(aiter, self.COL_SID, sid)

                sched = self._group.get_schedule(sid)
                now = sched.now_playing()
                if now != 0:
                    next_id, name, duration, short_desc = sched.get_informations(now)[0][1:]

                    self.set_value(aiter, self.COL_RUNNING_START, sched.get_local_start_timestamp(now)[0])
                    self.set_value(aiter, self.COL_RUNNING, escape(name))
                    self.set_value(aiter, self.COL_RUNNING_EVENT, now)
                    if next_id != 0:
                        name, duration, short_desc = sched.get_informations(next_id)[0][2:]
                        self.set_value(aiter, self.COL_NEXT_START, sched.get_local_start_timestamp(next_id)[0])
                        self.set_value(aiter, self.COL_NEXT, escape(name))
                        self.set_value(aiter, self.COL_NEXT_EVENT, next_id)

        channellist.get_channel_infos(result_handler=add_channels,
            error_handler=global_error_handler)
