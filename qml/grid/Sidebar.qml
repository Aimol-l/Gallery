// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

Item {
    id: root
    required property PhotoModel model

    // 文件夹条目的图标（按 root id），未识别的用通用图标
    readonly property var glyphs: ({
        "pictures": "▣",
        "screenshots": "▢",
        "camera": "◐",
        "downloads": "↓",
        "documents": "▤"
    })

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

        // 文件夹入口来自 PhotoModel.sidebarEntries（只含实际存在的目录），
        // 显示名随 XDG 用户目录 / 语言变化，不再写死
        Repeater {
            model: root.model.sidebarEntries

            delegate: SidebarItem {
                required property var modelData

                width: parent.width
                glyph: root.glyphs[modelData.id] ?? "▤"
                label: modelData.label
                count: root.model.counts[modelData.id] ?? 0
                active: root.model.filter === modelData.id
                onClicked: root.model.filter = modelData.id
            }
        }
    }
}
