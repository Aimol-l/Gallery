// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

Window {
    id: window
    width: 1440
    height: 900
    minimumWidth: Math.round(760 * AppSettings.uiScale)
    minimumHeight: Math.round(560 * AppSettings.uiScale)
    visible: true
    title: qsTr("图片查看器")
    color: Theme.bg
    flags: Qt.Window | Qt.FramelessWindowHint

    readonly property bool portrait: height > width
    readonly property int titleBarHeight: Theme.titleBarHeight

    // 窗口几何（Wayland 不保存位置）
    property int normalWidth: width
    property int normalHeight: height
    property bool geometryReady: false
    // 打开方式/拖放
    property string pendingOpenPath: ""
    property int pendingOpenTries: 0
    property string toastText: ""

    function showToast(message: string): void {
        window.toastText = message;
        toastTimer.restart();
    }

    function openPath(path: string): void {
        if (!path) {
            window.requestActivate();
            return;
        }
        let index = library.indexForPath(path);
        if (index < 0 && (library.filter !== "all" || library.searchText !== "")) {
            library.filter = "all";
            library.searchText = "";
            index = library.indexForPath(path);
        }
        if (index >= 0) {
            viewer.openAt(index);
            window.requestActivate();
            return;
        }
        // 可能还在扫描，稍后重试
        window.pendingOpenPath = path;
        window.pendingOpenTries = 0;
        openRetryTimer.start();
    }

    // 文件管理器 / 命令行打开单个文件：切到其所在目录浏览（非递归），
    // 侧栏与网格只显示同目录图片，扫描完成后定位到打开的那张
    function openFromLauncher(path: string): void {
        if (!path) {
            window.requestActivate();
            return;
        }
        if (!library.openFileScope(path)) {
            window.showToast(qsTr("无法打开文件"));
            return;
        }
        window.pendingOpenPath = path;
        window.pendingOpenTries = 0;
        openRetryTimer.start();
        window.requestActivate();
    }

    onWidthChanged: {
        if (window.geometryReady && window.visibility === Window.Windowed)
            window.normalWidth = width;
    }
    onHeightChanged: {
        if (window.geometryReady && window.visibility === Window.Windowed)
            window.normalHeight = height;
    }
    onVisibilityChanged: {
        if (!window.geometryReady)
            return;
        if (window.visibility === Window.Maximized) {
            AppSettings.winMaximized = true;
        } else if (window.visibility === Window.Windowed) {
            AppSettings.winMaximized = false;
            AppSettings.winWidth = window.normalWidth;
            AppSettings.winHeight = window.normalHeight;
        }
    }
    onClosing: {
        if (window.geometryReady) {
            AppSettings.winWidth = window.normalWidth;
            AppSettings.winHeight = window.normalHeight;
        }
    }

    Timer {
        id: openRetryTimer
        interval: 400
        repeat: true
        running: window.pendingOpenPath !== ""
        onTriggered: {
            // 扫描是流式的：目标文件一旦出现在模型里就打开，不必等全量扫描结束
            const index = library.indexForPath(window.pendingOpenPath);
            if (index >= 0) {
                viewer.openAt(index, library.indicesInDirectory(window.pendingOpenPath));
                window.pendingOpenPath = "";
                return;
            }
            // 兜底：无论扫描是否结束，30s 后都不再静默等待
            if (++window.pendingOpenTries > 75) {
                window.showToast(qsTr("无法打开：文件不在图片库中"));
                window.pendingOpenPath = "";
            }
        }
    }
    Timer {
        id: toastTimer
        interval: 2400
        onTriggered: window.toastText = ""
    }

    // 主数据模型
    PhotoModel {
        id: library
        Component.onCompleted: scan()
    }

    // 整体界面缩放：用缩放后的逻辑尺寸布局，再统一放大，保证文字/间距/控件一起变化
    Item {
        id: uiRoot
        width: window.width / AppSettings.uiScale
        height: window.height / AppSettings.uiScale
        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: AppSettings.uiScale
            yScale: AppSettings.uiScale
        }

        TitleBar {
            id: titleBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: window.titleBarHeight
            z: 20
            win: window
            model: library
            portrait: window.portrait
            onSearchCommitted: (text) => library.searchText = text
            onSettingsRequested: settingsPage.openAt(0)
        }

        Item {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBar.bottom
            anchors.bottom: parent.bottom

            Sidebar {
                id: sidebar
                visible: !window.portrait
                width: Theme.sidebarWidth
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                model: library
            }

            ChipsBar {
                id: chips
                visible: window.portrait
                height: 50
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                model: library
            }

            GridPage {
                id: gridPage
                anchors.left: window.portrait ? parent.left : sidebar.right
                anchors.right: parent.right
                anchors.top: window.portrait ? chips.bottom : parent.top
                anchors.bottom: parent.bottom
                model: library
                portrait: window.portrait
                zoomValue: titleBar.zoomValue
                onPhotoActivated: (photo) => viewer.openAt(photo.index)
                onDeleteRequested: (paths) => {
                    bulkDeleteDialog.pendingPaths = paths;
                    bulkDeleteDialog.open(
                        qsTr("删除 %1 张图片").arg(paths.length),
                        qsTr("选中的图片将移到回收站，可在文件管理器中恢复。"));
                }
            }
        }

        Viewer {
            id: viewer
            anchors.fill: parent
            z: 50
            win: window
            model: library
            portrait: window.portrait
            onDismissed: {
                gridPage.currentFlatIndex = viewer.lastClosedIndex;
                gridPage.forceActiveFocus();
            }
        }

        SettingsPage {
            id: settingsPage
            anchors.fill: parent
            z: 60
            win: window
            model: library
            onDismissed: gridPage.forceActiveFocus()
        }

        ConfirmDialog {
            id: bulkDeleteDialog
            anchors.fill: parent
            z: 70
            confirmText: qsTr("移到回收站")
            danger: true
            property var pendingPaths: []
            onAccepted: {
                const paths = pendingPaths;
                bulkDeleteDialog.pendingPaths = [];
                const removed = library.movePathsToTrash(paths);
                gridPage.clearSelection();
                if (removed < paths.length) {
                    window.showToast(qsTr("已移除 %1 张，%2 张失败")
                                     .arg(removed).arg(paths.length - removed));
                }
            }
        }

        // 全局轻提示（错误 / 打开失败）
        Rectangle {
            id: globalToast
            z: 90
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22
            height: 34
            width: globalToastText.implicitWidth + 28
            radius: 10
            color: Theme.ink
            visible: window.toastText.length > 0

            Text {
                id: globalToastText
                anchors.centerIn: parent
                text: window.toastText
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.surface
            }
        }
    }

    // 拖放图片打开
    DropArea {
        anchors.fill: parent
        onDropped: (drop) => {
            if (!drop.hasUrls || drop.urls.length === 0)
                return;
            const value = drop.urls[0].toString();
            if (!value.startsWith("file://"))
                return;
            window.openPath(decodeURIComponent(value.substring(7)));
        }
    }

    // 开发辅助：GALLERY_OPEN_INDEX=N 直接打开查看模式（配合截图）
    function devOpen(index: int, showInfo: bool): void {
        viewer.openAt(index);
        viewer.infoOpen = showInfo;
    }
    function devRequestDelete(index: int): void {
        viewer.openAt(index);
        viewer.requestDelete();
    }
    function devTrash(index: int): bool {
        return library.moveToTrash(index);
    }
    function devRotate(): void {
        viewer.devRotate();
    }
    function devSearch(text: string): void {
        library.searchText = text;
    }
    function devSort(mode: int): void {
        library.sortMode = mode;
    }
    function devFilter(id: string): void {
        library.filter = id;
    }
    function devFavorite(): void {
        library.toggleFavorite(viewer.currentIndex);
    }
    function devSelect(index: int): void {
        gridPage.currentFlatIndex = index;
    }
    function devZoom(value: real): void {
        titleBar.zoomValue = value;
    }
    function devSettings(page: int): void {
        settingsPage.openAt(page);
    }
    function devAccent(color: string): void {
        AppSettings.accentColor = color;
    }
    function devClearCache(): bool {
        return CacheController.clear();
    }
    function devScale(value: real): void {
        AppSettings.uiScale = Math.max(0.8, Math.min(1.6, value));
    }
    function devAppearance(mode: string): void {
        AppSettings.appearance = mode;
    }
    // ---- 设置持久化 ----
    Binding {
        target: Theme
        property: "accent"
        value: AppSettings.accentColor
    }
    Binding {
        target: Theme
        property: "dark"
        value: AppSettings.appearance === "dark"
               || (AppSettings.appearance === "system" && Appearance.systemDark)
    }
    Connections {
        target: library
        function onSortModeChanged() { AppSettings.sortMode = library.sortMode; }
    }
    Connections {
        target: titleBar
        function onZoomValueChanged() { AppSettings.thumbScale = titleBar.zoomValue; }
    }
    Connections {
        target: AppSettings
        function onThumbScaleChanged() { titleBar.zoomValue = AppSettings.thumbScale; }
    }
    Connections {
        target: AppSettings
        function onRecentDaysChanged() { library.recentDays = AppSettings.recentDays; }
    }
    Connections {
        target: library
        function onErrorOccurred(message) { window.showToast(message); }
    }
    Component.onCompleted: {
        if (AppSettings.winWidth >= 800 && AppSettings.winHeight >= 560) {
            window.width = AppSettings.winWidth;
            window.height = AppSettings.winHeight;
            window.normalWidth = window.width;
            window.normalHeight = window.height;
        }
        if (AppSettings.winMaximized)
            window.showMaximized();

        window.geometryReady = true;
        library.sortMode = AppSettings.sortMode;
        library.recentDays = AppSettings.recentDays;
        titleBar.zoomValue = AppSettings.thumbScale;
    }

    // ---- 界面缩放快捷键 ----
    Shortcut {
        sequence: "Ctrl+="
        context: Qt.ApplicationShortcut
        onActivated: AppSettings.adjustScale(0.1)
    }
    Shortcut {
        sequence: "Ctrl++"
        context: Qt.ApplicationShortcut
        onActivated: AppSettings.adjustScale(0.1)
    }
    Shortcut {
        sequence: "Ctrl+-"
        context: Qt.ApplicationShortcut
        onActivated: AppSettings.adjustScale(-0.1)
    }
    Shortcut {
        sequence: "Ctrl+0"
        context: Qt.ApplicationShortcut
        onActivated: AppSettings.uiScale = 1.0
    }

    // 无边框窗口：边缘可拖拽调整大小（Wayland 走 xdg_toplevel resize）
    MouseArea {
        width: 6
        height: parent.height - 6
        anchors.left: parent.left
        anchors.top: parent.top
        cursorShape: Qt.SizeHorCursor
        onPressed: window.startSystemResize(Qt.LeftEdge)
    }
    MouseArea {
        width: 6
        height: parent.height - 6
        anchors.right: parent.right
        anchors.top: parent.top
        cursorShape: Qt.SizeHorCursor
        onPressed: window.startSystemResize(Qt.RightEdge)
    }
    MouseArea {
        height: 6
        width: parent.width - 12
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: 6
        cursorShape: Qt.SizeVerCursor
        onPressed: window.startSystemResize(Qt.TopEdge)
    }
    MouseArea {
        height: 6
        width: parent.width - 12
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: 6
        cursorShape: Qt.SizeVerCursor
        onPressed: window.startSystemResize(Qt.BottomEdge)
    }
}
