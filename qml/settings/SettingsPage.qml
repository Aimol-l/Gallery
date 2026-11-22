// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Gallery

// 全窗口设置页：左导航 + 右侧卡片内容
Item {
    id: root
    required property Window win
    required property PhotoModel model

    property bool opened: false
    property int pageIndex: 0
    readonly property bool portrait: height > width
    readonly property var accentColors: [
        "#6d5bd0", "#3481fa", "#2f9e6e", "#d18a1f",
        "#e05c7b", "#c9483f", "#7a5c3e", "#4a4f5c"
    ]
    readonly property var navItems: [
        { icon: "⚙", label: qsTr("通用") },
        { icon: "◐", label: qsTr("外观") },
        { icon: "▤", label: qsTr("存储") },
        { icon: "ⓘ", label: qsTr("关于") }
    ]

    visible: opened
    focus: opened

    signal dismissed()

    function openAt(index: int): void {
        root.pageIndex = Math.max(0, Math.min(root.navItems.length - 1, index));
        root.opened = true;
        root.forceActiveFocus();
        if (root.pageIndex === 2)
            CacheController.refresh();
    }
    function close(): void {
        if (!root.opened)
            return;
        root.opened = false;
        root.dismissed();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    // ---- 顶部栏 ----
    Rectangle {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 54
        color: Theme.surface
        z: 2

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
        }

        WindowButton {
            id: backButton
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            glyph: "←"
            onClicked: root.close()
        }
        Text {
            anchors.left: backButton.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("设置")
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: Theme.ink
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

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

    // ---- 左导航 ----
    Rectangle {
        id: nav
        anchors.left: parent.left
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        width: root.portrait ? 168 : 210
        color: Theme.sidebar

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.line
        }

        Column {
            id: navList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            topPadding: 4
            spacing: 2

            Repeater {
                model: root.navItems
                delegate: Rectangle {
                    id: navItem
                    required property var modelData
                    required property int index
                    readonly property bool active: root.pageIndex === index

                    width: navList.width
                    height: 40
                    radius: 8
                    color: active ? Theme.surface
                                  : (navMouse.containsMouse ? Theme.hover : "transparent")
                    border.width: active ? 1 : 0
                    border.color: Theme.line

                    Text {
                        id: navIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        text: navItem.modelData.icon
                        font.pixelSize: 14
                        color: navItem.active ? Theme.accent : Theme.faint
                    }
                    Text {
                        anchors.left: navIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: navItem.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: navItem.active ? Font.DemiBold : Font.Normal
                        color: navItem.active ? Theme.ink : Theme.muted
                    }
                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.pageIndex = navItem.index;
                            if (navItem.index === 2)
                                CacheController.refresh();
                        }
                    }
                }
            }
        }
    }

    // ---- 内容 ----
    Flickable {
        id: flick
        anchors.left: nav.right
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 48
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: AppScrollBar {}

        Column {
            id: contentColumn
            x: 28
            y: 24
            width: flick.width - 56
            spacing: 16

            // ---- 通用 ----
            Column {
                width: contentColumn.width
                spacing: 16
                visible: root.pageIndex === 0

                SettingsCard {
                    title: qsTr("浏览")

                    SettingRow {
                        label: qsTr("默认排序")
                        description: qsTr("网格内缩略图的排列顺序")

                        Row {
                            spacing: 6
                            Repeater {
                                model: [qsTr("时间新→旧"), qsTr("文件名"), qsTr("大小")]
                                delegate: Rectangle {
                                    id: sortChip
                                    required property var modelData
                                    required property int index
                                    readonly property bool active: root.model.sortMode === index

                                    width: 88
                                    height: 32
                                    radius: 8
                                    color: active ? Theme.accentSoft
                                                  : (sortMouse.containsMouse ? Theme.hover
                                                                             : Theme.surface)
                                    border.width: 1
                                    border.color: active ? Theme.accent : Theme.line

                                    Text {
                                        anchors.centerIn: parent
                                        text: sortChip.modelData
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: sortChip.active ? Theme.accent : Theme.muted
                                    }
                                    MouseArea {
                                        id: sortMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.model.sortMode = sortChip.index
                                    }
                                }
                            }
                        }
                    }

                    SettingRow {
                        label: qsTr("缩略图大小")
                        description: qsTr("网格中缩略图的默认大小")

                        SettingsSlider {
                            value: AppSettings.thumbScale
                            onMoved: (value) => AppSettings.thumbScale = value
                        }
                    }

                    SettingRow {
                        label: qsTr("界面缩放")
                        description: qsTr("快捷键 Ctrl + = / Ctrl + -，Ctrl + 0 重置")
                        Row {
                            spacing: 6

                            SettingsButton {
                                text: "−"
                                onClicked: AppSettings.adjustScale(-0.1)
                            }
                            Text {
                                width: 52
                                height: 32
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Math.round(AppSettings.uiScale * 100) + "%"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.muted
                            }
                            SettingsButton {
                                text: "+"
                                onClicked: AppSettings.adjustScale(0.1)
                            }
                            SettingsButton {
                                text: qsTr("重置")
                                onClicked: AppSettings.uiScale = 1.0
                            }
                        }
                    }
                    SettingRow {
                        label: qsTr("最近添加范围")
                        description: qsTr("侧栏「最近添加」使用的时间范围")

                        Row {
                            spacing: 6

                            Repeater {
                                model: [7, 30, 90, 365]
                                delegate: Rectangle {
                                    id: recentChip
                                    required property int modelData
                                    readonly property bool active:
                                        AppSettings.recentDays === modelData

                                    width: 72
                                    height: 32
                                    radius: 8
                                    color: active ? Theme.accentSoft
                                                  : (recentMouse.containsMouse ? Theme.hover
                                                                             : Theme.surface)
                                    border.width: 1
                                    border.color: active ? Theme.accent : Theme.line

                                    Text {
                                        anchors.centerIn: parent
                                        text: recentChip.modelData + qsTr(" 天")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: recentChip.active ? Theme.accent : Theme.muted
                                    }
                                    MouseArea {
                                        id: recentMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: AppSettings.recentDays = recentChip.modelData
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("数据源")

                    SettingRow {
                        label: qsTr("扫描目录")
                        description: qsTr("~/Pictures（递归）· ~/Downloads · ~/Documents")
                    }
                    SettingRow {
                        label: qsTr("去重规则")
                        description: qsTr("同一文件只归到最长路径匹配的文件夹，不重复计数")
                    }
                }

                SettingsCard {
                    title: qsTr("重置")

                    SettingRow {
                        label: qsTr("恢复默认设置")
                        description: qsTr("主题、色调、界面缩放、排序、最近范围、缓存上限恢复默认")

                        SettingsButton {
                            text: qsTr("恢复默认")
                            danger: true
                            onClicked: resetDialog.open(
                                qsTr("恢复默认设置"),
                                qsTr("将恢复外观、缩放、排序和缓存设置，不会删除图片或缓存文件。"))
                        }
                    }
                }
            }

            // ---- 外观 ----
            Column {
                width: contentColumn.width
                spacing: 16
                visible: root.pageIndex === 1

                SettingsCard {
                    title: qsTr("主题")

                    Text {
                        width: parent.width
                        text: qsTr("亮色 / 暗色 / 跟随系统（读取桌面配色）")
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.faint
                        bottomPadding: 10
                    }

                    Row {
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "light", label: qsTr("亮色") },
                                { id: "dark", label: qsTr("暗色") },
                                { id: "system", label: qsTr("跟随系统") },
                            ]

                            delegate: Rectangle {
                                id: themeChip
                                required property var modelData
                                readonly property bool active:
                                    AppSettings.appearance === modelData.id

                                width: 96
                                height: 36
                                radius: 8
                                color: active ? Theme.accent
                                              : (themeMouse.containsMouse ? Theme.hover
                                                                         : Theme.surface)
                                border.width: 1
                                border.color: active ? Theme.accent : Theme.line

                                Text {
                                    anchors.centerIn: parent
                                    text: themeChip.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: themeChip.active ? "#ffffff" : Theme.muted
                                }
                                MouseArea {
                                    id: themeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: AppSettings.appearance = themeChip.modelData.id
                                }
                            }
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("全局色调")

                    Text {
                        width: parent.width
                        text: qsTr("选中态、按钮、收藏星标等强调色会立即跟随。")
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.faint
                        bottomPadding: 10
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.accentColors
                            delegate: Item {
                                id: swatch
                                required property var modelData
                                readonly property bool selected:
                                    AppSettings.accentColor.toLowerCase() === modelData.toLowerCase()

                                width: 52
                                height: 52

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 42
                                    height: 42
                                    radius: 21
                                    color: swatch.modelData
                                    border.width: 1
                                    border.color: Theme.swatchBorder
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 26
                                    color: "transparent"
                                    border.width: swatch.selected ? 2 : 0
                                    border.color: Theme.accent
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: swatch.selected
                                    text: "✓"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: AppSettings.accentColor = swatch.modelData
                                }
                            }
                        }
                    }

                    SettingRow {
                        label: qsTr("当前色调")
                        description: AppSettings.accentColor

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 6
                            color: Theme.accent
                            border.width: 1
                            border.color: Theme.swatchBorder
                        }
                    }
                }
            }

            // ---- 存储 ----
            Column {
                width: contentColumn.width
                spacing: 16
                visible: root.pageIndex === 2

                SettingsCard {
                    title: qsTr("缩略图缓存")

                    SettingRow {
                        label: qsTr("缓存目录")
                        description: CacheController.path
                    }
                    SettingRow {
                        label: qsTr("占用空间")
                        description: CacheController.files + qsTr(" 个文件 · ") + CacheController.sizeText
                    }
                    SettingRow {
                        label: qsTr("索引缓存")
                        description: CacheController.indexPath + qsTr(" · ")
                                     + CacheController.indexSizeText
                    }
                    SettingRow {
                        label: qsTr("缓存上限")
                        description: qsTr("超过上限时自动清理最旧的缩略图")

                        Row {
                            spacing: 6

                            Repeater {
                                model: [
                                    { value: 512, label: "512 MB" },
                                    { value: 1024, label: "1 GB" },
                                    { value: 2048, label: "2 GB" },
                                    { value: 0, label: qsTr("不限") },
                                ]
                                delegate: Rectangle {
                                    id: limitChip
                                    required property var modelData
                                    readonly property bool active:
                                        AppSettings.thumbCacheLimitMB === modelData.value

                                    width: 74
                                    height: 32
                                    radius: 8
                                    color: active ? Theme.accentSoft
                                                  : (limitMouse.containsMouse ? Theme.hover
                                                                             : Theme.surface)
                                    border.width: 1
                                    border.color: active ? Theme.accent : Theme.line

                                    Text {
                                        anchors.centerIn: parent
                                        text: limitChip.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: limitChip.active ? Theme.accent : Theme.muted
                                    }
                                    MouseArea {
                                        id: limitMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            AppSettings.thumbCacheLimitMB = limitChip.modelData.value;
                                            if (limitChip.modelData.value > 0)
                                                CacheController.pruneToLimit(limitChip.modelData.value);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SettingRow {
                        label: qsTr("重新扫描")
                        description: qsTr("手动刷新图库（深层目录超出监听上限时使用）")

                        SettingsButton {
                            text: qsTr("重新扫描")
                            onClicked: root.model.scan()
                        }
                    }
                    SettingRow {
                        label: qsTr("清理缓存")
                        description: qsTr("删除已生成的缩略图，下次浏览时重新生成")

                        Row {
                            spacing: 8
                            SettingsButton {
                                text: qsTr("刷新")
                                onClicked: CacheController.refresh()
                            }
                            SettingsButton {
                                text: qsTr("清空缓存")
                                danger: true
                                onClicked: clearDialog.open(
                                    qsTr("清空缩略图缓存"),
                                    qsTr("将删除 %1 个缓存文件，下次浏览时自动重新生成。")
                                        .arg(CacheController.files))
                            }
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("回收站")

                    SettingRow {
                        label: qsTr("删除位置")
                        description: qsTr("~/.local/share/Trash（遵循 XDG 规范，不会直接删除文件）")
                    }
                }
            }

            // ---- 关于 ----
            Column {
                width: contentColumn.width
                spacing: 16
                visible: root.pageIndex === 3

                SettingsCard {
                    title: qsTr("Gallery")

                    SettingRow {
                        label: qsTr("版本")
                        description: Qt.application.version
                    }
                    SettingRow {
                        label: qsTr("技术栈")
                        description: qsTr("Qt 6 · QML · C++20")
                    }
                    SettingRow {
                        label: qsTr("定位")
                        description: qsTr("Denial 平板原生图片查看器")
                    }
                    SettingRow {
                        label: qsTr("设计规范")
                        description: qsTr("docs/GALLERY.md")
                    }
                }

                SettingsCard {
                    title: qsTr("快捷键")

                    SettingRow {
                        label: qsTr("← / →")
                        description: qsTr("查看模式切换上一张 / 下一张")
                    }
                    SettingRow {
                        label: qsTr("Esc")
                        description: qsTr("返回网格 / 关闭信息面板")
                    }
                    SettingRow {
                        label: qsTr("双击图片")
                        description: qsTr("适应窗口 ↔ 100%")
                    }
                    SettingRow {
                        label: qsTr("滚轮")
                        description: qsTr("网格滚动；查看模式切换上一张 / 下一张")
                    }
                    SettingRow {
                        label: qsTr("Ctrl + 滚轮")
                        description: qsTr("查看模式缩放图片")
                    }
                    SettingRow {
                        label: qsTr("Ctrl + = / - / 0")
                        description: qsTr("整体界面放大 / 缩小 / 重置")
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: clearDialog
        anchors.fill: parent
        confirmText: qsTr("清空缓存")
        danger: true
        onAccepted: CacheController.clear()
    }

    ConfirmDialog {
        id: resetDialog
        anchors.fill: parent
        confirmText: qsTr("恢复默认")
        danger: true
        onAccepted: {
            AppSettings.accentColor = "#6d5bd0";
            AppSettings.appearance = "system";
            AppSettings.thumbScale = 0.3;
            AppSettings.sortMode = 0;
            AppSettings.recentDays = 30;
            AppSettings.thumbCacheLimitMB = 1024;
            AppSettings.uiScale = 1.0;
        }
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: root.opened
        onActivated: {
            if (clearDialog.opened)
                clearDialog.reject();
            else
                root.close();
        }
    }
}
