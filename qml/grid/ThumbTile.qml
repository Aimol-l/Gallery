// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Gallery

Rectangle {
    id: root
    property var photo
    property bool selected: false
    signal clicked()
    signal longPressed()

    radius: Theme.radius
    color: Theme.sunken
    clip: true

    // 图片与视频首帧都走 C++ 缩略图缓存（image://thumbs/<path>）
    Image {
        anchors.fill: parent
        visible: root.photo && root.photo.path
        source: visible ? "image://thumbs/" + encodeURIComponent(root.photo.path) : ""
        sourceSize.width: Math.ceil(width * 2)
        sourceSize.height: Math.ceil(height * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }

    Text {
        anchors.centerIn: parent
        visible: root.photo && root.photo.video
        text: "▶"
        font.pixelSize: 26
        color: "#f2f3f7"
    }

    Rectangle {
        visible: root.photo && root.photo.video
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        width: videoBadge.implicitWidth + 10
        height: 16
        radius: 4
        color: "#66000000"
        Text {
            id: videoBadge
            anchors.centerIn: parent
            text: qsTr("视频")
            font.family: Theme.fontFamily
            font.pixelSize: 9
            color: "#ffffff"
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        height: 18
        radius: 4
        color: "#47000000"
        Text {
            anchors.fill: parent
            anchors.leftMargin: 5
            anchors.rightMargin: 5
            verticalAlignment: Text.AlignVCenter
            text: root.photo ? root.photo.name : ""
            elide: Text.ElideMiddle
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: "#f0f1f5"
        }
    }

    // 选中描边必须画在图片之上（Rectangle 的 border 会被子项盖住）
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 3
        border.color: Theme.accent
        visible: root.selected
    }

    MouseArea {
        id: input
        anchors.fill: parent
        hoverEnabled: true
        property bool longPressTriggered: false

        onPressed: {
            longPressTriggered = false;
            longPressTimer.start();
        }
        onReleased: longPressTimer.stop()
        onCanceled: longPressTimer.stop()
        onClicked: {
            if (longPressTriggered) {
                longPressTriggered = false;
                return;
            }
            root.clicked();
        }

        Timer {
            id: longPressTimer
            interval: 600
            onTriggered: {
                input.longPressTriggered = true;
                root.longPressed();
            }
        }
    }
}
