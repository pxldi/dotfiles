# dotfiles

A niri + Noctalia desktop on Arch, on two machines, with a Microsoft 365
calendar on the work one that works without the tenant's blessing.

`./install.sh <profile>` symlinks everything into place and prints the services
to enable. The profiles are `work` and `home`.

## What is here

| Path | What it is |
| --- | --- |
| `niri/` | Compositor config: keybinds, input, layout, animation, window rules |
| `noctalia/` | The five local plugins, and the shell config |
| `bin/` | The scripts the bar and keybinds call |
| `systemd/` | User units that keep the above fed |
| `wireplumber/` | Audio device priority rules |
| `misc/` | Portal, idle, Teams, calendar-source and hot-corner config |
| `hosts/<profile>/` | Everything that differs between the two machines |

## Profiles

Four things cannot be shared between a laptop with a TV attached and a desktop
with two identical panels: the outputs, which workspace opens on which output,
what starts up, and what sits in the bar. Those live in
`hosts/<profile>/`, and `install.sh` links them into the same destinations as
the shared files, so `config.kdl` does not change between machines.

`hosts/<profile>/manifest.sh` also decides which scripts, plugins and units get
linked at all. That is what keeps the Teams machinery off the home desktop.

| | `work` | `home` |
| --- | --- | --- |
| Outputs | eDP-1 laptop panel, DP-2 TV | DP-2 and DP-3, two 1440p panels |
| Bar | next meeting, Teams unread, present, posture, media | posture, media |
| Startup | browser, shells, VeraCrypt, Teams, music | browser, shells, music |
| Teams and the M365 calendar | yes | no |
| Presentation rig (`present`, `av`) | yes | no |

`posture` is on both. On `home` its `defer_during_meetings` is off, because
the meeting it would defer for is read by `next-event`, which is work-only.

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
| `posture` | Sit/stand timer in the bar: alternates on a schedule, one nudge per switch, defers while a meeting is running, tracks today's standing time. |
| `present` | Presentation state: shows whether an external screen is attached and whether you are live. Click presents, right-click mirrors (drives `bin/present`). |

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
| `clipboard-picker` | Pick an entry out of the cliphist history (Mod+V) |

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

Both profiles:

    niri noctalia quickshell xwayland-satellite ghostty fuzzel hypridle
    cliphist wl-clipboard playerctl easyeffects polkit-gnome flameshot
    nautilus grim slurp bibata-cursor-theme

The portal set `misc/niri-portals.conf` names:

    xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr gnome-keyring

The `work` profile adds:

    mosquitto teams-for-linux gnome-calendar evolution-data-server wl-mirror
    veracrypt

`mosquitto` needs a local listener - `listener 1883 localhost` and
`allow_anonymous true` - and `teams-for-linux` needs `graphApi.enabled` plus
MQTT with a `commandTopic` set, as in `misc/teams-for-linux-config.json`.

The bar also loads five plugins that are not in this repo. Install them from
Noctalia's plugin browser: `noctalia/wallhaven`, `felipeartur/ai-usagebar`,
`yuuto/arch-updater`, `dotnetrob/cat`, `kenn/keybind-cheatsheet`.
