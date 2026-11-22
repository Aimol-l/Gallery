// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Gallery

// 查看模式底部操作栏按钮：图标 + 文字（竖屏只留图标）
Item {
    id: root
    property string icon: ""
    property string label: ""
    property bool danger: false
    property bool disabled: false
    property bool compact: false
    signal clicked()

    width: compact ? 42 : 60
    height: 50
    opacity: disabled ? 0.32 : 1

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 9
        color: mouse.containsMouse && !root.disabled
               ? (root.danger ? "#14c9483f" : Theme.hover)
               : "transparent"
    }

    Column {
        anchors.centerIn: parent
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            font.pixelSize: 16
            color: root.danger ? Theme.danger : Theme.muted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.compact
            text: root.label
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: root.danger ? Theme.danger : Theme.muted
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.disabled
        onClicked: root.clicked()
    }
}
