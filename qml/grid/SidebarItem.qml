// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Gallery

Rectangle {
    id: root
    property string glyph: ""
    property string label: ""
    property int count: 0
    property bool active: false
    signal clicked()

    height: 36
    radius: 8
    color: active ? Theme.surface : (mouse.containsMouse ? Theme.hover : "transparent")
    border.width: active ? 1 : 0
    border.color: Theme.line

    Text {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        font.pixelSize: 14
        color: root.active ? Theme.accent : Theme.faint
    }
    Text {
        anchors.left: icon.right
        anchors.leftMargin: 10
        anchors.right: countText.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: 14
        font.weight: root.active ? Font.DemiBold : Font.Normal
        color: root.active ? Theme.ink : Theme.muted
    }
    Text {
        id: countText
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.count
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: Theme.faint
        font.features: { "tnum": 1 }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
