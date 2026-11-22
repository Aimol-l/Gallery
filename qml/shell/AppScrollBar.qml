// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls.Basic
import Gallery

ScrollBar {
    id: root

    policy: ScrollBar.AsNeeded
    width: 8

    background: Item {}

    contentItem: Rectangle {
        implicitWidth: 6
        radius: 3
        color: Theme.faint
        opacity: root.pressed ? 0.85 : 0.45
    }
}
