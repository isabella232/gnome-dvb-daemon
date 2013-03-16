/*
 * Copyright (C) 2011 Sebastian Pölsterl
 *
 * This file is part of GNOME DVB Daemon.
 *
 * GNOME DVB Daemon is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * GNOME DVB Daemon is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with GNOME DVB Daemon.  If not, see <http://www.gnu.org/licenses/>.
 */

using GLib;
using Gee;

namespace DVB {

    /**
     * We don't want to hold the complete information about
     * every event in memory. Just remember id and starttime
     * so we can have a sorted list.
     */
    public class EventElement : GLib.Object {

        public uint id;
        /* Time is stored in UTC */
        public time_t starttime;

        public static int compare (EventElement event1, EventElement event2) {
            if (event1 == null && event2 == null) return 0;
            else if (event1 == null && event2 != null) return +1;
            else if (event1 != null && event2 == null) return -1;

            if (event1.starttime < event2.starttime) return -1;
            else if (event1.starttime > event2.starttime) return +1;
            else return 0;
        }

        public static EventElement new_from_event (Event event) {
            EventElement element = new EventElement ();
            element.id = event.id;
            element.starttime = event.get_start_timestamp ();
            return element;
        }
    }

    public class EventStorage : GLib.Object, Traversable<EventElement>, Iterable<EventElement> {

        private Sequence<EventElement> events;
        private Map<uint, unowned SequenceIter<EventElement>> event_id_map;

        // concurrent modification protection
	    private int _stamp = 0;

        public int size {
            get {
                return events.get_length ();
            }
        }

        public Type element_type {
            get {
                return typeof(EventElement);
            }
        }

        public EventStorage () {
            this.events = new Sequence<EventElement> ();
            this.event_id_map = new HashMap<uint, unowned SequenceIter<EventElement>> ();
        }

        public void insert (Event event) {
            EventElement element = EventElement.new_from_event (event);

            SequenceIter<EventElement> iter = this.events.insert_sorted (element, EventElement.compare);
            this.event_id_map.set (event.id, iter);

            _stamp++;

            assert (this.events.get_length () == this.event_id_map.size);
        }

        public void remove_range (int start, int end) {
            assert (start >= 0);
            assert (end < this.events.get_length ());

            SequenceIter<EventElement> begin_iter = this.events.get_iter_at_pos (start);
            SequenceIter<EventElement> end_iter = this.events.get_iter_at_pos (end);

            SequenceIter<EventElement> iter = begin_iter;
            while (iter != end_iter) {
                EventElement element = iter.get();
                this.event_id_map.unset (element.id);

                iter = iter.next ();
            }

            Sequence.remove_range (begin_iter, end_iter);

            _stamp++;

            assert (this.events.get_length () == this.event_id_map.size);
        }

        public void remove_all(Gee.List<Event> events) {
            foreach (Event event in events) {
                SequenceIter<EventElement> iter = this.event_id_map.get (event.id);
                if (iter != null) {
                    Sequence.remove (iter);
                    this.event_id_map.unset (event.id);
                }
            }
            _stamp++;
        }

        public new EventElement get (int index) {
            assert (index < this.events.get_length ());

            SequenceIter<EventElement> iter = this.events.get_iter_at_pos (index);
            EventElement element = iter.get ();

            return element;
        }

        public EventElement get_by_id (uint event_id) {
            SequenceIter<EventElement> iter = this.event_id_map.get (event_id);
            EventElement element = iter.get ();

            return element;
        }

        public bool contains_event_with_id (uint event_id) {
            return this.event_id_map.has_key (event_id);
        }

        public EventElement? next (EventElement element) {
            SequenceIter<EventElement> iter = this.event_id_map.get (element.id);
            assert (iter != null);
            SequenceIter<EventElement> next = iter.next();
            return (next.is_end ()) ? null : next.get();
        }

        public EventElement? prev (EventElement element) {
            SequenceIter<EventElement> iter = this.event_id_map.get (element.id);
            assert (iter != null);
            SequenceIter<EventElement> prev = iter.prev();
            return (prev.is_begin ()) ? null : prev.get();
        }

        public Gee.List<EventElement> get_overlapping_events (Event event) {
            EventElement element = EventElement.new_from_event (event);
            time_t event_end = event.get_end_timestamp ();

            SequenceIter<EventElement> start_iter = this.events.search (element, EventElement.compare).prev ();

            Gee.List<EventElement> overlap = new ArrayList<EventElement> ();

            SequenceIter<EventElement> end_iter = start_iter;
            while (!end_iter.is_end ()) {
                EventElement data = end_iter.get ();
                if (data.starttime > event_end) {
                    break;
                }

                overlap.add (data);

                end_iter = end_iter.next ();
            }

            return overlap;
        }

        public bool foreach (ForallFunc<EventElement> f) {
            Iterator<EventElement> iter = this.iterator();
            return iter.foreach(f);
        }

        public Iterator<EventElement> iterator () {
            return new EventIterator (this);
        }

        public BidirIterator<EventElement> bidir_iterator () {
            return new EventIterator (this);
        }

        private class EventIterator : Object, Traversable<EventElement>, Iterator<EventElement>, BidirIterator<EventElement> {

            private EventStorage _storage;
            private SequenceIter<EventElement> _iter;

            // concurrent modification protection
    		private int _stamp = 0;

            public EventIterator(EventStorage storage) {
                this._storage = storage;
                this._stamp = storage._stamp;
            }

            public bool valid { get { return true; }}
            public bool read_only { get { return true; }}

            public bool next () {
                assert (_stamp == _storage._stamp);
                if (!_iter.is_end ()) {
				    _iter = _iter.next ();
				    return true;
			    }
                return false;
            }

            public bool has_next () {
                assert (_stamp == _storage._stamp);
                return (!_iter.is_end ());
            }

            public bool first () {
                assert (_stamp == _storage._stamp);
                if (_storage.size > 0) {
                    _iter = _storage.events.get_begin_iter ();
                    return true;
                }
                return false;
            }

            public new EventElement get () {
                assert (_stamp == _storage._stamp);
                assert (_iter != null);

                return _iter.get ();
            }

            public void remove () {

            }

            public bool previous () {
                assert (_stamp == _storage._stamp);
                if (!_iter.is_begin ()) {
				    _iter = _iter.prev ();
				    return true;
    			}
                return false;
            }

            public bool has_previous () {
                assert (_stamp == _storage._stamp);
                return (!_iter.is_begin ());
            }

            public bool last () {
                assert (_stamp == _storage._stamp);
                if (_storage.size > 0) {
                    _iter = _storage.events.get_end_iter ();
                    return true;
                }
                return false;
            }

            public bool foreach (ForallFunc<EventElement> f) {
                assert (_stamp == _storage._stamp);
                while (!_iter.is_end ()) {
				    _iter = _iter.next ();
                    if (!f(_iter.get()))
                        return false;
                }
                return true;
            }
        }

    }

}
