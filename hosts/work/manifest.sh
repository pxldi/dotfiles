# The work laptop: Teams, the Microsoft 365 calendar, and the presentation rig.

SCRIPTS=(av av-detect mpris-follow next-event present teams-calendar-sync
         teams-call-watch teams-focus teams-unread clipboard-picker)

PLUGINS=(next-meeting media-controls teams-status posture present)

UNITS=(hotcorner.service mpris-follow.service teams-calendar-http.service
       teams-calendar-sync.service teams-calendar-sync.timer teams-call-watch.service)

ENABLE="teams-calendar-sync.timer teams-calendar-http.service teams-call-watch.service mpris-follow.service hotcorner.service"

extras() {
    link "$REPO/misc/teams-for-linux-config.json" "$CONFIG/teams-for-linux/config.json"
    link "$REPO/misc/teams-calendar.source" "$CONFIG/evolution/sources/teams-calendar.source"
}
