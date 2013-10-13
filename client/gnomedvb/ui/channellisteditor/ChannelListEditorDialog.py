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

import gnomedvb
from gi.repository import GObject
from gi.repository import Gtk
from gnomedvb import _
from gnomedvb.ui.widgets.ChannelsStore import ChannelsStore
from gnomedvb.ui.widgets.ChannelsView import ChannelsView
from gnomedvb.ui.widgets.ChannelGroupsStore import ChannelGroupsStore
from gnomedvb.ui.widgets.ChannelGroupsView import ChannelGroupsView
from gnomedvb.ui.widgets.Frame import Frame, BaseFrame
from gnomedvb.ui.widgets.HelpBox import HelpBox

class ChannelListEditorDialog(Gtk.Dialog):

    def __init__(self, model, parent=None):
        Gtk.Dialog.__init__(self, title=_("Edit Channel Lists"),
            parent=parent)

        self.set_modal(True)
        self.set_destroy_with_parent(True)
        self.model = model
        self.devgroup = None
        self.channel_list = None

        self.set_default_size(600, 500)
        self.set_border_width(5)

        close_button = self.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        close_button.grab_default()

        self.vbox_main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.vbox_main.set_border_width(5)
        self.get_content_area().pack_start(self.vbox_main, True, True, 0)

        # channel groups
        groups_box = Gtk.Box(spacing=6)
        groups_frame = BaseFrame("<b>%s</b>" % _("Channel groups"),
            groups_box)
        self.vbox_main.pack_start(groups_frame, False, True, 0)

        self.channel_groups = ChannelGroupsStore()
        self.channel_groups_view = ChannelGroupsView(self.channel_groups)
        self.channel_groups_view.set_headers_visible(False)
        self.channel_groups_view.get_selection().connect("changed",
            self.on_group_changed)
        self.channel_groups_view.get_renderer().connect("edited",
            self.on_channel_group_edited)

        scrolledgroups = Gtk.ScrolledWindow()
        scrolledgroups.add(self.channel_groups_view)
        scrolledgroups.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolledgroups.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
        groups_box.pack_start(scrolledgroups, True, True, 0)

        groups_buttonbox = Gtk.ButtonBox(orientation=Gtk.Orientation.VERTICAL)
        groups_buttonbox.set_spacing(6)
        groups_buttonbox.set_layout(Gtk.ButtonBoxStyle.START)
        groups_box.pack_end(groups_buttonbox, False, False, 0)

        new_group_button = Gtk.Button(stock=Gtk.STOCK_ADD)
        new_group_button.connect("clicked", self.on_new_group_clicked)
        groups_buttonbox.pack_start(new_group_button, True, True, 0)

        self.del_group_button = Gtk.Button(stock=Gtk.STOCK_REMOVE)
        self.del_group_button.connect("clicked", self.on_delete_group_clicked)
        groups_buttonbox.pack_start(self.del_group_button, True, True, 0)

        # device groups
        self.devgroupslist = Gtk.ListStore(str, int, GObject.GObject)

        self.devgroupscombo = Gtk.ComboBox.new_with_model_and_entry(self.devgroupslist)
        self.devgroupscombo.connect("changed", self.on_devgroupscombo_changed)
        cell_adapter = Gtk.CellRendererText()
        self.devgroupscombo.pack_start(cell_adapter, True)
        self.devgroupscombo.set_entry_text_column(0)

        groups_label = Gtk.Label()
        groups_label.set_markup_with_mnemonic(_("_Group:"))
        groups_label.set_mnemonic_widget(self.devgroupscombo)

        groups_box = Gtk.Box(spacing=6)
        groups_box.pack_start(groups_label, False, True, 0)
        groups_box.pack_start(self.devgroupscombo, True, True, 0)

        self.devgroups_frame = BaseFrame("<b>%s</b>" % _("Device groups"),
            groups_box, False, False)
        self.vbox_main.pack_start(self.devgroups_frame, False, True, 0)

        # channels
        channels_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.vbox_main.pack_start(channels_box, True, True, 0)

        cbox = Gtk.Box(spacing=6)
        channels_box.pack_start(cbox, True, True, 0)

        # all channels
        self.channels_store = None
        self.channels_view = ChannelsView(self.channels_store)
        self.channels_view.set_headers_visible(False)
        self.channels_view.connect("row-activated",
            self.on_channels_view_activated)
        treesel = self.channels_view.get_selection()
        treesel.set_mode(Gtk.SelectionMode.MULTIPLE)
        treesel.connect("changed",
            self.on_channel_store_selected)

        left_frame = Frame("<b>%s</b>" % _("All channels"), self.channels_view)
        cbox.pack_start(left_frame, True, True, 0)

        # selected channels
        self.selected_channels_store = Gtk.ListStore(str, int) # Name, sid
        self.selected_channels_view = Gtk.TreeView.new_with_model(self.selected_channels_store)
        self.selected_channels_view.set_reorderable(True)
        self.selected_channels_view.set_headers_visible(False)
        self.selected_channels_view.connect("row-activated",
            self.on_selected_channels_view_activated)
        treesel = self.selected_channels_view.get_selection()
        treesel.connect("changed",
            self.on_selected_channels_changed)
        treesel.set_mode(Gtk.SelectionMode.MULTIPLE)
        col_name = Gtk.TreeViewColumn(_("Channel"))
        cell_name = Gtk.CellRendererText()
        col_name.pack_start(cell_name, True)
        col_name.add_attribute(cell_name, "markup", 0)
        self.selected_channels_view.append_column(col_name)
        self.selected_channels_view.show()

        self.scrolled_selected_channels = Gtk.ScrolledWindow()
        self.scrolled_selected_channels.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
        self.scrolled_selected_channels.set_policy(Gtk.PolicyType.AUTOMATIC,
            Gtk.PolicyType.AUTOMATIC)
        self.scrolled_selected_channels.add(self.selected_channels_view)

        self.select_group_helpbox = HelpBox()
        self.select_group_helpbox.set_markup(_("Choose a channel group"))
        self.right_frame = BaseFrame("<b>%s</b>" % _("Channels of group"),
            self.select_group_helpbox)
        cbox.pack_start(self.right_frame, True, True, 0)

        buttonbox = Gtk.ButtonBox()
        buttonbox.set_spacing(6)
        buttonbox.set_layout(Gtk.ButtonBoxStyle.SPREAD)
        self.add_channel_button = Gtk.Button(stock=Gtk.STOCK_ADD)
        self.add_channel_button.connect("clicked", self.on_add_channel_clicked)
        buttonbox.pack_start(self.add_channel_button, True, True, 0)
        self.remove_channel_button = Gtk.Button(stock=Gtk.STOCK_REMOVE)
        self.remove_channel_button.connect("clicked", self.on_remove_channel_clicked)
        buttonbox.pack_start(self.remove_channel_button, True, True, 0)
        channels_box.pack_start(buttonbox, False, False, 0)

        self.del_group_button.set_sensitive(False)
        self.add_channel_button.set_sensitive(False)
        self.remove_channel_button.set_sensitive(False)

        self.fill_device_groups()
        self.fill_channel_groups()

        self.show_all()

    def fill_channel_groups(self):
        def add_groups(proxy, groups, user_data):
            for gid, name in groups:
                self.channel_groups.append([gid, name, False]) # not editable

        self.model.get_channel_groups(result_handler=add_groups,
            error_handler=gnomedvb.global_error_handler)

    def fill_device_groups(self):
        def append_groups(groups):
            for group in groups:
                self.devgroupslist.append([group["name"], group["id"], group])
            if len(groups) == 1:
                self.devgroup = groups[0]
                self.devgroups_frame.hide()
            else:
                self.devgroups_frame.show()
            self.devgroupscombo.set_active(0)

        self.model.get_registered_device_groups(result_handler=append_groups,
            error_handler=gnomedvb.global_error_handler)

    def refill_channel_groups(self):
        self.channel_groups.clear()
        self.fill_channel_groups()

    def fill_group_members(self):
        def add_channels(proxy, data, user_data):
            channels, success = data
            if success:
                for channel_id in channels:
                    name, success = self.channel_list.get_channel_name(channel_id)
                    if success:
                        self.selected_channels_store.append([name, channel_id])

        self.selected_channels_store.clear()
        data = self.get_selected_channel_group()
        if data:
            group_id, group_name = data
            self.channel_list.get_channels_of_group(group_id,
                result_handler=add_channels,
                error_handler=gnomedvb.global_error_handler)

    def get_selected_channels_all(self):
        sel = self.channels_view.get_selection()
        model, paths = sel.get_selected_rows()
        return [model[path][ChannelsStore.COL_SID] for path in paths]

    def get_selected_channels_selected_group(self):
        sel = self.selected_channels_view.get_selection()
        model, paths = sel.get_selected_rows()
        return [model[path][1] for path in paths]

    def get_selected_channel_group(self):
        model, aiter = self.channel_groups_view.get_selection().get_selected()
        if aiter == None:
            return None
        else:
            return self.channel_groups[aiter][0], self.channel_groups[aiter][1]

    def on_new_group_clicked(self, button):
        aiter = self.channel_groups.append()
        self.channel_groups.set_value(aiter, self.channel_groups.COL_EDITABLE,
            True)
        self.channel_groups_view.grab_focus()
        path = self.channel_groups.get_path(aiter)
        self.channel_groups_view.set_cursor(path,
            self.channel_groups_view.get_column(0), True)
        self.channel_groups_view.scroll_to_cell(path)

    def on_add_channel_group_finished(self, proxy, data, user_data):
        group_id, success = data
        if success:
            self.refill_channel_groups()
        else:
            error_dialog = Gtk.MessageDialog(parent=self,
                flags=Gtk.DialogFlags.MODAL|Gtk.DialogFlags.DESTROY_WITH_PARENT,
                type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.OK)
            error_dialog.set_markup(
                "<big><span weight=\"bold\">%s</span></big>" % _("An error occured while adding the group"))
            error_dialog.run()
            error_dialog.destroy()

    def on_delete_group_clicked(self, button):
        dialog = Gtk.MessageDialog(parent=self,
            flags=Gtk.DialogFlags.MODAL|Gtk.DialogFlags.DESTROY_WITH_PARENT,
            type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.YES_NO)
        group_id, group_name = self.get_selected_channel_group()
        msg = _("Are you sure you want to delete the group '%s'?") % group_name
        dialog.set_markup (
            "<big><span weight=\"bold\">%s</span></big>\n\n%s" %
            (msg, _("All assignments to this group will be lost.")))
        if dialog.run() == Gtk.ResponseType.YES:
            self.model.remove_channel_group(group_id,
                result_handler=self.on_remove_channel_group_finished,
                error_handler=gnomedvb.global_error_handler)
        dialog.destroy()

    def on_remove_channel_group_finished(self, proxy, success, user_data):
        if success:
            self.refill_channel_groups()
        else:
            error_dialog = Gtk.MessageDialog(parent=self,
                flags=Gtk.DialogFlags.MODAL|Gtk.DialogFlags.DESTROY_WITH_PARENT,
                type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.OK)
            error_dialog.set_markup(
                "<big><span weight=\"bold\">%s</span></big>" % _("An error occured while removing the group"))
            error_dialog.run()
            error_dialog.destroy()

    def on_add_channel_clicked(self, button):
        channel_ids = self.get_selected_channels_all()
        group_data = self.get_selected_channel_group()
        if group_data:
            for channel_id in channel_ids:
                self.channel_list.add_channel_to_group(channel_id, group_data[0])
            self.fill_group_members()

    def on_remove_channel_clicked(self, button):
        channel_ids = self.get_selected_channels_selected_group()
        group_data = self.get_selected_channel_group()
        if group_data:
            for channel_id in channel_ids:
                self.channel_list.remove_channel_from_group(channel_id, group_data[0])
            self.fill_group_members()

    def on_channel_store_selected(self, treeselection):
        model, paths = treeselection.get_selected_rows()
        val = (len(paths) > 0 and self.get_selected_channel_group() != None)
        self.add_channel_button.set_sensitive(val)

    def on_selected_channels_changed(self, treeselection):
        model, paths = treeselection.get_selected_rows()
        val = (len(paths) > 0)
        self.remove_channel_button.set_sensitive(val)

    def on_group_changed(self, treeselection):
        model, aiter = treeselection.get_selected()
        val = aiter != None
        self.del_group_button.set_sensitive(val)
        if val:
            self.fill_group_members()
            self.right_frame.set_aligned_child(self.scrolled_selected_channels)
        else:
            self.right_frame.set_aligned_child(self.select_group_helpbox)
            self.selected_channels_store.clear()

    def on_channel_group_edited(self, renderer, path, new_text):
        aiter = self.channel_groups.get_iter(path)
        if len(new_text) == 0:
            self.channel_groups.remove(aiter)
        else:
            self.model.add_channel_group(new_text,
                result_handler=self.on_add_channel_group_finished,
                error_handler=gnomedvb.global_error_handler)

    def get_selected_group(self):
        if self.devgroup != None:
            return self.devgroup
        aiter = self.devgroupscombo.get_active_iter()
        if aiter == None:
            return None
        else:
            return self.devgroupslist[aiter][2]

    def on_devgroupscombo_changed(self, combo):
        group = self.get_selected_group()
        if group != None:
            self.channel_list = group.get_channel_list()
            self.channels_store = ChannelsStore(group)
            self.channels_view.set_model(self.channels_store)

    def on_channels_view_activated(self, treeview, aiter, path):
        self.on_add_channel_clicked(None)

    def on_selected_channels_view_activated(self, treeview, aiter, path):
        self.on_remove_channel_clicked(None)

