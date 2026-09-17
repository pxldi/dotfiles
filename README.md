# dotfiles

A niri + Noctalia desktop on Arch, with a Microsoft 365 calendar that works
without the tenant's blessing.

`./install.sh` symlinks everything into place and prints the services to enable.

## What is here

| Path | What it is |
| --- | --- |
| `niri/` | Compositor config: outputs, keybinds, input, window rules |
| `noctalia/` | Bar layout and settings, plus three local plugins |
| `bin/` | The scripts the bar and keybinds call |
| `systemd/` | User units that keep the above fed |
| `wireplumber/` | Audio device priority rules |
| `misc/` | Portal, Teams, calendar-source and hot-corner config |

## The calendar, and why it is built this way

Work calendars live in Exchange Online, and the obvious clients cannot reach
them here:

- **EWS** is switched off for Exchange Online from 1 October 2026, so
  `evolution-ews` is a dead end.
- **Microsoft Graph** needs OAuth consent, and this tenant requires an admin to
  approve third-party apps. Evolution's client is not approved.
- **Published ICS** works without admin approval, but Microsoft regenerates
  those feeds on a multi-hour cycle - useless for "what am I late for".

What does work: the Teams client is already signed in, and `teams-for-linux`
can answer a `get-calendar` command over MQTT using its own session. So:

    teams-for-linux --(MQTT)--> teams-calendar-sync --> events.json  --> bar widget
                                                    \-> teams.ics    --> localhost:8099 --> evolution-data-server --> GNOME Calendar

`events.json` is read directly by the bar widget; `teams.ics` is served on
loopback so evolution-data-server can subscribe to it like any web calendar.
Both refresh every five minutes.

This depends on Teams being open and logged in. When it is not, the cache goes
stale and both the widget tooltip and the agenda panel say so rather than
showing old data as if it were current.

## Noctalia plugins

| Plugin | What it does |
| --- | --- |
| `next-meeting` | Countdown to the next meeting; click joins it inside the join window, otherwise opens an agenda panel. Notifies a couple of minutes ahead. |
| `media-controls` | Previous / play-pause / next in the bar. The play-pause glyph follows real MPRIS state, fed by `mpris-follow` so nothing is polled. |
| `teams-status` | Teams unread count, read from the tray item's *tooltip* - its icon shows an attention dot with nothing waiting. |

## Scripts

| Script | Purpose |
| --- | --- |
| `teams-calendar-sync` | Ask Teams for the calendar over MQTT, write the cache |
| `next-event` | Read that cache: bar JSON, agenda data, or join the next meeting |
| `teams-call-watch` | Silence notifications and inhibit idle during a call |
| `teams-unread` / `teams-focus` | Unread count, and raise the Teams window |
| `mpris-follow` | Stream playback state to a file so the bar never polls |
| `present` | Presentation mode: move to the external screen, fullscreen, hide the bar, DND, room audio |
| `av` / `av-detect` | Switch the audio/video rig; detect which display and sink are attached |

## Things worth knowing

- **niri window rules are applied when a window maps.** Single-instance apps
  reuse an existing window, so a rule change appears not to work until the app
  is actually quit.
- **`os.getenv` does not exist in the Noctalia plugin sandbox.** Absolute paths
  come from `noctalia.pluginDataDir()`.
- **`noctalia.runAsync` kills its child when the timeout expires**, which takes
  a GUI app down with it. Anything long-lived is launched with `setsid ... &`.
- **Notifications:** dunst is masked so Noctalia can own
  `org.freedesktop.Notifications`; only one process can.

## Requirements

    niri noctalia mosquitto teams-for-linux playerctl gnome-calendar
    evolution-data-server wl-mirror grim slurp

`mosquitto` needs a local listener - `listener 1883 localhost` and
`allow_anonymous true` - and `teams-for-linux` needs `graphApi.enabled` plus
MQTT with a `commandTopic` set, as in `misc/teams-for-linux-config.json`.
