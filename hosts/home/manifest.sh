# The desktop at home: no Teams, no Microsoft 365 calendar, no laptop panel.
#
# Dropped from the work profile and why:
#   teams-*, next-event, next-meeting, teams-status  work accounts only
#   av, av-detect, present, the present plugin       they name the laptop's
#                                                    PCI audio nodes and assume
#                                                    an eDP panel plus a TV
# `posture` stays, with defer_during_meetings off, because it calls next-event.

SCRIPTS=(mpris-follow clipboard-picker)

PLUGINS=(media-controls posture)

UNITS=(hotcorner.service mpris-follow.service)

ENABLE="mpris-follow.service hotcorner.service"

extras() {
    :
}
