// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Gallery

Rectangle {
    id: root
    property string text: ""
    property bool primary: false
    property bool danger: false
    signal clicked()

    width: label.implicitWidth + 28
    height: 32
    radius: 8
    color: {
        if (root.danger)
            return mouse.containsMouse ? Qt.darker(Theme.danger, 1.08) : Theme.danger;
        if (root.primary)
            return mouse.containsMouse ? Qt.darker(Theme.accent, 1.08) : Theme.accent;
        return mouse.containsMouse ? Theme.hover : Theme.surface;
    }
    border.width: (root.primary || root.danger) ? 0 : 1
    border.color: Theme.line

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: (root.primary || root.danger) ? Font.DemiBold : Font.Normal
        color: (root.primary || root.danger) ? "#ffffff" : Theme.muted
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
