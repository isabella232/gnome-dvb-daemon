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
from gi.repository import Gtk
from gnomedvb import _
import datetime
import gnomedvb
from gnomedvb import global_error_handler
from gnomedvb.ui.timers.MessageDialogs import TimerFailureDialog
from gnomedvb.ui.timers.TimerDialog import TimerDialog
from gnomedvb.ui.widgets.CellRendererDatetime import CellRendererDatetime

class EditTimersDialog(Gtk.Dialog):

    (COL_ID,
    COL_CHANNEL,
    COL_TITLE,
    COL_START,
    COL_DURATION,
    COL_ACTIVE,) = list(range(6))

    def __init__(self, device_group, parent=None):
        """
        @param device_group: ID of device group
        @type device_group: int
        @param parent: Parent window
        @type parent: Gtk.Window
        """
        Gtk.Dialog.__init__(self, title=_("Recording schedule"),
            parent=parent)

        self.recorder = None

        self.set_modal(True)
        self.set_destroy_with_parent(True)
        self.device_group = device_group
        self.set_recorder(device_group)

        close_button = self.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        close_button.grab_default()

        self.set_default_size(550, 400)
        self.set_border_width(5)

        self.main_box = Gtk.Box(spacing=12)
        self.main_box.set_border_width(5)
        self.main_box.show()
        self.get_content_area().pack_start(self.main_box, True, True, 0)

        self.timerslist = Gtk.ListStore(int, str, str, GObject.TYPE_PYOBJECT, int, bool)
        self.timerslist.set_sort_func(self.COL_START,
            self._datetime_sort_func)

        self.timersview = Gtk.TreeView.new_with_model(self.timerslist)
        self.timersview.get_selection().connect("changed",
            self._on_timers_selection_changed)

        col_channel = Gtk.TreeViewColumn(_("Channel"))
        cell_rec = Gtk.CellRendererPixbuf()
        col_channel.pack_start(cell_rec, True)
        col_channel.set_cell_data_func(cell_rec, self._get_recording_icon_for_cell, None)
        col_channel.add_attribute(cell_rec, "stock-id", self.COL_ACTIVE)
        cell_channel = Gtk.CellRendererText()
        col_channel.pack_start(cell_channel, True)
        col_channel.add_attribute(cell_channel, "text", self.COL_CHANNEL)

        self.timersview.append_column(col_channel)

        col_title = Gtk.TreeViewColumn(_("Title"))
        cell_title = Gtk.CellRendererText()
        col_title.pack_start(cell_title, True)
        col_title.add_attribute(cell_title, "text", self.COL_TITLE)

        self.timersview.append_column(col_title)

        cell_starttime = CellRendererDatetime()
        col_starttime = Gtk.TreeViewColumn(_("Start time"))
        col_starttime.pack_start(cell_starttime, True)
        col_starttime.add_attribute(cell_starttime, "datetime", self.COL_START)

        self.timersview.append_column(col_starttime)

        cell_duration = Gtk.CellRendererText()
        col_duration = Gtk.TreeViewColumn(_("Duration"))
        col_duration.pack_start(cell_duration, False)
        col_duration.set_cell_data_func(cell_duration, self._get_duration_data, None)

        self.timersview.append_column(col_duration)

        self.scrolledwindow = Gtk.ScrolledWindow()
        self.scrolledwindow.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.scrolledwindow.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
        self.scrolledwindow.add(self.timersview)
        self.main_box.pack_start(self.scrolledwindow, True, True, 0)

        self.buttonbox = Gtk.ButtonBox(orientation=Gtk.Orientation.VERTICAL)
        self.buttonbox.set_spacing(6)
        self.buttonbox.set_layout(Gtk.ButtonBoxStyle.START)
        self.button_add = Gtk.Button(stock=Gtk.STOCK_ADD)
        self.button_add.connect("clicked", self._on_button_add_clicked)
        self.buttonbox.pack_start(self.button_add, True, True, 0)

        self.button_delete = Gtk.Button(stock=Gtk.STOCK_DELETE)
        self.button_delete.connect("clicked", self._on_button_delete_clicked)
        self.button_delete.set_sensitive(False)
        self.buttonbox.pack_start(self.button_delete, True, True, 0)

        self.button_edit = Gtk.Button(stock=Gtk.STOCK_EDIT)
        self.button_edit.connect("clicked", self._on_button_edit_clicked)
        self.button_edit.set_sensitive(False)
        self.buttonbox.pack_start(self.button_edit, True, True, 0)

        self.main_box.pack_start(self.buttonbox, False, False, 0)

        self.get_timers()

        self.show_all()

    def set_recorder(self, dev_group):
        self.recorder = dev_group.get_recorder()
        self.recorder.connect("changed", self._on_recorder_changed)
        self.recorder.connect("recording-started", self._set_recording_state, True)
        self.recorder.connect("recording-finished", self._set_recording_state, False)

    def get_timers(self):
        def add_timer(proxy, timers, user_data):
            for timer_id in timers:
                self._add_timer(timer_id)
        self.recorder.get_timers(result_handler=add_timer, error_handler=global_error_handler)

    def _add_timer(self, timer_id):
        start_list, success = self.recorder.get_start_time(timer_id)
        if success:
            starttime = datetime.datetime(*start_list)
            (duration, active, channel, title) = self.recorder.get_all_informations(timer_id)[0][1:]

            self.timerslist.append([int(timer_id), channel, title, starttime, duration, bool(active)])

    def _remove_timer(self, timer_id):
        for row in self.timerslist:
            if row[self.COL_ID] == timer_id:
                self.timerslist.remove(row.iter)

    def _on_button_delete_clicked(self, button):
        def delete_timer_callback(proxy, success, user_data):
            if not success:
                error_dialog = Gtk.MessageDialog(parent=self,
                    flags=Gtk.DialogFlags.MODAL|Gtk.DialogFlags.DESTROY_WITH_PARENT,
                    type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.OK)
                error_dialog.set_markup(
                    "<big><span weight=\"bold\">%s</span></big>" % _("Timer could not be deleted"))
                error_dialog.run()
                error_dialog.destroy()

        model, aiter = self.timersview.get_selection().get_selected()
        if aiter != None:
            timer_id = model[aiter][self.COL_ID]
            if self.recorder.is_timer_active(timer_id):
                dialog = Gtk.MessageDialog(parent=self,
                    flags=Gtk.DialogFlags.MODAL|Gtk.DialogFlags.DESTROY_WITH_PARENT,
                    type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.YES_NO)
                dialog.set_markup(
                    "<big><span weight=\"bold\">%s</span></big>" % _("Abort active recording?"))
                dialog.format_secondary_text(
                    _("The timer you selected belongs to a currently active recording.") + " " +
                    _("Deleting this timer will abort the recording."))
                response = dialog.run()
                dialog.destroy()
                if response == Gtk.ResponseType.YES:
                    self.recorder.delete_timer(timer_id,
                        result_handler=delete_timer_callback,
                        error_handler=global_error_handler)
            else:
                self.recorder.delete_timer(timer_id,
                    result_handler=delete_timer_callback,
                    error_handler=global_error_handler)

    def _on_button_add_clicked(self, button):
        def add_timer_callback(proxy, data, user_data):
            rec_id, success = data
            if not success:
                err_dialog = TimerFailureDialog(self)
                err_dialog.run()
                err_dialog.destroy()

        dialog = TimerDialog(self, self.device_group)
        response_id = dialog.run()
        if response_id == Gtk.ResponseType.ACCEPT:
            duration = dialog.get_duration()
            start = dialog.get_start_time()
            channel = dialog.get_channel()

            self.recorder.add_timer (channel, start[0],
                start[1], start[2], start[3], start[4], duration,
                result_handler=add_timer_callback,
                error_handler=global_error_handler)

        dialog.destroy()

    def _on_button_edit_clicked(self, button):
        model, aiter = self.timersview.get_selection().get_selected()
        if aiter != None:
            start = model[aiter][self.COL_START]
            duration = model[aiter][self.COL_DURATION]
            channel = model[aiter][self.COL_CHANNEL]

            dialog = TimerDialog(self, self.device_group, channel=channel,
                starttime=start, duration=duration)
            dialog.set_time_and_date_editable(
                not model[aiter][self.COL_ACTIVE])
            response_id = dialog.run()
            if response_id == Gtk.ResponseType.ACCEPT:
                timer_id = model[aiter][self.COL_ID]
                new_duration = dialog.get_duration()
                new_start = dialog.get_start_time()
                self.recorder.set_start_time(timer_id, new_start[0],
                    new_start[1], new_start[2], new_start[3], new_start[4])
                self.recorder.set_duration(timer_id, new_duration)
            dialog.destroy()

    def _on_recorder_changed(self, recorder, timer_id, typeid):
        if recorder == self.recorder:
            if (typeid == 0):
                # Timer added
                self._add_timer(timer_id)
            elif (typeid == 1):
                # Timer deleted
                self._remove_timer(timer_id)
            elif (typeid == 2):
                # Timer changed
                self._remove_timer(timer_id)
                self._add_timer(timer_id)

    def _on_timers_selection_changed(self, treeselection):
        model, aiter = treeselection.get_selected()
        if aiter == None:
            self.button_delete.set_sensitive(False)
            self.button_edit.set_sensitive(False)
        else:
            self.button_delete.set_sensitive(True)
            self.button_edit.set_sensitive(True)

    def _set_recording_state(self, recorder, timer_id, state):
        for row in self.timerslist:
            if row[self.COL_ID] == timer_id:
                self.timerslist[row.iter][self.COL_ACTIVE] = bool(state)

    def _get_recording_icon_for_cell(self, column, cell, model, aiter, user_data):
        if model[aiter][self.COL_ACTIVE]:
            cell.set_property("stock-id", Gtk.STOCK_MEDIA_RECORD)

    def _get_duration_data(self, column, cell, model, aiter, user_data):
        # We have minutes but need seconds
        duration = model[aiter][self.COL_DURATION] * 60
        duration_str = gnomedvb.seconds_to_time_duration_string(duration)
        cell.set_property("text", duration_str)

    def _datetime_sort_func(self, treemodel, iter1, iter2):
        d1 = treemodel[iter1][self.COL_START]
        d2 = treemodel[iter2][self.COL_START]
        return cmp(d1, d2)

