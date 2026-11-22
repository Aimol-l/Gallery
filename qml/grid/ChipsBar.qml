// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

Item {
    id: root
    required property PhotoModel model

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.line
    }

    ListView {
        id: chips
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        model: [
            { id: "all", label: qsTr("全部") },
            { id: "recent", label: qsTr("最近") },
            { id: "favorites", label: qsTr("收藏") },
            { id: "screenshots", label: qsTr("截图") },
            { id: "camera", label: qsTr("Android 相机") },
            { id: "downloads", label: qsTr("下载") },
        ]

        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool active: root.model.filter === modelData.id

            width: chipText.implicitWidth + 28
            height: 34
            radius: 17
            color: active ? Theme.accent : Theme.surface
            border.width: 1
            border.color: active ? Theme.accent : Theme.line

            Text {
                id: chipText
                anchors.centerIn: parent
                text: root.model.counts[chip.modelData.id] !== undefined
                      ? chip.modelData.label + "  " + root.model.counts[chip.modelData.id]
                      : chip.modelData.label
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: parent.active ? "#ffffff" : Theme.muted
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.model.filter = chip.modelData.id
            }
        }
    }
}
