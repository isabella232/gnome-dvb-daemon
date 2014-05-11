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
from gnomedvb import _
from gnomedvb.ui.wizard import DVB_TYPE_TO_DESC
from gnomedvb.Device import Device

__all__ = ["UnassignedDevicesStore", "DeviceGroupsStore", "DeviceGroupsView"]

class UnassignedDevicesStore (Gtk.ListStore):

    (COL_DEVICE,) = list(range(1))

    def __init__(self):
        Gtk.ListStore.__init__(self, GObject.TYPE_PYOBJECT)


class DeviceGroupsStore (Gtk.TreeStore):

    (COL_GROUP, COL_DEVICE,) = list(range(2))

    def __init__(self):
        Gtk.TreeStore.__init__(self, GObject.GObject, GObject.TYPE_PYOBJECT)

    def get_groups(self):
        groups = []
        for row in self:
            if not isinstance(row, Device):
                groups.append((row[self.COL_GROUP], row.iter))
        return groups


class DeviceGroupsView (Gtk.TreeView):

    def __init__(self, model):
        GObject.GObject.__init__(self)
        self.set_model(model)
        self.set_headers_visible(False)
        #self.set_reorderable(True)

        cell_description = Gtk.CellRendererText ()
        column_description = Gtk.TreeViewColumn (_("Devices"), cell_description)
        column_description.set_cell_data_func(cell_description, self.get_description_data, None)
        self.append_column(column_description)

    def get_description_data(self, column, cell, model, aiter, user_data=None):
        device = model[aiter][model.COL_DEVICE]

        if isinstance(device, Device):
            # translators: first is device's name, second its type
            text = _("<b>%s (%s)</b>\n") % (device.name, DVB_TYPE_TO_DESC[device.type])
            text += "<small>%s</small>" % (_("Adapter: %d, Frontend: %d") % (device.adapter,
                device.frontend))
        else:
            if device == "":
                group = model[aiter][model.COL_GROUP]
                text = _("Group %d") % group["id"]
            else:
                text = device[0]

        cell.set_property("markup", text)


