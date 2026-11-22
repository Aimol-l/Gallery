// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Gallery

Rectangle {
    id: card
    property string title: ""
    default property alias content: body.data

    width: parent ? parent.width : 0
    implicitHeight: contentColumn.implicitHeight + 34
    radius: 12
    color: Theme.surface
    border.width: 1
    border.color: Theme.line

    Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 10

        Text {
            visible: card.title !== ""
            text: card.title
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: Theme.ink
        }
        Column {
            id: body
            width: parent.width
            spacing: 0
        }
    }
}
