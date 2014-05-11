from gnomedvb import _
from gnomedvb import GROUP_TERRESTRIAL
from gnomedvb import GROUP_SATELLITE
from gnomedvb import GROUP_CABLE

DVB_TYPE_TO_DESC = {
    GROUP_CABLE: _("digital cable"),
    GROUP_SATELLITE: _("digital satellite"),
    GROUP_TERRESTRIAL: _("digital terrestrial")
}

DVB_TYPE_TO_TV_DESC = {
    GROUP_CABLE: _("digital cable TV"),
    GROUP_SATELLITE: _("digital satellite TV"),
    GROUP_TERRESTRIAL: _("digital terrestrial TV")
}
