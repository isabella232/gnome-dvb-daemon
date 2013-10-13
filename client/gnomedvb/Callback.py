import collections
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

class Callback:

    def __init__(self):
        self.callbacks = []

    def add_callback(self, callback_function, *args):
        if not isinstance(callback_function, collections.Callable):
            raise TypeError("first argument must be callable")
        self.callbacks.append((callback_function, args))

    def callback(self, result):
        for cb, args in self.callbacks:
            cb(result, *args)

