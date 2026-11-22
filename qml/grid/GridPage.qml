// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Gallery

Item {
    id: root
    required property PhotoModel model
    property bool portrait: false

    readonly property int gap: Theme.gap
    readonly property int pad: Theme.pagePadding
    // 标题栏滑块（0..1）经由 Main 传入
    property real zoomValue: 0.3
    readonly property int thumbTarget: Math.round(128 + zoomValue * 132)

    readonly property int columns: {
        if (root.portrait)
            return 3;
        const usable = width - pad * 2;
        return Math.max(3, Math.floor((usable + gap) / (thumbTarget + gap)));
    }
    readonly property int cellSize: Math.max(48, Math.floor(
        ((width - pad * 2) - (columns - 1) * gap) / columns))

    // ---- 多选 ----
    property bool selectionMode: false
    property var selectedPaths: ({})
    readonly property int selectedCount: Object.keys(root.selectedPaths).length
    signal deleteRequested(var paths)

    function pathSelected(path): bool {
        return root.selectedPaths[path] === true;
    }
    function setSelected(path, on): void {
        const next = Object.assign({}, root.selectedPaths);
        if (on)
            next[path] = true;
        else
            delete next[path];
        root.selectedPaths = next;
    }
    function beginSelection(path): void {
        if (!root.selectionMode)
            root.selectionMode = true;
        root.setSelected(path, !root.pathSelected(path));
        root.forceActiveFocus();
    }
    function toggleSelection(path): void {
        root.setSelected(path, !root.pathSelected(path));
    }
    function clearSelection(): void {
        root.selectionMode = false;
        root.selectedPaths = ({});
        root.currentFlatIndex = -1;
    }
    function selectedPathList(): var {
        return Object.keys(root.selectedPaths);
    }
    function requestDelete(): void {
        if (root.selectedCount > 0)
            root.deleteRequested(root.selectedPathList());
    }

    // 窗口刚创建时 width 还是负数，先别用临时的 3 列去重建几十万行的模型
    Binding {
        target: root.model
        property: "columns"
        value: root.columns
        when: root.width > root.pad * 2 + 1
    }

    // 模型 reset（排序/筛选/列数/最终整理）后尽量回到原来的顶部照片
    property string pendingTopPath: ""
    Connections {
        target: root.model
        function onModelAboutToBeReset() {
            const row = grid.indexAt(1, Math.max(0, grid.contentY + 2));
            root.pendingTopPath = row >= 0 ? root.model.photoPathInRow(row) : "";
        }
        function onModelReset() {
            if (root.pendingTopPath === "")
                return;
            const row = root.model.rowForPath(root.pendingTopPath);
            root.pendingTopPath = "";
            if (row >= 0)
                Qt.callLater(function() { grid.positionViewAtIndex(row, ListView.Beginning); });
        }
        function onFilterChanged() { root.clearSelection(); }
        function onSearchTextChanged() { root.clearSelection(); }
        function onSortModeChanged() { root.clearSelection(); }
    }

    focus: true
    Keys.onPressed: (event) => {
        const count = root.model.photoCount;
        if (count === 0)
            return;

        let index = root.currentFlatIndex;
        if (index < 0 && event.key !== Qt.Key_Home && event.key !== Qt.Key_End)
            index = 0;

        switch (event.key) {
        case Qt.Key_Left:
            index = Math.max(0, index - 1);
            break;
        case Qt.Key_Right:
            index = Math.min(count - 1, index + 1);
            break;
        case Qt.Key_Up:
            index = Math.max(0, index - root.columns);
            break;
        case Qt.Key_Down:
            index = Math.min(count - 1, index + root.columns);
            break;
        case Qt.Key_Home:
            index = 0;
            break;
        case Qt.Key_End:
            index = count - 1;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (index >= 0)
                root.photoActivated(root.model.photoAt(index));
            event.accepted = true;
            return;
        default:
            return;
        }

        root.currentFlatIndex = index;
        const row = root.model.rowForFlatIndex(index);
        if (row >= 0)
            grid.positionViewAtIndex(row, ListView.Contain);
        event.accepted = true;
    }

    Component.onCompleted: root.forceActiveFocus()

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: root.selectionMode
        onActivated: root.clearSelection()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    // 内容顶栏
    Rectangle {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 58
        color: Theme.surface
        border.width: 0

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.line
        }

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.leftMargin: root.pad
            anchors.verticalCenter: parent.verticalCenter
            text: root.selectionMode
                  ? qsTr("已选 %1 张").arg(root.selectedCount)
                  : root.model.title
            font.family: Theme.fontFamily
            font.pixelSize: 19
            font.weight: Font.DemiBold
            color: Theme.ink
        }
        Text {
            anchors.left: titleText.right
            anchors.leftMargin: 10
            anchors.baseline: titleText.baseline
            visible: !root.selectionMode
            text: {
                const folderCount = root.model.counts.visibleFolders ?? 0;
                let s = root.model.photoCount + qsTr(" 张");
                if (folderCount > 0)
                    s += " · " + folderCount + qsTr(" 个文件夹");
                return s;
            }
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.faint
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.pad
            anchors.verticalCenter: parent.verticalCenter
            visible: root.model.scanning && !root.selectionMode
            text: qsTr("正在扫描…")
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.faint
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: root.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            visible: root.selectionMode

            Rectangle {
                width: 64
                height: 32
                radius: 8
                color: cancelSelectionMouse.containsMouse ? Theme.hover : Theme.surface
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
                    id: cancelSelectionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.clearSelection()
                }
            }

            Rectangle {
                visible: root.selectedCount > 0
                width: 84
                height: 32
                radius: 8
                color: deleteSelectionMouse.containsMouse
                       ? Qt.darker(Theme.danger, 1.08) : Theme.danger
                Text {
                    anchors.centerIn: parent
                    text: qsTr("删除")
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                }
                MouseArea {
                    id: deleteSelectionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.requestDelete()
                }
            }
        }
    }

    ListView {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.topMargin: 6
        anchors.bottomMargin: 24
        clip: true
        model: root.model
        spacing: 0
        cacheBuffer: Math.max(0, height) * 2
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: AppScrollBar {}

        // 滚轮速度：一格约一行缩略图（ListView 默认每次只滚几十像素，太慢）
        WheelHandler {
            id: gridWheel
            target: null
            onWheel: (event) => {
                const maxY = Math.max(0, grid.contentHeight - grid.height);
                const step = event.pixelDelta.y !== 0
                             ? event.pixelDelta.y * 1.6
                             : event.angleDelta.y * 1.6;
                grid.contentY = Math.max(0, Math.min(maxY, grid.contentY - step));
                event.accepted = true;
            }
        }

        delegate: Column {
            id: rowRoot
            required property string dayLabel
            required property int dayCount
            required property var photos

            width: grid.width
            spacing: root.gap
            topPadding: dayLabel !== "" ? 12 : 0
            bottomPadding: 4

            Row {
                height: rowRoot.dayLabel !== "" ? 22 : 0
                visible: rowRoot.dayLabel !== ""
                spacing: 8

                Text {
                    anchors.baseline: parent.bottom
                    text: rowRoot.dayLabel
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Theme.muted
                }
                Text {
                    anchors.baseline: parent.bottom
                    text: rowRoot.dayCount + qsTr(" 张")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.faint
                }
            }

            Row {
                spacing: root.gap
                Repeater {
                    model: rowRoot.photos
                    delegate: ThumbTile {
                        id: tile
                        required property var modelData
                        width: root.cellSize
                        height: root.cellSize
                        photo: modelData
                        selected: root.selectionMode
                                  ? root.selectedPaths[modelData.path] === true
                                  : root.currentFlatIndex === modelData.index
                        onClicked: {
                            if (root.selectionMode) {
                                root.toggleSelection(modelData.path);
                                return;
                            }
                            root.currentFlatIndex = modelData.index;
                            grid.forceActiveFocus();
                            root.photoActivated(modelData);
                        }
                        onLongPressed: root.beginSelection(modelData.path)
                    }
                }
            }
        }
    }

    // 当前选中的扁平下标（供后续查看模式使用）
    property int currentFlatIndex: -1
    signal photoActivated(var photo)

    Column {
        anchors.centerIn: parent
        spacing: 8
        visible: root.model.photoCount === 0 && !root.model.scanning
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("这里还没有照片")
            font.family: Theme.fontFamily
            font.pixelSize: 15
            color: Theme.muted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("把图片放进 ~/Pictures 就会出现在这里")
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.faint
        }
    }
}
