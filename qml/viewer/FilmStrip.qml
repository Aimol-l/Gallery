// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

// 查看模式左侧 138px 图片列表：当前项 accent 描边并居中，切换时自动滚动跟随。
Item {
    id: root
    required property PhotoModel model
    required property int currentIndex
    required property int total
    property string title: ""

    signal activated(int index)

    readonly property int radius: 14
    property var indices: []

    function rebuild(): void {
        if (total <= 0) {
            indices = [];
            return;
        }
        const start = Math.max(0, currentIndex - radius);
        const end = Math.min(total - 1, currentIndex + radius);
        const list = [];
        for (let i = start; i <= end; ++i)
            list.push(i);
        indices = list;
        Qt.callLater(function() {
            strip.positionViewAtIndex(currentIndex - start, ListView.Center);
        });
    }

    onCurrentIndexChanged: rebuild()
    onTotalChanged: rebuild()
    Component.onCompleted: rebuild()

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

    Item {
        id: stripHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 36

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.RichText
            text: "<b>" + (root.currentIndex + 1) + "</b> / " + root.total
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.faint
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 70
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: root.title
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.faint
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.line
        }
    }

    ListView {
        id: strip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: stripHeader.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 8
        clip: true
        spacing: 7
        boundsBehavior: Flickable.StopAtBounds
        model: root.indices

        delegate: Item {
            id: item
            required property int modelData
            readonly property var photoData: root.model.photoAt(modelData)
            readonly property bool active: modelData === root.currentIndex

            width: strip.width - 16
            height: 94

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: item.active ? Theme.surface : "transparent"
            }

            Rectangle {
                id: thumb
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 4
                width: parent.width - 8
                height: 70
                radius: 6
                clip: true
                color: Theme.sunken

                Image {
                    anchors.fill: parent
                    visible: item.photoData && item.photoData.path
                    source: visible ? "image://thumbs/" + encodeURIComponent(item.photoData.path) : ""
                    sourceSize.width: 148
                    sourceSize.height: 148
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: item.photoData && item.photoData.video
                    text: "▶"
                    font.pixelSize: 18
                    color: "#f2f3f7"
                }
            }

            Text {
                anchors.top: thumb.bottom
                anchors.topMargin: 3
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: item.photoData ? item.photoData.name : ""
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: item.active ? Font.DemiBold : Font.Normal
                color: item.active ? Theme.ink : Theme.faint
            }

            // 当前项描边覆盖在缩略图之上
            Rectangle {
                anchors.fill: thumb
                radius: thumb.radius
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
                visible: item.active
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.activated(item.modelData)
            }
        }
    }
}
