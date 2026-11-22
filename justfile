# Gallery — 本地 x86 开发；部署到平板用 just deploy

# 构建（Debug）
b:
    cmake --preset linux-debug
    cmake --build --preset linux-debug -j 8

# 构建（Release）
br:
    cmake --preset linux-release
    cmake --build --preset linux-release -j 8

# 运行
r: b
    ./build/linux-debug/bin/gallery

# 离屏截图（CI / 无显示环境自检）
shot: b
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    GALLERY_SCREENSHOT=/tmp/gallery.png ./build/linux-debug/bin/gallery
    @echo "截图: /tmp/gallery.png"

# 同步源码到平板并设备端构建（arm64）
deploy:
    ./scripts/deploy-arm.sh

clean:
    rm -rf build
