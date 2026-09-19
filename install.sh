#!/usr/bin/env bash
# Link this repo's files into place.
#
# Symlinks rather than copies, so editing the live config edits the repo and
# `git diff` shows what has drifted. Anything already present is backed up
# with a .bak suffix rather than overwritten.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"

link() {
    local src="$1" dest="$2"
    [ -e "$src" ] || return 0
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        mv "$dest" "$dest.bak"
        echo "  backed up existing $dest -> $dest.bak"
    fi
    ln -sfn "$src" "$dest"
    echo "  $dest"
}

echo "niri:"
link "$REPO/niri/config.kdl" "$CONFIG/niri/config.kdl"
link "$REPO/niri/cfg" "$CONFIG/niri/cfg"
link "$REPO/niri/startup.fish" "$CONFIG/niri/startup.fish"

echo "noctalia:"
link "$REPO/noctalia/settings.toml" "$STATE/noctalia/settings.toml"
link "$REPO/noctalia/shell-config.toml" "$CONFIG/noctalia/config.toml"
for plugin in next-meeting media-controls teams-status posture present; do
    link "$REPO/noctalia/$plugin" "$SHARE/noctalia/plugins/$plugin"
done

echo "scripts:"
for script in "$REPO"/bin/*; do
    link "$script" "$HOME/.local/bin/$(basename "$script")"
done

echo "systemd user units:"
for unit in "$REPO"/systemd/*; do
    link "$unit" "$CONFIG/systemd/user/$(basename "$unit")"
done

echo "wireplumber:"
for conf in "$REPO"/wireplumber/*.conf; do
    link "$conf" "$CONFIG/wireplumber/wireplumber.conf.d/$(basename "$conf")"
done

echo "misc:"
link "$REPO/misc/niri-portals.conf" "$CONFIG/xdg-desktop-portal/niri-portals.conf"
link "$REPO/misc/teams-for-linux-config.json" "$CONFIG/teams-for-linux/config.json"
link "$REPO/misc/teams-calendar.source" "$CONFIG/evolution/sources/teams-calendar.source"
link "$REPO/misc/hotcorner" "$CONFIG/quickshell/hotcorner"

echo
echo "Now enable the services:"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now teams-calendar-sync.timer teams-calendar-http.service \\"
echo "      teams-call-watch.service mpris-follow.service hotcorner.service"
