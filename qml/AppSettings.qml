// SPDX-License-Identifier: GPL-3.0-or-later
// 用户设置单例：写入 ~/.config/<Org>/<App>.conf 的 [Gallery] 分组
pragma Singleton
import QtQuick
import QtCore

Settings {
    id: root
    category: "Gallery"

    // 全局色调（accent）
    property string accentColor: "#6d5bd0"
    // 网格缩略图大小滑块 0..1
    property real thumbScale: 0.3
    // 网格排序：0 时间 / 1 文件名 / 2 大小
    property int sortMode: 0
    // 外观：light / dark / system
    property string appearance: "system"
    // 缩略图缓存上限（MB，0 = 不限制）
    property int thumbCacheLimitMB: 1024
    // 最近添加范围（天）
    property int recentDays: 30
    // 窗口几何
    property int winWidth: 1440
    property int winHeight: 900
    property bool winMaximized: false
    // 整体界面缩放
    property real uiScale: 1.0

    function adjustScale(delta: real): void {
        uiScale = Math.max(0.8, Math.min(1.6, Math.round((uiScale + delta) * 10) / 10));
    }
}
