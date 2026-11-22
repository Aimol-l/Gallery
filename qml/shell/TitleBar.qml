// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

Item {
    id: root

    required property Window win
    required property PhotoModel model
    property bool portrait: false
    // 0..1，映射到缩略图边长
    property real zoomValue: 0.3

    signal searchCommitted(string text)
    signal settingsRequested()

    function toggleMaximize(): void {
        if (root.win.visibility === Window.Maximized)
            root.win.showNormal()
        else
            root.win.showMaximized()
    }

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

    // 空白区域：拖动窗口 / 双击最大化
    MouseArea {
        anchors.fill: parent
        onPressed: root.win.startSystemMove()
        onDoubleClicked: root.toggleMaximize()
    }

    Row {
        id: brandRow
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Rectangle {
            width: 28
            height: 28
            radius: 8
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(Theme.accent, 1.35) }
                GradientStop { position: 1.0; color: Theme.accent }
            }
            Text {
                anchors.centerIn: parent
                text: "▧"
                color: "#ffffff"
                font.pixelSize: 13
            }
        }
        Text {
            text: qsTr("图片查看器")
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: Theme.ink
        }
    }

    // 搜索框：横屏时左边缘对齐侧栏右边界（内容区起点）
    Rectangle {
        id: searchBox
        x: root.portrait ? brandRow.x + brandRow.width + 14 : Theme.sidebarWidth
        anchors.verticalCenter: parent.verticalCenter
        width: root.portrait ? 150 : 230
        height: 36
        radius: 8
        color: Theme.hover
        border.width: 1
        border.color: Theme.line

        Text {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: "⌕"
            font.pixelSize: 14
            color: Theme.faint
        }
        TextInput {
            id: searchInput
            anchors.left: searchIcon.right
            anchors.leftMargin: 7
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: 12
            selectionColor: Theme.accentSoft
            selectByMouse: true
            onAccepted: root.searchCommitted(text)

            Text {
                anchors.fill: parent
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: Text.AlignVCenter
                text: qsTr("搜索文件名…")
                font: searchInput.font
                color: Theme.faint
                visible: searchInput.text.length === 0
            }
        }
    }

    // 排序（时间 / 名称 / 大小）
    Rectangle {
        id: sortButton
        x: searchBox.x + searchBox.width + 8
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 34
        radius: 8
        color: sortMouse.containsMouse ? Theme.hover : Theme.surface
        border.width: 1
        border.color: Theme.line
        visible: !root.portrait

        Text {
            anchors.centerIn: parent
            text: "⇅"
            font.pixelSize: 14
            color: Theme.muted
        }
        MouseArea {
            id: sortMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.model.sortMode = (root.model.sortMode + 1) % 3
        }
    }

    // 缩略图大小
    Item {
        id: zoomControl
        x: sortButton.x + sortButton.width + 12
        anchors.verticalCenter: parent.verticalCenter
        width: 152
        height: 40
        visible: !root.portrait

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
            id: zoomTrack
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: Theme.sunken

            Rectangle {
                width: zoomTrack.width * root.zoomValue
                height: 4
                radius: 2
                color: Theme.muted
            }
            Rectangle {
                x: zoomTrack.width * root.zoomValue - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: "#ffffff"
                border.width: 1
                border.color: Theme.knobBorder
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                onPositionChanged: (mouse) => {
                    root.zoomValue = Math.max(0, Math.min(1, mouse.x / zoomTrack.width))
                }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        WindowButton {
            glyph: "⚙"
            onClicked: root.settingsRequested()
        }
        WindowButton {
            glyph: "−"
            onClicked: root.win.showMinimized()
        }
        WindowButton {
            visible: !root.portrait
            glyph: root.win.visibility === Window.Maximized ? "❐" : "▢"
            onClicked: root.toggleMaximize()
        }
        WindowButton {
            glyph: "✕"
            danger: true
            onClicked: root.win.close()
        }
    }
}
