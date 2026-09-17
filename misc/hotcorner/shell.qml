// A top-right hot corner, mirroring niri's built-in top-left one.
//
// niri's own hot corners only ever open the overview - they take no custom
// action - so the trigger zone is its own tiny layer-shell surface instead.
// Nudge the pointer into the corner and the keybind cheatsheet opens.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors.top: true
            anchors.right: true
            implicitWidth: 8
            implicitHeight: 8
            color: "transparent"

            // Sit above the bar, but never reserve space or take keyboard focus.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                // Hover only: clicks stay with whatever is underneath.
                acceptedButtons: Qt.NoButton
                onEntered: {
                    if (cooldown.running)
                        return;
                    cooldown.restart();
                    cheatsheet.running = true;
                }
            }

            // Without this, brushing the corner re-triggers on every enter.
            Timer {
                id: cooldown
                interval: 1500
            }

            Process {
                id: cheatsheet
                command: ["noctalia", "msg", "panel-open", "kenn/keybind-cheatsheet:cheatsheet"]
            }
        }
    }
}
