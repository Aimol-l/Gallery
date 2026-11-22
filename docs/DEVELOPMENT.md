# Gallery 开发指南（本地 x86）

> 先在 x86 上打磨，再同步到 Denial 平板（arm64）。环境事实见 `docs/CONTEXT.md`。

## 1. 目录结构

```text
include/gallery/<模块>/    # C++ 公共头文件（按模块分目录）
  core/photomodel.h        # 扫描 / 去重 / 分组 / 收藏 / 回收站
  core/filetypes.h         # 图片/视频后缀判定
  core/trash.h             # XDG 回收站
  core/thumbnailprovider.h # 256px 缩略图缓存 + 视频首帧
src/
  main.cpp
  core/*.cpp
qml/
  Main.qml  Theme.qml      # 窗口入口 + 主题单例
  shell/                   # 标题栏、窗口按钮
  grid/                    # 侧栏、chips、网格、缩略图
  viewer/                  # 查看模式、filmstrip、舞台、信息面板
  settings/                # 设置页（通用/外观/存储/关于）
  dialogs/                 # 应用内确认弹窗
packaging/                 # .desktop
scripts/deploy-arm.sh      # 同步到平板并设备端编译
```

QML 通过 `qt_add_qml_module` 注册为 `Gallery` 模块，`engine.loadFromModule("Gallery", "Main")` 加载；`qml/` 下文件按 glob 收集，新增文件不用改 CMake。

## 2. 构建 / 运行

```bash
cmake --preset linux-debug
cmake --build --preset linux-debug -j8
./build/linux-debug/bin/gallery

# Release
cmake --preset linux-release
cmake --build --preset linux-release -j8
```

`justfile` 提供 `just b` / `just r` / `just shot` / `just deploy`，本机未安装 `just` 时直接用上面的命令。

## 3. 本地测试数据

本机 `~/Pictures` 有几十万张图，直接跑会很慢。用假 home：

```bash
GALLERY_HOME=/tmp/gallery-home ./build/linux-debug/bin/gallery
```

`GALLERY_HOME` 下按真实结构放少量图片即可：

```text
/tmp/gallery-home/Pictures/{,Screenshots,Camera}
/tmp/gallery-home/{Downloads,Documents}
```

## 4. 开发用环境变量

| 变量 | 作用 |
|---|---|
| `GALLERY_HOME` | 替换扫描根目录的 home（测试夹具） |
| `GALLERY_SCREENSHOT=/tmp/x.png` | 渲染一帧后保存退出（配合 `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software`） |
| `GALLERY_SIZE=1000x1500` | 启动后调整窗口尺寸（验证竖屏） |
| `GALLERY_OPEN_INDEX=N` | 自动进入查看模式并定位到第 N 张 |
| `GALLERY_INFO=1` | 配合上一项，打开信息面板 |
| `GALLERY_ROTATE=1` | 打开后旋转 90° |
| `GALLERY_DELETE_INDEX=N` | 打开删除确认框 |
| `GALLERY_TRASH_INDEX=N` | 直接把第 N 张移到回收站 |
| `GALLERY_SEARCH=text` | 设置搜索词 |
| `GALLERY_SORT=0/1/2` | 时间 / 文件名 / 大小 |
| `GALLERY_FILTER=all\|recent\|favorites\|pictures\|screenshots\|camera\|downloads\|documents` | 切换侧栏筛选 |
| `GALLERY_FAVORITE=1` | 收藏当前查看的图片 |
| `GALLERY_SELECT=N` | 选中网格第 N 张（验证选中描边） |
| `GALLERY_ZOOM=0..1` | 设置缩略图大小滑块 |
| `GALLERY_SETTINGS=0..3` | 打开设置页（通用/外观/存储/关于） |
| `GALLERY_ACCENT=#rrggbb` | 设置全局色调 |
| `GALLERY_APPEARANCE=light\|dark\|system` | 设置亮色 / 暗色 / 跟随系统 |
| `GALLERY_CLEAR_CACHE=1` | 启动后清空缩略图缓存 |
| `GALLERY_SCALE=0.8..1.6` | 设置整体界面缩放 |
| `GALLERY_WHEEL_TEST=plain\|ctrl` | 向舞台/网格中心发送滚轮事件（滚轮切换 / Ctrl+滚轮缩放） |
| `GALLERY_KEY_TEST=1` | 向网格发送一次右方向键（验证键盘导航/焦点） |
| `GALLERY_LONGPRESS_TEST=1` | 向第一张缩略图注入长按（验证多选） |
| `GALLERY_LONGPRESS_CONFIRM=1` | 配合上一项，长按后点击顶部「删除」打开确认框 |
| `GALLERY_SCREENSHOT_DELAY=ms` | 截图前等待时间（默认 1900ms，测大目录扫描/缓存时可调大） |

离屏截图示例：

```bash
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
GALLERY_HOME=/tmp/gallery-home GALLERY_SCREENSHOT=/tmp/g.png \
./build/linux-debug/bin/gallery
```

> 普通重定向看不到 Qt 日志时，用 `script -qec "<cmd>" /dev/null` 跑，能拿到 stderr。

## 5. 数据与缓存

- 扫描根：`~/Pictures`（递归）、`~/Downloads`、`~/Documents`；`Pictures/Screenshots`、`Pictures/Camera` 为独立入口。
- 去重：每个文件只归到「最长路径前缀」的根，嵌套根只扫描一次。
- 缩略图：`~/.cache/denial/gallery/thumbs/<sha1>.png`（key = path|mtime|size），图片用 `QImageReader` 缩放解码，视频用 `ffmpeg -ss 1 ... -vf scale=256:-2`。默认上限 1GB，启动时在后台按最旧清理；设置里可改 512MB/1/2GB/不限。
- 索引缓存：`~/.cache/denial/gallery/index.bin`（紧凑二进制，含扫描根校验）。启动时先读缓存立即显示，再后台静默扫描；静默扫描用「路径 → 元数据签名」比对，不复制整库，文件集未变化不重建。
- 增量刷新：监听目录变化后只重扫变化的目录（递归）并合并，不再是每次全量扫描；单目录新增/删除实测约 5–6ms。
- 监听上限：最多同时 watch 8192 个目录（超过后深层目录不自动刷新，可在设置里手动「重新扫描」）。
- 收藏：`~/.config/denial/gallery-favorites.json`。
- 用户设置：`~/.config/denial/gallery.conf` 的 `[Gallery]` 分组（accentColor / appearance / thumbScale / sortMode / recentDays / thumbCacheLimitMB / uiScale / winWidth / winHeight / winMaximized）。
- 删除：移到 `~/.local/share/Trash/{files,info}`，写 `.trashinfo`（Path 百分号编码）。
- 目录监听：`QFileSystemWatcher` 监听扫描到的目录，400ms 防抖后全量重扫。

## 6. 主题

- 设置 → 外观提供「亮色 / 暗色 / 跟随系统」，保存为 `appearance`。
- `Theme.dark` 由 Main 绑定：`appearance == dark` 或 `system && Appearance.systemDark`；
  `Appearance`（C++ 单例）读取 `QStyleHints::colorScheme` 并监听系统变化。
- 所有颜色走 `Theme.*` 令牌；新增了 `stageBg` / `overlayBar` / `knobBorder` / `swatchBorder`。
  不要在 QML 里写死浅色背景，图片上的白色文字/黑色蒙层除外。
- 滚动条统一用 `AppScrollBar`，自动跟随明暗。

## 7. 大目录性能设计

几十万张图时，时间主要花在枚举/stat 和建列表上，处理方式：

| 机制 | 说明 |
|---|---|
| 边扫边显示 | 工作线程每 ~150ms 或 2000 个文件投递一批；主线程用 `beginInsertRows` 追加，**首屏约 150ms 就能看到照片**，不会等全量扫描 |
| 最终整理 | 扫描结束后按日期排序 + 分组，做一次 model reset（视图回到顶部） |
| 行按需构建 | `Row` 只存 `m_visible` 的区间，照片 `QVariantMap` 只在 `data()` 里为可见行生成，内存从「每张图一个 map」降到「每行 16 字节」 |
| 索引缓存 | 扫描完成写 `index.bin`；下次启动同步读入（27 万条约 0.35s release），立即显示，再后台静默刷新 |
| 静默比对 | 已有缓存时只建「路径 → 签名」表，扫描中逐条比对；不变的不复制，变化的少量条目在结束时合并 |
| 增量重扫 | 只重扫发生变化的目录并合并；影响超过 5 万条时回退到后台全量扫描 |
| 扫描根校验 | 缓存头记录扫描根，`GALLERY_HOME` 或目录变化时自动失效，避免显示错数据 |
| 监听上限 | 最多 8192 个目录 watch，超出后由设置页「重新扫描」兜底 |
| 筛选复用顺序 | 全部照片按当前排序方式排好一次（`m_order`），切换「最近添加/收藏/文件夹」只做 O(n) 过滤，不再每次重排 27 万条 |
| 截止时间只算一次 | 「最近添加」的 30 天截止时间在 rebuild 入口计算一次，避免对每张图调用 `QDateTime::currentDateTime()` |

实测（本机 x86_64，debug / release 混合，273,143 张）：

- 首次扫描：release ~2.0s / debug ~2.2–2.9s；扫描过程中持续可见
- 二次启动：索引缓存加载 ~0.35s（release），静默比对期间界面可正常使用
- 峰值内存：约 338MB（debug + offscreen 软件渲染；旧实现约 595MB）
- 增量刷新：单个目录约 5–6ms
- 切换筛选：「最近添加」~20ms、「收藏」~10ms、「Pictures」~40ms（首次启动建排序 ~150ms release）
- 缓存文件：索引 ~23MB；缩略图按上限自动清理

## 8. 打包（pacman）

```bash
./scripts/package-pacman.sh        # 只出包
./scripts/package-pacman.sh -i     # 出包并安装（makepkg -sif）
```

- 包名 `denial-gallery`，架构跟随构建机（平板 aarch64 / 本机 x86_64）。
- 脚本从当前源码生成 `dist/pacman/denial-gallery-<ver>.tar.gz`，复制并同步
  `packaging/arch/PKGBUILD` 的 `pkgver`，然后 `makepkg -sf`；产物在
  `dist/pacman/denial-gallery-<ver>-1-<arch>.pkg.tar.zst`。
- 依赖写在 PKGBUILD：`qt6-base qt6-declarative qt6-wayland qt6-svg qt6-imageformats
  ffmpeg hicolor-icon-theme`；`noto-fonts-cjk` 是可选依赖（中文字体）。
  构建需要 `base-devel + cmake ninja`；缺依赖时用 `-i`（`makepkg -s`）让 makepkg 安装。
- 安装内容：
  - `/usr/bin/gallery`
  - `/usr/share/applications/dev.denial.gallery.desktop`
  - `/usr/share/icons/hicolor/scalable/apps/dev.denial.gallery.svg`
  - `/usr/share/gallery/qml/Gallery/{qmldir,gallery.qmltypes}`（QML 模块根 qmldir；
    构建目录靠 `bin/qt.conf`，安装后靠这个目录 + `applicationDirPath()/../share` 导入路径）
- `.desktop` 的 `Exec` 会显式带上平板需要的
  `WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000`；如果设备用户 uid 或
  显示名不同，安装前改 `packaging/dev.denial.gallery.desktop`。
- 本地自用包使用 `sha256sums=('SKIP')`；若要发 AUR，请补真实 checksum、`url` 并生成 `.SRCINFO`。

## 9. 交互速查

| 操作 | 行为 |
|---|---|
| 单击缩略图 | 查看模式 |
| 双击图片 / 双击舞台 | 适应窗口 ↔ 100% |
| 捏合 / Ctrl+滚轮 | 缩放 10%–800% |
| 普通滚轮 | 网格快速滚动；查看模式切换上一张/下一张 |
| 上下滑动（触屏） | 查看模式切换上一张/下一张（适应窗口时） |
| Ctrl + = / - / 0 | 整体界面缩放 / 重置 |
| 网格 ← / → / ↑ / ↓ + Enter | 移动选中并打开 |
| 长按缩略图 | 进入多选（当前项选中）；多选时单击切换选中 |
| 多选顶部 | 显示「已选 N 张」「取消」；N > 0 时显示「删除」，确认后批量移到回收站 |
| 拖放文件到窗口 | 打开该图片（需在扫描根内） |
| 双击标题栏 | 最大化 / 还原 |
| 方向键 / Enter | 网格移动选中 / 打开 |
| 缩放后拖动 | 平移 |
| ← / → | 上一张 / 下一张 |
| Esc | 关信息面板 → 返回网格 |
| 底部删除 | 确认后移到回收站 |
| ⓘ | 信息面板（含收藏切换） |
| 缩放 > 适应窗口 | 底部显示百分比 + 拖动平移提示 |
| 标题栏 ⚙ | 打开设置（通用 / 外观 / 存储 / 关于） |

竖屏（高 > 宽）：左栏收成顶部 chips，网格 3 列，查看模式隐藏 filmstrip、底部栏只留图标。

## 7. 后续

- 裁剪（四角手柄 / 比例 / 覆盖或另存）——需先确认是否进首期。
- 分享、幻灯片、EXIF 深度解析。
- 视频播放（当前查看模式只显示占位）。
- 缩略图缓存容量上限与清理策略。
- 模型层单元测试（去重 / 分组 / 回收站路径）。
