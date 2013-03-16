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

namespace DVB.Logging {

public enum LogLevel {
    LOG,
    DEBUG,
    INFO,
    WARNING,
    ERROR
}

public interface Formatter : GLib.Object {

    public abstract string format (string logger_name, LogLevel level, string format);

}

public interface Handler : GLib.Object {

    public abstract Formatter formatter {get; set;}
    public abstract LogLevel threshold {get; set;}

    public abstract void publish (string logger_name, LogLevel level, string format, va_list args);
    public abstract void close ();

}

public class DefaultFormatter : GLib.Object, Formatter {

    protected virtual string get_level_name (LogLevel level) {
        string lvlstr = null;
        switch (level) {
            case LogLevel.LOG: lvlstr = "LOG"; break;
            case LogLevel.DEBUG: lvlstr = "DEBUG"; break;
            case LogLevel.INFO: lvlstr = "INFO"; break;
            case LogLevel.WARNING: lvlstr = "WARNING"; break;
            case LogLevel.ERROR: lvlstr = "ERROR"; break;
            default: assert_not_reached ();
        }
        return lvlstr;
    }

    public virtual string format (string logger_name, LogLevel level, string format) {
        string lvlstr = this.get_level_name (level);

        string msg = "%-12s %-12s %s\n".printf (logger_name, lvlstr, format);
        return msg;
    }

}

public class ColorFormatter : DefaultFormatter {

    static string[] colormap = new string[] {
      "\033[37m",                   /* LOG */
      "\033[36m",                   /* DEBUG */
      "\033[32;01m",                /* INFO */
      "\033[33;01m",                /* WARNING */
      "\033[31;01m"                 /* ERROR */
    };
    static const string clear = "\033[00m";

    protected override string get_level_name (LogLevel level) {
        string lvlstr = base.get_level_name (level);
        return "%s%s%s".printf (colormap[level], lvlstr, clear);
    }

    public override string format (string logger_name, LogLevel level, string format) {
        string lvlstr = this.get_level_name (level);

        string msg;
        if (level < LogLevel.INFO)
            msg = "%-12s %-20s %s\n".printf (logger_name, lvlstr, format);
        else
            msg = "%-12s %-23s %s\n".printf (logger_name, lvlstr, format);
        return msg;
    }

}

public class ConsoleHandler : GLib.Object, Handler {

    public Formatter formatter {get; set; default = new DefaultFormatter ();}
    public LogLevel threshold {get; set; default = LogLevel.LOG;}

    public void publish (string logger_name, LogLevel level, string format, va_list args) {
        if (level < threshold)
            return;

        string msg = formatter.format (logger_name, level, format);
        if (level > LogLevel.INFO)
            stderr.vprintf (msg, args);
        else
            stdout.vprintf (msg, args);
    }

    public void close () { }

}

public class FileHandler : GLib.Object, Handler {

    public Formatter formatter {get; set; default = new DefaultFormatter ();}
    public LogLevel threshold {get; set; default = LogLevel.LOG;}
    public int limit {get; set; default = 0;}
    public int count {get; set; default = 1;}
    public string pattern {get; construct;}

    private OutputStream os;
    private int file_size;
    private int file_index;

    public FileHandler (string file_pattern) throws Error {
        GLib.Object (pattern: file_pattern);

        this.file_index = 0;
        this.rotate ();
    }

    public void publish (string logger_name, LogLevel level, string format, va_list args) {
        if (level < threshold)
            return;

        string msg = formatter.format (logger_name, level, format);
        string txt = msg.vprintf (args);

        try {
            if (limit > 0) {
                file_size += txt.length;
                if (file_size > limit) {
                    this.rotate ();
                }
            }

            os.write (txt.data);
        } catch (Error e) {
            stderr.printf ("Error in FileHandler.publish: %s\n", e.message);
        }
    }

    public void close () {
        try {
            os.close ();
        } catch (IOError e) {
            stderr.printf ("Error in FileHandler.close: %s\n", e.message);
        }
    }

    private void rotate () throws Error {
        if (this.os != null)
            this.close ();

        File file = this.get_next_file ();

        FileOutputStream fos;
        if (file.query_exists (null)) {
            fos = file.replace (null, false, FileCreateFlags.NONE, null);
        } else {
            fos = file.create (FileCreateFlags.NONE, null);
        }
        this.os = new BufferedOutputStream (fos);
        this.file_size = 0;
    }

    private File get_next_file () {
        if (this.file_index == this.count) {
            this.file_index = 0;
        }

        string filename = this.pattern.printf (this.file_index++);
        return File.new_for_path (filename);
    }

}

public class Logger : GLib.Object {

    public string name {get; set;}
    private Gee.HashSet<Handler> handlers;

    construct {
        this.handlers = new Gee.HashSet<Handler> (
            Gee.Functions.get_hash_func_for(typeof(Handler)),
            Gee.Functions.get_equal_func_for(typeof(Handler)));
    }

    public void addHandler (Handler handler) {
        lock (this.handlers) {
            this.handlers.add (handler);
        }
    }

    public void removeHandler (Handler handler) {
        lock (this.handlers) {
            this.handlers.remove (handler);
        }
    }

    public Gee.HashSet<Handler> getHandlers () {
        return this.handlers;
    }

    private inline void log_full (LogLevel level, string format, va_list args) {
        lock (this.handlers) {
            foreach (Handler handler in this.handlers) {
                var l = args.copy (args);
                handler.publish (this.name, level, format, l);
            }
        }
    }

    [Diagnostics]
    [PrintfFormat]
    public void log (string format, ...) {
        var l = va_list ();
        this.log_full (LogLevel.LOG, format, l);
    }

    [Diagnostics]
    [PrintfFormat]
    public void debug (string format, ...) {
        var l = va_list ();
        this.log_full (LogLevel.DEBUG, format, l);
    }

    [Diagnostics]
    [PrintfFormat]
    public void info (string format, ...) {
        var l = va_list ();
        this.log_full (LogLevel.INFO, format, l);
    }

    [Diagnostics]
    [PrintfFormat]
    public void warning (string format, ...) {
        var l = va_list ();
        this.log_full (LogLevel.WARNING, format, l);
    }

    [Diagnostics]
    [PrintfFormat]
    public void error (string format, ...) {
        var l = va_list ();
        this.log_full (LogLevel.ERROR, format, l);
    }

}

public class LogManager : GLib.Object {

    private static const string DEFAULT_NAME = "default";

    private static LogManager instance;
    private static RecMutex instance_mutex = RecMutex ();

    private Gee.HashMap<string, Logger> loggers;

    construct {
        this.loggers = new Gee.HashMap<string, Logger> (
            Gee.Functions.get_hash_func_for(typeof(string)),
            Gee.Functions.get_equal_func_for(typeof(string)),
            Gee.Functions.get_equal_func_for(typeof(Logger)));
    }

    public static unowned LogManager getLogManager () {
        instance_mutex.lock ();
        if (instance == null) {
            instance = new LogManager ();
        }
        instance_mutex.unlock ();
        return instance;
    }

    public Logger getDefaultLogger () {
        return this.getLogger (DEFAULT_NAME);
    }

    public Logger getLogger (string name) {
        Logger l;
        lock (this.loggers) {
            if (this.loggers.has_key (name)) {
                l = this.loggers.get (name);
            } else {
                l = createLogger (name);
            }
        }
        return l;
    }

    private Logger createLogger (string name) {
        Logger l = new Logger ();
        l.name = name;
        this.loggers.set (name, l);
        return l;
    }

    public void cleanup () {
        lock (this.loggers) {
            foreach (Logger logger in this.loggers.values) {
                foreach (Handler handler in logger.getHandlers ()) {
                    handler.close ();
                }
            }
            this.loggers.clear ();
        }
    }

}

}
