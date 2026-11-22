// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Gallery

Rectangle {
    id: root
    property string glyph: ""
    property bool danger: false
    property bool active: false
    signal clicked()

    width: 36
    height: 36
    radius: 8
    color: mouse.containsMouse
           ? (danger ? Theme.danger : Theme.hover)
           : (active ? Theme.sunken : "transparent")

    Behavior on color { ColorAnimation { duration: 80 } }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        font.family: Theme.fontFamily
        font.pixelSize: 14
        color: mouse.containsMouse && root.danger ? "#ffffff" : Theme.muted
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
