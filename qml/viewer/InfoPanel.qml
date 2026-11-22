// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

Rectangle {
    id: root
    property var info: ({})
    property bool portrait: false
    property bool favorite: false

    signal favoriteToggled()

    property string copiedPath: ""
    function copyPath(): void {
        const text = root.info.fullPath ?? "";
        if (text.length === 0)
            return;
        clipboard.text = text;
        clipboard.selectAll();
        clipboard.copy();
        root.copiedPath = text;
        copiedTimer.restart();
    }

    TextEdit {
        id: clipboard
        visible: false
    }
    Timer {
        id: copiedTimer
        interval: 1200
        onTriggered: root.copiedPath = ""
    }

    width: portrait ? Math.min(280, parent ? parent.width - 32 : 280) : 280
    height: column.height + 32
    radius: 14
    color: Theme.overlayBar
    border.width: 1
    border.color: Theme.line

    readonly property var rows: [
        { k: "文件名", v: info.name ?? "—" },
        { k: "尺寸", v: info.dimensions ?? "—" },
        { k: "大小", v: info.size ?? "—" },
        { k: "修改时间", v: info.modified ?? "—" },
        { k: "位置", v: info.path ?? "—", copy: true },
        { k: "来源", v: info.source ?? "—" },
    ]

    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 0

        Item {
            width: column.width
            height: 24

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("图片信息")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Theme.ink
            }
            Text {
                id: star
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.favorite ? "★" : "☆"
                font.pixelSize: 17
                color: root.favorite ? Theme.accent : Theme.faint
            }
            MouseArea {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 24
                hoverEnabled: true
                onClicked: root.favoriteToggled()
            }
        }

        Repeater {
            model: root.rows
            delegate: Item {
                id: row
                required property var modelData

                width: column.width
                height: Math.max(28, valueText.implicitHeight + 12)

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: 6
                    width: 64
                    text: row.modelData.k
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.faint
                }
                Text {
                    id: valueText
                    anchors.left: parent.left
                    anchors.leftMargin: 70
                    anchors.right: row.modelData.copy ? copyIcon.left : parent.right
                    anchors.rightMargin: row.modelData.copy ? 6 : 0
                    anchors.top: parent.top
                    anchors.topMargin: 6
                    text: row.modelData.v
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.ink
                }
                Text {
                    id: copyIcon
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    visible: row.modelData.copy === true
                    text: root.copiedPath.length > 0 ? "✓" : "⧉"
                    font.pixelSize: 13
                    color: root.copiedPath.length > 0 ? Theme.accent : Theme.faint
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.copyPath()
                    }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.line
                }
            }
        }
    }
}
