#!/usr/bin/env fish
# Startup layout for niri. Which workspace each window lands on is decided by the
# window-rules in hosts/home/niri/host-rules.kdl; the per-slot --class is what lets
# those rules tell otherwise-identical ghostty windows apart. The sleeps only fix
# left-to-right order.
#
# No claude here on purpose: a claude session is task-bound, so it wants a real
# working directory. Spawn one with Mod+Ctrl+Return instead.

function term --argument-names slot
    ghostty --class=com.mitchellh.ghostty.$slot &
    sleep 0.7
end

# ── workspace 1: browser (2/3) · shell (1/3) ──
helium-browser &
sleep 0.7
term w1a

# ── workspace 2: two shells, half each ──
term w2a
term w2b

# ── workspace 3 (right screen): music ──
feishin &
