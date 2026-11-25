// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

// 沉浸式查看模式：顶部信息栏 + 左侧 filmstrip + 舞台 + 底部操作栏 + 信息浮层。
Item {
    id: root
    required property Window win
    required property PhotoModel model
    property bool portrait: false
    property bool opened: false
    property int currentIndex: -1
    property string currentPath: "" // 当前查看的路径，模型 rebuild 后据此重定位
    // 目录播放列表（model 扁平索引）：文件管理器打开单个文件时只在其同目录内浏览；
    // 空 = 全部照片（从网格进入时）
    property var playlist: []

    readonly property int playlistLength: playlist.length > 0 ? playlist.length : model.photoCount
    property bool infoOpen: false
    property string toastText: ""
    property int lastClosedIndex: -1

    readonly property int total: model.photoCount
    readonly property var currentPhoto: {
        const revision = root.model.revision; // 删除/收藏/过滤后强制重新取值
        return currentIndex >= 0 && revision >= 0
               ? root.model.photoAt(currentIndex) : ({});
    }
    readonly property var currentInfo: {
        const revision = root.model.revision;
        return currentIndex >= 0 && revision >= 0
               ? root.model.photoInfo(currentIndex) : ({});
    }

    signal dismissed()

    focus: opened
    visible: opened

    function openAt(index: int, ids): void {
        if (index < 0 || index >= root.model.photoCount)
            return;
        root.playlist = ids ?? [];
        root.currentIndex = index;
        root.currentPath = pathAt(index);
        root.infoOpen = false;
        root.opened = true;
        root.forceActiveFocus();
    }
    function close(): void {
        if (!root.opened)
            return;
        root.lastClosedIndex = root.currentIndex;
        root.opened = false;
        root.infoOpen = false;
        root.currentIndex = -1;
        root.currentPath = "";
        root.playlist = [];
        root.dismissed();
    }
    function goTo(index: int): void {
        if (index < 0 || index >= root.model.photoCount)
            return;
        root.currentIndex = index;
        root.currentPath = pathAt(index);
    }
    function pathAt(index: int): string {
        if (index < 0 || index >= root.model.photoCount)
            return "";
        const photo = root.model.photoAt(index);
        return photo.path ?? "";
    }

    // 播放列表中的当前位置；非列表模式（playlist 为空）返回索引本身
    function playlistPosition(): int {
        if (root.playlist.length === 0)
            return root.currentIndex;
        for (let i = 0; i < root.playlist.length; ++i) {
            if (root.playlist[i] === root.currentIndex)
                return i;
        }
        return -1;
    }

    // 模型 rebuild（扫描完成/删除/收藏）后索引会漂移：重建目录播放列表并按路径重定位；
    // 文件已不在库里就退出查看模式
    Connections {
        target: root.model
        function onRevisionChanged() {
            if (!root.opened || root.currentPath === "")
                return;
            if (root.playlist.length > 0) {
                const ids = root.model.indicesInDirectory(root.currentPath);
                if (ids.length > 0)
                    root.playlist = ids;
            }
            if (root.currentIndex >= 0 && root.currentIndex < root.model.photoCount) {
                const photo = root.model.photoAt(root.currentIndex);
                if ((photo.path ?? "") === root.currentPath)
                    return;
            }
            const index = root.model.indexForPath(root.currentPath);
            if (index >= 0) {
                root.currentIndex = index;
            } else {
                root.close();
            }
        }
    }
    // 在播放列表内循环切换（最后一张之后回到第一张）
    function next(): void {
        if (root.currentIndex < 0)
            return;
        if (root.playlist.length === 0) {
            if (root.model.photoCount > 0)
                root.goTo((root.currentIndex + 1) % root.model.photoCount);
            return;
        }
        const pos = root.playlistPosition();
        if (pos >= 0)
            root.goTo(root.playlist[(pos + 1) % root.playlist.length]);
    }
    function previous(): void {
        if (root.currentIndex < 0)
            return;
        if (root.playlist.length === 0) {
            if (root.model.photoCount > 0)
                root.goTo((root.currentIndex - 1 + root.model.photoCount) % root.model.photoCount);
            return;
        }
        const pos = root.playlistPosition();
        if (pos >= 0)
            root.goTo(root.playlist[(pos - 1 + root.playlist.length) % root.playlist.length]);
    }
    function step(direction: int): void {
        if (!root.opened || deleteDialog.opened)
            return;
        if (stepTimer.running)
            return;
        stepTimer.restart();
        if (direction < 0)
            root.previous();
        else
            root.next();
    }
    function showToast(message: string): void {
        root.toastText = message;
        toastTimer.restart();
    }
    function requestDelete(): void {
        deleteDialog.open(
            qsTr("删除图片"),
            qsTr("确定把“%1”移到回收站吗？").arg(root.currentPhoto.name ?? ""));
    }
    function devRotate(): void {
        stage.rotate();
    }

    onTotalChanged: {
        if (!opened)
            return;
        if (total === 0)
            close();
        else if (currentIndex >= total)
            currentIndex = total - 1;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.stageBg
    }

    // ---- 顶部栏 ----
    Rectangle {
        id: vtop
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 54
        color: Theme.overlayBar

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.line
        }

        MouseArea {
            anchors.fill: parent
            onPressed: root.win.startSystemMove()
            onDoubleClicked: {
                if (root.win.visibility === Window.Maximized)
                    root.win.showNormal();
                else
                    root.win.showMaximized();
            }
        }

        WindowButton {
            id: backButton
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            glyph: "←"
            onClicked: root.close()
        }

        Column {
            anchors.left: backButton.right
            anchors.leftMargin: 6
            anchors.right: windowButtons.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                elide: Text.ElideMiddle
                text: root.currentPhoto.name ?? ""
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Theme.ink
            }
            Text {
                width: parent.width
                visible: text.length > 0
                elide: Text.ElideRight
                text: {
                    const info = root.currentInfo;
                    if (!info || !info.dimensions)
                        return "";
                    return info.dimensions + " · " + info.size + " · "
                           + (root.playlistPosition() + 1) + " / " + root.playlistLength;
                }
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.faint
            }
        }

        Row {
            id: windowButtons
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            WindowButton {
                glyph: "ⓘ"
                active: root.infoOpen
                onClicked: root.infoOpen = !root.infoOpen
            }
            WindowButton {
                glyph: "⋯"
                onClicked: root.showToast(qsTr("更多功能开发中"))
            }
            WindowButton {
                glyph: "−"
                onClicked: root.win.showMinimized()
            }
            WindowButton {
                visible: !root.portrait
                glyph: root.win.visibility === Window.Maximized ? "❐" : "▢"
                onClicked: {
                    if (root.win.visibility === Window.Maximized)
                        root.win.showNormal();
                    else
                        root.win.showMaximized();
                }
            }
            WindowButton {
                glyph: "✕"
                danger: true
                onClicked: root.win.close()
            }
        }
    }

    // ---- 左侧图片列表 ----
    FilmStrip {
        id: filmStrip
        visible: !root.portrait
        width: 138
        anchors.left: parent.left
        anchors.top: vtop.bottom
        anchors.bottom: vbottom.top
        model: root.model
        currentIndex: root.currentIndex
        total: root.total
        playlist: root.playlist
        title: root.model.title
        onActivated: (index) => root.goTo(index)
    }

    // ---- 图片舞台 ----
    PhotoStage {
        id: stage
        anchors.left: root.portrait ? parent.left : filmStrip.right
        anchors.right: parent.right
        anchors.top: vtop.bottom
        anchors.bottom: vbottom.top
        photo: root.currentPhoto
        portrait: root.portrait
        onStepRequested: (direction) => root.step(direction)
    }

    // ---- 信息浮层 ----
    InfoPanel {
        id: infoPanel
        visible: root.infoOpen
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.top: vtop.bottom
        anchors.topMargin: 16
        info: root.currentInfo
        portrait: root.portrait
        favorite: root.currentInfo.favorite ?? false
        onFavoriteToggled: root.model.toggleFavorite(root.currentIndex)
    }

    // ---- 底部操作栏 ----
    Rectangle {
        id: vbottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 66
        color: Theme.overlayBar

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.line
        }

        Row {
            anchors.centerIn: parent
            spacing: root.portrait ? 0 : 2

            ViewerButton {
                icon: "‹"
                label: qsTr("上一张")
                compact: root.portrait
                disabled: root.playlistLength <= 1
                onClicked: root.previous()
            }
            ViewerButton {
                icon: "⊖"
                label: qsTr("缩小")
                compact: root.portrait
                disabled: root.currentPhoto.video ?? false
                onClicked: stage.zoomOut()
            }
            ViewerButton {
                icon: "⊕"
                label: qsTr("放大")
                compact: root.portrait
                disabled: root.currentPhoto.video ?? false
                onClicked: stage.zoomIn()
            }

            Rectangle {
                height: 26
                width: zoomChipText.implicitWidth + 22
                radius: 13
                color: Theme.hover
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: zoomChipText
                    anchors.centerIn: parent
                    text: (root.currentPhoto.video ?? false)
                          ? qsTr("视频")
                          : (stage.isFit
                             ? qsTr("适应窗口")
                             : (stage.zoomPercent + "%" + (stage.canPan ? qsTr(" · 拖动平移") : "")))
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.muted
                }
            }

            ViewerButton {
                icon: "⟳"
                label: qsTr("旋转")
                compact: root.portrait
                disabled: root.currentPhoto.video ?? false
                onClicked: stage.rotate()
            }
            ViewerButton {
                icon: "◱"
                label: qsTr("裁剪")
                compact: root.portrait
                disabled: true
                onClicked: root.showToast(qsTr("裁剪将在后续版本提供"))
            }
            ViewerButton {
                icon: "↗"
                label: qsTr("分享")
                compact: root.portrait
                disabled: true
                onClicked: root.showToast(qsTr("分享将在后续版本提供"))
            }
            ViewerButton {
                icon: "🗑"
                label: qsTr("删除")
                danger: true
                compact: root.portrait
                onClicked: root.requestDelete()
            }
            ViewerButton {
                icon: "›"
                label: qsTr("下一张")
                compact: root.portrait
                disabled: root.playlistLength <= 1
                onClicked: root.next()
            }
        }
    }

    // 轻提示
    Rectangle {
        id: toast
        visible: root.toastText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: vbottom.top - height - 12
        height: 34
        width: toastLabel.implicitWidth + 28
        radius: 10
        color: Theme.ink

        Text {
            id: toastLabel
            anchors.centerIn: parent
            text: root.toastText
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.surface
        }
    }
    Timer {
        id: toastTimer
        interval: 2200
        onTriggered: root.toastText = ""
    }
    // 滚轮/触控板会连续发事件，限速避免一次手势连跳好几张
    Timer {
        id: stepTimer
        interval: 180
    }

    ConfirmDialog {
        id: deleteDialog
        anchors.fill: parent
        confirmText: qsTr("移到回收站")
        danger: true
        onAccepted: {
            const index = root.currentIndex;
            if (!root.model.moveToTrash(index))
                return;
            if (root.model.photoCount === 0)
                root.close();
            else
                root.currentIndex = Math.min(index, root.model.photoCount - 1);
        }
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: root.opened
        onActivated: {
            if (deleteDialog.opened)
                deleteDialog.reject();
            else if (root.infoOpen)
                root.infoOpen = false;
            else
                root.close();
        }
    }
    Shortcut {
        sequence: "Left"
        context: Qt.ApplicationShortcut
        enabled: root.opened && !deleteDialog.opened
        onActivated: root.previous()
    }
    Shortcut {
        sequence: "Right"
        context: Qt.ApplicationShortcut
        enabled: root.opened && !deleteDialog.opened
        onActivated: root.next()
    }
}
