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

PRIME = 31

class Device:

    def __init__(self, group_id, name, adapter, frontend, devtype):
        self.group = group_id
        self.group_name = None
        self.name = name
        self.adapter = adapter
        self.frontend = frontend
        self.type = devtype

    def __hash__(self):
        return PRIME * PRIME * self.type + PRIME * self.adapter + self.frontend

    def __eq__(self, other):
        if not isinstance(other, Device):
            return False

        return (self.adapter == other.adapter \
            and self.frontend == other.frontend \
            and self.type == other.type)

    def __ne__(self, other):
        if not isinstance(other, Device):
            return True

        return (self.adapter != other.adapter \
            or self.frontend != other.frontend \
            or self.type != other.type)

    def __repr__(self):
        return "/dev/dvb/adapter%d/frontend%d/%d" % (self.adapter, self.frontend, self.type)