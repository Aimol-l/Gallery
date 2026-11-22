// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Gallery

// 应用内确认弹窗（样式与设计稿一致，不依赖平台原生对话框）
Item {
    id: root
    property bool opened: false
    property string title: ""
    property string text: ""
    property string confirmText: qsTr("确定")
    property bool danger: true

    signal accepted()
    signal rejected()

    visible: opened
    focus: opened

    function open(titleText: string, bodyText: string): void {
        root.title = titleText;
        root.text = bodyText;
        root.opened = true;
    }
    function reject(): void {
        root.opened = false;
        root.rejected();
    }
    function accept(): void {
        root.opened = false;
        root.accepted();
    }

    Rectangle {
        anchors.fill: parent
        color: "#66000000"
        MouseArea {
            anchors.fill: parent
            onClicked: root.reject()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(400, parent.width - 40)
        height: column.height + 40
        radius: 14
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        MouseArea { anchors.fill: parent }

        Column {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 12

            Text {
                width: parent.width
                text: root.title
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Theme.ink
            }
            Text {
                width: parent.width
                text: root.text
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.muted
                lineHeight: 1.3
            }
            Row {
                anchors.right: parent.right
                spacing: 8

                Rectangle {
                    width: 76
                    height: 34
                    radius: 8
                    color: cancelMouse.containsMouse ? Theme.hover : Theme.surface
                    border.width: 1
                    border.color: Theme.line
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("取消")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.muted
                    }
                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.reject()
                    }
                }

                Rectangle {
                    width: 84
                    height: 34
                    radius: 8
                    color: root.danger
                           ? (confirmMouse.containsMouse ? Qt.darker(Theme.danger, 1.1) : Theme.danger)
                           : (confirmMouse.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent)
                    Text {
                        anchors.centerIn: parent
                        text: root.confirmText
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: "#ffffff"
                    }
                    MouseArea {
                        id: confirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.accept()
                    }
                }
            }
        }
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: root.opened
        onActivated: root.reject()
    }
}
