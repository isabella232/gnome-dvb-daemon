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
import gnomedvb
from gi.repository import Gtk
from gnomedvb import _
from gnomedvb.Device import Device
from gnomedvb import GROUP_TERRESTRIAL
from gnomedvb import GROUP_SATELLITE
from gnomedvb import GROUP_CABLE
from gnomedvb.ui.wizard import DVB_TYPE_TO_DESC
from gnomedvb.ui.wizard.pages.BasePage import BasePage
from gnomedvb.ui.widgets.Frame import BaseFrame
import copy

class AdaptersPage(BasePage):

    __gsignals__ = {
        "finished": (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, [bool]),
        "next-page": (GObject.SIGNAL_RUN_LAST, GObject.TYPE_NONE, []),
    }

    def __init__(self, model):
        BasePage.__init__(self)

        self.__adapter_info = None
        self.__use_configured = True
        self.__model = model
        self._progressbar = None
        self._progressbar_timer = None
        self.devicesview = None
        self.frame = None

        # Name, Type Name, Type, adapter, frontend, registered
        self.deviceslist = Gtk.ListStore(str, str, int, int, int, bool)

    def show_no_devices(self):
        if self.frame:
            self.frame.hide()

        text = "<big><span weight=\"bold\">%s</span></big>" % _('No devices have been found.')
        text += "\n\n"
        text += _('Either no DVB cards are installed or all cards are busy. In the latter case make sure you close all programs such as video players that access your DVB card.')
        self._label.set_markup (text)
        self._label.show()

    def show_devices(self):
        self._label.hide()

        if self.devicesview == None:
            self.devicesview = Gtk.TreeView.new_with_model(self.deviceslist)
            self.devicesview.get_selection().connect("changed",
                self.on_device_selection_changed)

            cell_name = Gtk.CellRendererText()
            col_name = Gtk.TreeViewColumn(_("Name"))
            col_name.pack_start(cell_name, True)
            col_name.set_cell_data_func(cell_name, self.name_data_func, None)
            self.devicesview.append_column(col_name)

            cell_type = Gtk.CellRendererText()
            col_type = Gtk.TreeViewColumn(_("Type"))
            col_type.pack_start(cell_type, True)
            col_type.add_attribute(cell_type, "text", 1)
            self.devicesview.append_column(col_type)

            scrolledview = Gtk.ScrolledWindow()
            scrolledview.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
            scrolledview.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
            scrolledview.add(self.devicesview)
            scrolledview.show_all()

            text = "<b>%s</b>" % _("Select the device you want to configure.")
            self.frame = BaseFrame(text, scrolledview)
            self.frame.show()
            self.pack_start(self.frame, True, True, 0)

        self.devicesview.grab_focus()

        if len(self.deviceslist) == 1:
            self.emit("next-page")

    def show_all_configured(self):
        if self.frame:
            self.frame.hide()

        text = "<big><span weight=\"bold\">%s</span></big>" % _('All devices are already configured.')
        text += "\n\n"
        text += _('Go to the control center if you want to alter the settings of already configured devices.')
        self._label.set_markup (text)
        self._label.show()

    def show_error(self, error):
        if self.frame:
            self.frame.hide()

        text = "<big><span weight=\"bold\">%s</span></big>" % _('An error occured while retrieving devices.')
        text += "\n\n"
        text += _("Make sure other applications don't access DVB devices and you have permissions to access them.")
        text += "\n\n"
        text += _('The detailed error message is:')
        text += "\n<i>%s</i>" % error
        self._label.set_selectable(True)
        self._label.set_markup (text)
        self._label.show()

    def show_progressbar(self):
        self._label.hide()
        self._progressbar = Gtk.ProgressBar()
        self._progressbar.set_text(_("Searching for devices"))
        self._progressbar.set_fraction(0.1)
        self._progressbar.show()
        self.pack_start(self._progressbar, False, True, 0)
        self._progressbar_timer = GObject.timeout_add(100, self.progressbar_pulse, None)

    def destroy_progressbar(self):
        GObject.source_remove(self._progressbar_timer)
        self._progressbar_timer = None
        self._progressbar.destroy()

    def progressbar_pulse(self, user_data):
        self._progressbar.pulse()
        return True

    def get_page_title(self):
        return _("Device selection")

    def display_configured(self, val):
        self.__use_configured = val

    def get_selected_device(self):
        model, aiter = self.devicesview.get_selection().get_selected()
        if aiter != None:
            return None
        else:
            return model[aiter]

    def get_adapter_info(self):
        if self.__adapter_info == None and len(self.deviceslist) == 1:
            aiter = self.deviceslist.get_iter_first()
            self.__adapter_info = {"name": self.deviceslist[aiter][0],
                                   "type": self.deviceslist[aiter][2],
                                   "adapter": self.deviceslist[aiter][3],
                                   "frontend": self.deviceslist[aiter][4],
                                   "registered": self.deviceslist[aiter][5],}
        return self.__adapter_info

    def run(self):
        """
        Retrieves registered and unregistered devices
        and sets the contents of the page
        """
        def registered_handler(devgroups):
            for group in devgroups:
                for dev in group["devices"]:
                    dev.type_name = DVB_TYPE_TO_DESC[dev.type]
                    dev.registered = True
                    registered.add(dev)
            self.__model.get_all_devices(result_handler=devices_handler)

        def devices_handler(devices):
            error = None
            for dev in devices:
                if dev not in registered:
                    success, info = gnomedvb.get_adapter_info(dev.adapter,
                        dev.frontend)
                    if success:
                        if info["type_t"]:
                            dev_t = copy.copy(dev)
                            dev_t.name = info["name"]
                            dev_t.type = GROUP_TERRESTRIAL
                            if dev_t.type in DVB_TYPE_TO_DESC:
                                dev_t.type_name = DVB_TYPE_TO_DESC[dev_t.type]
                            else:
                                dev_t.type_name = "Unknown"
                            dev_t.registered = False
                            unregistered.add(dev_t)
                        if info["type_s"]:
                            dev_s = copy.copy(dev)
                            dev_s.name = info["name"]
                            dev_s.type = GROUP_SATELLITE
                            if dev_s.type in DVB_TYPE_TO_DESC:
                                dev_s.type_name = DVB_TYPE_TO_DESC[dev_s.type]
                            else:
                                dev_s.type_name = "Unknown"
                            dev_s.registered = False
                            unregistered.add(dev_s)
                        if info["type_c"]:
                            dev_c = copy.copy(dev)
                            dev_c.name = info["name"]
                            dev_c.type = GROUP_CABLE
                            if dev_c.type in DVB_TYPE_TO_DESC:
                                dev_c.type_name = DVB_TYPE_TO_DESC[dev_c.type]
                            else:
                                dev_c.type_name = "Unknown"
                            dev_c.registered = False
                            unregistered.add(dev_c)
                    else:
                        error = info

            all_devs = registered | unregistered
            has_device = len(all_devs) > 0
            if self.__use_configured:
                devs = all_devs
            else:
                devs = unregistered

            self.deviceslist.clear()
            for dev in devs:
                self.deviceslist.append([dev.name, dev.type_name,
                    dev.type, dev.adapter, dev.frontend, dev.registered])

            self.destroy_progressbar()

            if error != None:
                self.show_error(error)
            elif len(devs) == 0:
                if not has_device:
                    self.show_no_devices()
                else:
                    self.show_all_configured()
            else:
                self.show_devices()

        registered = set()
        unregistered = set()
        self.__adapter_info = None
        self.show_progressbar()

        self.__model.get_registered_device_groups(result_handler=registered_handler)

    def on_device_selection_changed(self, treeselection):
        model, aiter = treeselection.get_selected()
        if aiter != None:
            self.__adapter_info = {"name": model[aiter][0],
                                   "type": model[aiter][2],
                                   "adapter": model[aiter][3],
                                   "frontend": model[aiter][4],
                                   "registered": model[aiter][5],}
            self.emit("finished", True)
        else:
            self.emit("finished", False)

    def name_data_func(self, column, cell, model, aiter, user_data):
        name = model[aiter][0]
        adapter = model[aiter][3]
        frontend = model[aiter][4]

        text = _("<b>%s</b>\n") % name
        text += "<small>%s</small>" % (_("Adapter: %d, Frontend: %d") % (adapter, frontend))

        cell.set_property("markup", text)
