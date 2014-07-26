AC_PREREQ(2.63.2)
AC_INIT([gnome-dvb-daemon], [0.2.90],
       [https://bugzilla.gnome.org/browse.cgi?product=dvb-daemon],
       [gnome-dvb-daemon],
       [http://live.gnome.org/DVBDaemon])
AC_CONFIG_SRCDIR([Makefile.am])
AC_CONFIG_HEADERS(config.h)
AC_CONFIG_MACRO_DIR([m4])
AM_INIT_AUTOMAKE([1.11 subdir-objects dist-xz no-dist-gzip])
AM_MAINTAINER_MODE([enable])
m4_ifdef([AM_SILENT_RULES],[AM_SILENT_RULES([yes])])

AC_PROG_CC
AM_PROG_CC_C_O

LT_PREREQ([2.2.6])
LT_INIT([disable-static])

AM_PROG_VALAC([0.25.1])

AC_SUBST(CFLAGS)
AC_SUBST(CPPFLAGS)
AC_SUBST(LDFLAGS)

dnl *********************
dnl * i18n
dnl *********************
IT_PROG_INTLTOOL([0.40.0])

AC_SUBST([GETTEXT_PACKAGE], [gnome-dvb-daemon])
AC_DEFINE([GETTEXT_PACKAGE], [PACKAGE_TARNAME], [Define to the gettext package name])

AC_SUBST([CONFIG_STATUS_DEPENDENCIES], ['$(top_srcdir)/po/LINGUAS'])

dnl *********************
dnl * time.h and timegm
dnl *********************
AC_CHECK_HEADERS([time.h], have_time=yes, have_time=no)
if test "x$have_time" = "xno"; then
	AC_MSG_ERROR([Could not find time.h])
fi

AC_CHECK_FUNC([timegm], have_timegm=yes, have_timegm=no)
if test "x$have_timegm" = "xno"; then
	AC_MSG_ERROR([Could not find timegm function])
fi

dnl ***********
dnl * signal.h
dnl ***********
AC_CHECK_HEADERS([signal.h], have_signal=yes, have_signal=no)
if test "x$have_signal" = "xno"; then
	AC_MSG_ERROR([Could not find signal.h])
fi

dnl ******************
dnl * Check for libs
dnl ******************
GLIB_REQUIRED=2.32.0
GST_REQUIRED=1.4.0
GEE_REQUIRED=0.8.0
SQLITE_REQUIRED=3.4
GST_RTSP_SERVER_REQUIRED=1.4.0
GST_MPEGTS_REQUIRED=1.4.0

PKG_CHECK_MODULES(GST, gstreamer-1.0 >= $GST_REQUIRED
                       gstreamer-rtsp-1.0 >= $GST_REQUIRED)
AC_SUBST(GST_CFLAGS)
AC_SUBST(GST_LIBS)

PKG_CHECK_MODULES(GNOME_DVB_DAEMON, glib-2.0 >= $GLIB_REQUIRED
                            gio-2.0 >= $GLIB_REQUIRED
                            gobject-2.0 >= $GLIB_REQUIRED
                            gee-0.8 >= $GEE_REQUIRED
                            sqlite3 >= $SQLITE_REQUIRED
                            gstreamer-rtsp-server-1.0 >= $GST_RTSP_SERVER_REQUIRED
                            gstreamer-mpegts-1.0 >= $GST_MPEGTS_REQUIRED)
AC_SUBST(GNOME_DVB_DAEMON_CFLAGS)
AC_SUBST(GNOME_DVB_DAEMON_LIBS)

PKG_CHECK_MODULES(GLIB, glib-2.0 >= $GLIB_REQUIRED)
AC_SUBST(GLIB_CFLAGS)
AC_SUBST(GLIB_LIBS)

PKG_CHECK_MODULES(GUDEV, gudev-1.0)
AC_SUBST(GUDEV_CFLAGS)
AC_SUBST(GUDEV_LIBS)

AG_GST_CHECK_GST_INSPECT
AG_GST_CHECK_MODULE_BAD([tsparse])
AG_GST_CHECK_MODULE_BAD([dvbbasebin])
AG_GST_CHECK_MODULE_BAD([dvbsrc])
AG_GST_CHECK_MODULE_GOOD([rtpmp2tpay])

dnl ****************
dnl * Totem plugin
dnl ****************
AC_ARG_ENABLE([totem-plugin],
	AS_HELP_STRING([--enable-totem-plugin], [Install the Totem plugin (default: no)]),
	[enable_totem=$enableval],
	[enable_totem=no])

AM_CONDITIONAL(ENABLE_TOTEM, test "x$enable_totem" = "xyes")

AC_ARG_WITH([totem-plugin-dir],
	AS_HELP_STRING([--with-totem-plugin-dir],
		[Directory where Totem plugins are installed (default: LIBDIR/totem/plugins)]))

if test "x$enable_totem" = "xyes"; then
	if test "x$with_totem_plugin_dir" = "x"; then
		TOTEM_PLUGIN_DIR=`$PKG_CONFIG --variable=pluginsdir totem`
		if test "x$TOTEM_PLUGIN_DIR" = "x"; then
			AC_MSG_ERROR(
			[

	*** Could not determinate totem plugin directory.

	Please make sure totem is installed or set the directory
	manually using --with-totem-plugin-dir
			])
		fi
	else
		TOTEM_PLUGIN_DIR="$with_totem_plugin_dir"
	fi
fi
AC_SUBST(TOTEM_PLUGIN_DIR)

dnl **********
dnl * Python
dnl **********
PYTHON_REQUIRED=2.5
AM_PATH_PYTHON($PYTHON_REQUIRED)
AM_CHECK_PYTHON_HEADERS(,[AC_MSG_ERROR(could not find Python headers)])
AC_SUBST(PYTHONDIR)

PYGOBJECT_REQUIRED=3.2.1
PKG_CHECK_MODULES(PYGOBJECT, pygobject-3.0 >= $PYGOBJECT_REQUIRED)

dnl ******************
dnl * Python modules
dnl *****************
AM_CHECK_PYMOD(gi.repository)

AC_CONFIG_FILES([
	Makefile
	client/Makefile
	client/gnomedvb/defs.py
	client/gnomedvb/Makefile
	client/totem-plugin/Makefile
	data/Makefile
	data/gnome-dvb-control.desktop.in
	data/gnome-dvb-setup.desktop.in
	data/icons/Makefile
	po/Makefile.in])

AC_OUTPUT

echo "
$PACKAGE_NAME $PACKAGE_VERSION

    Install Prefix:               ${prefix}
    Python dir:                   ${pythondir}
    Build Totem plugin            ${enable_totem}
"
