# Gallery — Denial 平板原生图片查看器

Qt 6 / QML 实现的图片查看器，面向小米平板 5（Denial Wayland 合成器），
本地 x86 开发、设备端 arm64 编译。

## 现状

| 模块 | 状态 |
|---|---|
| 网格 | 左栏分类/文件夹、按日期分组、搜索、排序、缩略图大小滑块、竖屏 chips + 3 列、方向键/Enter 导航、拖放打开、长按多选删除 |
| 缩略图 | 256px 磁盘缓存（path+mtime+size 作 key），视频用 ffmpeg 取首帧 |
| 查看 | filmstrip、适应窗口/100% 双击切换、Ctrl+滚轮/捏合缩放、拖动平移、旋转、信息面板、收藏、GIF/WebP 动图、复制路径 |
| 删除 | 确认后移入 XDG 回收站（`.trashinfo`），绝不直接 unlink |
| 刷新 | QFileSystemWatcher 递归监听，400ms 防抖重扫 |
| 性能 | 边扫描边分批显示、行按需构建、静默比对不复制全库、按目录增量重扫、索引缓存二次启动秒开、缩略图缓存上限与清理 |
| 设置 | 全局色调、默认排序、缩略图大小、最近添加范围、缓存上限、亮/暗/跟随系统主题、整体缩放（Ctrl + = / - / 0）、缓存统计/清理/重建索引、恢复默认、关于 |
| 集成 | 打开方式（%F）、单实例转发、窗口几何记忆、应用图标、拖放打开 |
| 未做 | 撤销删除、裁剪写回、分享、幻灯片、视频播放、EXIF 深度解析、单元测试 |

## 构建 / 运行

```bash
cmake --preset linux-debug
cmake --build --preset linux-debug -j8
./build/linux-debug/bin/gallery
```

本地调试建议用测试 home（避免扫描真实的上十万张图）：

```bash
GALLERY_HOME=/tmp/gallery-home ./build/linux-debug/bin/gallery
```

设备端：

```bash
./scripts/deploy-arm.sh          # scp 到平板后在设备上 cmake + ninja
./scripts/package-pacman.sh      # 生成 Arch pacman 包（产物 dist/pacman/）
./scripts/package-pacman.sh -i   # 构建并安装（sudo pacman -U）
```

## 文档

- [docs/GALLERY.md](docs/GALLERY.md) — 设计规范（权威需求）
- [docs/CONTEXT.md](docs/CONTEXT.md) — 设备 / 环境实测事实与首期范围
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — 目录结构、开发用环境变量、交互速查
- [design/gallery-redesign.html](design/gallery-redesign.html) — 视觉设计稿
