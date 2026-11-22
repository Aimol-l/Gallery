// SPDX-License-Identifier: GPL-3.0-or-later
// 主题色板单例 —— 取值来自 design/gallery-redesign.html
pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: "Noto Sans CJK SC"

    // 亮/暗色由 Main 依据设置与系统配色绑定
    property bool dark: false

    // 基础色（accent 由设置页驱动，可在运行时修改）
    property color accent: "#6d5bd0"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.10)
    readonly property color ink: dark ? "#e9eaee" : "#1c1c1f"
    readonly property color muted: dark ? "#a6abb6" : "#5f6470"
    readonly property color faint: dark ? "#7f8492" : "#9aa0ad"
    readonly property color line: dark ? "#2b2e37" : "#e4e6ec"
    readonly property color bg: dark ? "#131418" : "#f6f7f9"
    readonly property color surface: dark ? "#1d1f26" : "#ffffff"
    readonly property color sidebar: dark ? "#181a20" : "#f7f8fa"
    readonly property color hover: dark ? "#262a33" : "#f1f2f5"
    readonly property color sunken: dark ? "#2d313b" : "#e9ebef"
    readonly property color danger: dark ? "#e5675d" : "#c9483f"

    // 查看器 / 浮层
    readonly property color stageBg: dark ? "#0f1014" : "#eceef2"
    readonly property color overlayBar: dark ? "#f2181a20" : "#f7ffffff"
    readonly property color knobBorder: dark ? "#3a3e48" : "#c9ccd4"
    readonly property color swatchBorder: dark ? "#40ffffff" : "#22000000"

    // 尺寸
    readonly property int titleBarHeight: 52
    readonly property int sidebarWidth: 208
    readonly property int radius: 8
    readonly property int radiusSmall: 6
    readonly property int gap: 8
    readonly property int pagePadding: 22
}
