dnl Checks for gstreamer modules (code from Totem)
dnl AG_GST_CHECK_GST_INSPECT
dnl   check for gst-inspect-1.0
dnl
dnl AG_GST_CHECK_MODULE_BAD([MODULE])
dnl   check for module from gst-plugins-bad

AC_DEFUN([AG_GST_CHECK_GST_INSPECT],
[
	gst010_toolsdir=`$PKG_CONFIG --variable=toolsdir gstreamer-1.0`
	GST_INSPECT="$gst010_toolsdir/gst-inspect-1.0"

	dnl Give error and exit if we don't have the gst_inspect tool
	AC_MSG_CHECKING([GStreamer 1.0 inspection tool])
	if test -r "$GST_INSPECT"; then
		AC_MSG_RESULT([yes])
		AC_SUBST(GST_INSPECT)
	else
		AC_MSG_RESULT([no])
		AC_MSG_ERROR([
Cannot find required GStreamer-1.0 tool 'gst-inspect-1.0'.
It should be part of gstreamer-1_0-utils. Please install it.
		])
	fi
])

AC_DEFUN([AG_GST_CHECK_MODULE_BAD],
[
	base_element="[$1]"
	
    AC_MSG_CHECKING([GStreamer 1.0 $base_element plugin])
	if $GST_INSPECT $base_element >/dev/null 2>/dev/null; then
		AC_MSG_RESULT([yes])
	else
		AC_MSG_RESULT([no])
		AC_MSG_ERROR([
Cannot find required GStreamer-1.0 plugin '$base_element'.
It should be part of gst-plugins-bad. Please install it.
		])
	fi
])

AC_DEFUN([AG_GST_CHECK_MODULE_GOOD],
[
	base_element="[$1]"
	
    AC_MSG_CHECKING([GStreamer 1.0 $base_element plugin])
	if $GST_INSPECT $base_element >/dev/null 2>/dev/null; then
		AC_MSG_RESULT([yes])
	else
		AC_MSG_RESULT([no])
		AC_MSG_ERROR([
Cannot find required GStreamer-1.0 plugin '$base_element'.
It should be part of gst-plugins-good. Please install it.
		])
	fi
])
