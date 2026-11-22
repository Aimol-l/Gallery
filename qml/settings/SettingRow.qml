// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import Gallery

Item {
    id: row
    property string label: ""
    property string description: ""
    default property alias control: controlRow.data

    width: parent ? parent.width : 0
    height: Math.max(54, layout.implicitHeight + 14)

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: row.label
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.ink
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: row.description
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.faint
            }
        }

        RowLayout {
            id: controlRow
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
        }
    }
}
