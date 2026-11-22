// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Gallery

// 图片舞台：适应窗口 / 100% 双击切换、捏合缩放 10%–800%、放大后拖动平移、旋转显示。
Item {
    id: stage
    property var photo
    property bool portrait: false

    // -1 上一张 / +1 下一张（滚轮、上下滑动）
    signal stepRequested(int direction)

    property int rotationSteps: 0
    property bool fitMode: true
    property real manualZoom: 1
    property real panX: 0
    property real panY: 0

    readonly property real marginH: portrait ? 20 : 88
    readonly property real marginV: portrait ? 16 : 28
    readonly property bool isVideo: photo ? photo.video === true : false
    readonly property bool animated: {
        const name = (photo && photo.name)
            ? photo.name.toLowerCase()
            : loadedPath.toLowerCase();
        return name.endsWith(".gif") || name.endsWith(".webp");
    }
    readonly property int activeStatus: animated ? anim.status : image.status
    readonly property real naturalW: activeStatus === Image.Ready
        ? (animated ? anim.implicitWidth : image.implicitWidth) : 0
    readonly property real naturalH: activeStatus === Image.Ready
        ? (animated ? anim.implicitHeight : image.implicitHeight) : 0
    readonly property bool rotated: rotationSteps % 2 !== 0
    readonly property real effectiveW: rotated ? naturalH : naturalW
    readonly property real effectiveH: rotated ? naturalW : naturalH

    readonly property real fitZoom: {
        if (effectiveW <= 0 || effectiveH <= 0)
            return 1;
        const availableW = Math.max(1, width - marginH);
        const availableH = Math.max(1, height - marginV);
        return Math.min(1, availableW / effectiveW, availableH / effectiveH);
    }
    readonly property real zoom: fitMode ? fitZoom : manualZoom
    readonly property bool isFit: fitMode
    readonly property real viewW: rotated ? naturalH * zoom : naturalW * zoom
    readonly property real viewH: rotated ? naturalW * zoom : naturalH * zoom
    readonly property bool canPan: viewW > width + 1 || viewH > height + 1
    readonly property int zoomPercent: Math.round(zoom * 100)

    function clamp(v, lo, hi): real {
        return Math.max(lo, Math.min(hi, v));
    }
    function clampPan(): void {
        const maxX = Math.max(0, (viewW - width) / 2);
        const maxY = Math.max(0, (viewH - height) / 2);
        panX = clamp(panX, -maxX, maxX);
        panY = clamp(panY, -maxY, maxY);
    }
    function resetView(): void {
        fitMode = true;
        manualZoom = 1;
        rotationSteps = 0;
        panX = 0;
        panY = 0;
    }
    function zoomTo(value: real): void {
        fitMode = false;
        manualZoom = clamp(value, 0.1, 8);
        clampPan();
    }
    // Ctrl+滚轮围绕光标缩放（旋转后简化为中心缩放）
    function zoomAt(factor: real, px: real, py: real): void {
        if (rotationSteps % 4 !== 0 || isVideo) {
            zoomTo(zoom * factor);
            return;
        }
        const oldZoom = zoom;
        const newZoom = clamp(oldZoom * factor, 0.1, 8);
        if (newZoom === oldZoom)
            return;
        const cx = width / 2;
        const cy = height / 2;
        const ratio = newZoom / oldZoom;
        panX = px - cx - (px - cx - panX) * ratio;
        panY = py - cy - (py - cy - panY) * ratio;
        fitMode = false;
        manualZoom = newZoom;
        clampPan();
    }
    function zoomIn(): void { zoomTo(zoom * 1.25); }
    function zoomOut(): void { zoomTo(zoom / 1.25); }
    function toggleFit(): void {
        if (fitMode) {
            fitMode = false;
            manualZoom = 1;
        } else {
            fitMode = true;
        }
        panX = 0;
        panY = 0;
    }
    function rotate(): void {
        rotationSteps = (rotationSteps + 1) % 4;
        panX = 0;
        panY = 0;
    }

    // revision 变化（如收藏）会重建 photo 对象，只有路径真的变了才重置视图
    property string loadedPath: ""
    onPhotoChanged: {
        const path = photo && photo.path ? photo.path : "";
        if (path === loadedPath)
            return;
        loadedPath = path;
        resetView();
        image.source = "";
        anim.source = "";
        anim.playing = false;
        if (path && !photo.video) {
            // 不能依赖 animated 绑定，它可能在本回调之后才刷新
            const lower = path.toLowerCase();
            const isAnimated = lower.endsWith(".gif") || lower.endsWith(".webp");
            if (isAnimated) {
                anim.source = "file://" + path;
                anim.playing = true;
            } else {
                image.source = "file://" + path;
            }
        }
    }
    onWidthChanged: clampPan()
    onHeightChanged: clampPan()
    onZoomChanged: clampPan()
    onRotationStepsChanged: clampPan()

    Rectangle {
        anchors.fill: parent
        color: Theme.stageBg
    }

    Rectangle {
        id: holder
        width: Math.max(1, stage.naturalW * stage.zoom)
        height: Math.max(1, stage.naturalH * stage.zoom)
        x: (stage.width - width) / 2 + stage.panX
        y: (stage.height - height) / 2 + stage.panY
        rotation: stage.rotationSteps * 90
        transformOrigin: Item.Center
        visible: !stage.isVideo && stage.activeStatus === Image.Ready
        radius: 6
        clip: true
        color: "transparent"

        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Image {
            id: image
            anchors.fill: parent
            visible: !stage.animated
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: true
            autoTransform: true   // 应用 EXIF 方向，与网格缩略图保持一致
        }

        AnimatedImage {
            id: anim
            anchors.fill: parent
            visible: stage.animated
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            autoTransform: true
        }
    }

    // 视频：首期只显示占位（后续接播放）
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: stage.isVideo
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "▶"
            font.pixelSize: 40
            color: Theme.muted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("视频预览暂未支持")
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.muted
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !stage.isVideo && stage.activeStatus === Image.Loading
        text: qsTr("载入中…")
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.muted
    }
    Text {
        anchors.centerIn: parent
        visible: !stage.isVideo && stage.activeStatus === Image.Error
        text: qsTr("无法打开这张图片")
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.danger
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: stage.toggleFit()
    }

    DragHandler {
        id: drag
        target: null
        enabled: stage.canPan
        property real startX: 0
        property real startY: 0
        onActiveChanged: {
            if (active) {
                startX = stage.panX;
                startY = stage.panY;
            }
        }
        onTranslationChanged: {
            if (!active)
                return;
            stage.panX = startX + translation.x;
            stage.panY = startY + translation.y;
        }
    }

    // 适应窗口时上下滑动切换图片（放大后由 DragHandler 负责平移）
    DragHandler {
        id: swipeHandler
        target: null
        enabled: !stage.canPan
        property real lastX: 0
        property real lastY: 0
        onActiveChanged: {
            if (active) {
                lastX = 0;
                lastY = 0;
            } else if (Math.abs(lastY) > 70 && Math.abs(lastY) > Math.abs(lastX)) {
                stage.stepRequested(lastY < 0 ? 1 : -1);
            }
        }
        onTranslationChanged: {
            if (active) {
                lastX = translation.x;
                lastY = translation.y;
            }
        }
    }

    PinchHandler {
        id: pinch
        target: null
        property real startZoom: 1
        onActiveChanged: {
            if (active)
                startZoom = stage.zoom;
        }
        onScaleChanged: {
            if (active)
                stage.zoomTo(startZoom * scale);
        }
    }

    // 滚轮：Ctrl + 滚轮缩放；普通滚轮切换上一张/下一张
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            if (wheel.modifiers & Qt.ControlModifier) {
                if (!stage.isVideo)
                    stage.zoomAt(wheel.angleDelta.y > 0 ? 1.15 : 1 / 1.15,
                             wheel.x, wheel.y);
                wheel.accepted = true;
                return;
            }
            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y
                                                   : wheel.pixelDelta.y;
            if (delta !== 0) {
                stage.stepRequested(delta > 0 ? -1 : 1);
                wheel.accepted = true;
            }
        }
    }
}
