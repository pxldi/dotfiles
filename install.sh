#!/usr/bin/env bash
# Link this repo's files into place for one host profile.
#
#   ./install.sh work    the work laptop
#   ./install.sh home    the desktop at home
#
# Symlinks rather than copies, so editing the live config edits the repo and
# `git diff` shows what has drifted. Anything already present is backed up
# with a .bak suffix rather than overwritten.
#
# Everything outside hosts/ is shared. A profile supplies the four things that
# cannot be: the outputs, the workspace-to-output map, the startup layout, and
# the bar. It also picks which scripts, plugins and units get linked at all -
# see hosts/<profile>/manifest.sh.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"

PROFILE="${1:-}"
if [ -z "$PROFILE" ] || [ ! -d "$REPO/hosts/$PROFILE" ]; then
    echo "usage: ./install.sh <profile>"
    echo "profiles: $(ls "$REPO/hosts" | tr '\n' ' ')"
    exit 1
fi
HOST="$REPO/hosts/$PROFILE"

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

# shellcheck source=/dev/null
. "$HOST/manifest.sh"

echo "profile: $PROFILE"

echo "niri:"
# An earlier install linked cfg/ as one directory. The files go in one by one
# now, so that symlink has to go first, or every link would point at itself.
[ -L "$CONFIG/niri/cfg" ] && rm "$CONFIG/niri/cfg"
link "$REPO/niri/config.kdl" "$CONFIG/niri/config.kdl"
# Linked file by file, not as a directory, so the host profile can drop its own
# display.kdl, workspaces.kdl and host-rules.kdl in beside the shared ones.
for cfg in "$REPO"/niri/cfg/*.kdl "$HOST"/niri/*.kdl; do
    link "$cfg" "$CONFIG/niri/cfg/$(basename "$cfg")"
done
link "$HOST/startup.fish" "$CONFIG/niri/startup.fish"

echo "noctalia:"
link "$HOST/noctalia/settings.toml" "$STATE/noctalia/settings.toml"
link "$REPO/noctalia/shell-config.toml" "$CONFIG/noctalia/config.toml"
for plugin in "${PLUGINS[@]}"; do
    link "$REPO/noctalia/$plugin" "$SHARE/noctalia/plugins/$plugin"
done

echo "scripts:"
for script in "${SCRIPTS[@]}"; do
    link "$REPO/bin/$script" "$HOME/.local/bin/$script"
done

echo "systemd user units:"
for unit in "${UNITS[@]}"; do
    link "$REPO/systemd/$unit" "$CONFIG/systemd/user/$unit"
done

echo "wireplumber:"
for conf in "$REPO"/wireplumber/*.conf; do
    link "$conf" "$CONFIG/wireplumber/wireplumber.conf.d/$(basename "$conf")"
done

echo "misc:"
link "$REPO/misc/niri-portals.conf" "$CONFIG/xdg-desktop-portal/niri-portals.conf"
link "$REPO/misc/hypridle.conf" "$CONFIG/hypr/hypridle.conf"
link "$REPO/misc/hotcorner" "$CONFIG/quickshell/hotcorner"
extras

echo
echo "Now enable the services:"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now $ENABLE"
