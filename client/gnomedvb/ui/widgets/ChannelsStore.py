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

import gtk
import gnomedvb
from gnomedvb import global_error_handler

class ChannelsStore(gtk.ListStore):

    (COL_NAME,
     COL_SID,) = range(2)

    def __init__(self, device_group):
        """
        @param device_group: ID of device group the
        list of channels should be retrieved
        """
    
        gtk.ListStore.__init__(self, str, int)
        
        self.set_sort_column_id(self.COL_NAME,
            gtk.SORT_ASCENDING)
            
        self._add_channels(device_group)
        
    def _add_channels(self, device_group):
        channellist = device_group.get_channel_list()
        
        def append_channel(channels):
            for channel_id in channels:
                name = channellist.get_channel_name(channel_id)
                self.append([name, channel_id])
        
        channellist.get_channels(reply_handler=append_channel, error_handler=global_error_handler)


class ChannelsTreeStore(gtk.TreeStore):

    (COL_GROUP_ID,
     COL_NAME,
     COL_SID,) = range(3)
     
    def __init__(self):
        gtk.TreeStore.__init__(self, int, str, int)
        
        self.set_sort_column_id(self.COL_NAME,
            gtk.SORT_ASCENDING)
            
        self._add_channels()
            
    def _add_channels(self):
        manager = gnomedvb.DVBManagerClient ()
        dev_groups = manager.get_registered_device_groups()
    
        for dev_group in dev_groups:
            group_id = dev_group.get_id()
            group_name = dev_group.get_name()
            group_iter = self.append(None, [group_id, group_name, 0])
            channellist = dev_group.get_channel_list()
            append_channel = lambda channels: [self.append(group_iter, [group_id, channellist.get_channel_name(channel_id), channel_id]) for channel_id in channels]
            channellist.get_channels(reply_handler=append_channel, error_handler=global_error_handler)
         
