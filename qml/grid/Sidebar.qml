// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

Item {
    id: root
    required property PhotoModel model

    Rectangle {
        anchors.fill: parent
        color: Theme.sidebar
    }
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Theme.line
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        topPadding: 4
        spacing: 2

        SidebarItem {
            width: parent.width
            glyph: "▦"
            label: qsTr("全部照片")
            count: root.model.counts.all ?? 0
            active: root.model.filter === "all"
            onClicked: root.model.filter = "all"
        }
        SidebarItem {
            width: parent.width
            glyph: "◷"
            label: qsTr("最近添加")
            count: root.model.counts.recent ?? 0
            active: root.model.filter === "recent"
            onClicked: root.model.filter = "recent"
        }
        SidebarItem {
            width: parent.width
            glyph: "★"
            label: qsTr("收藏")
            count: root.model.counts.favorites ?? 0
            active: root.model.filter === "favorites"
            onClicked: root.model.filter = "favorites"
        }

        Item {
            width: parent.width
            height: 19
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Theme.line
            }
        }

        Text {
            leftPadding: 12
            bottomPadding: 4
            text: qsTr("文件夹")
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 0.8
            color: Theme.faint
        }

        SidebarItem {
            width: parent.width
            glyph: "▣"
            label: qsTr("Pictures")
            count: root.model.counts.pictures ?? 0
            active: root.model.filter === "pictures"
            onClicked: root.model.filter = "pictures"
        }
        SidebarItem {
            width: parent.width
            glyph: "▢"
            label: qsTr("屏幕截图")
            count: root.model.counts.screenshots ?? 0
            active: root.model.filter === "screenshots"
            onClicked: root.model.filter = "screenshots"
        }
        SidebarItem {
            width: parent.width
            glyph: "↓"
            label: qsTr("下载")
            count: root.model.counts.downloads ?? 0
            active: root.model.filter === "downloads"
            onClicked: root.model.filter = "downloads"
        }
        SidebarItem {
            width: parent.width
            glyph: "◐"
            label: qsTr("Android 相机")
            count: root.model.counts.camera ?? 0
            active: root.model.filter === "camera"
            onClicked: root.model.filter = "camera"
        }
        SidebarItem {
            width: parent.width
            glyph: "▤"
            label: qsTr("文档")
            count: root.model.counts.documents ?? 0
            active: root.model.filter === "documents"
            onClicked: root.model.filter = "documents"
        }
    }
}
