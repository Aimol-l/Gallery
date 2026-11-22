// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Gallery

Item {
    id: root
    property real value: 0.3
    signal moved(real value)

    width: 200
    height: 30

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: qsTr("小")
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: Theme.faint
    }
    Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: qsTr("大")
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: Theme.faint
    }
    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        radius: 2
        color: Theme.sunken

        Rectangle {
            width: track.width * root.value
            height: 4
            radius: 2
            color: Theme.accent
        }
        Rectangle {
            x: track.width * root.value - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: "#ffffff"
            border.width: 1
            border.color: Theme.knobBorder
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -10
            onPressed: (mouse) => root.moved(Math.max(0, Math.min(1, mouse.x / track.width)))
            onPositionChanged: (mouse) => {
                if (pressed)
                    root.moved(Math.max(0, Math.min(1, mouse.x / track.width)));
            }
        }
    }
}
