# Gallery（Qt 版）— 开发上下文

> 本文档写给在本仓库工作的开发 agent / 开发者，汇总了所有**实测确认过的环境事实**、
> 平台约定、踩坑记录与首期范围。权威设计文档见下方「参考文档」。
>
> 更新时间：2026-11-21

---

## 0. 使命

为 Denial 平板（小米平板 5，自研 Wayland 合成器）写一个**原生图片查看器**：
网格浏览 + 沉浸式单图查看 + 基础编辑（裁剪/旋转）。技术栈：**Qt 6.12（C++/QML），
在设备上直接编译**。

## 1. 权威参考文档

| 文档 | 内容 |
|---|---|
| `docs/GALLERY.md`（本仓库） | 完整设计规范：界面结构、交互规范、格式、性能、验收标准。**需求以它为准** |
| `design/gallery-redesign.html` | 视觉设计稿（浏览器打开）：5 屏布局（横屏网格 / 查看 / 信息面板 / 裁剪 / 竖屏） |

规范要点速记：左栏（全部照片/最近添加/收藏 + 文件夹）+ 按日期分组的缩略图网格；
查看模式 = 左侧 138px filmstrip + 居中舞台 + 底部操作栏（上一张/缩小/放大/缩放状态/
旋转/裁剪/分享/删除/下一张）；双击在「适应窗口」↔「100%」间切换；捏合自由缩放；
信息面板 ⓘ 浮层；裁剪四角手柄 + 九宫格 + 比例 + 旋转；竖屏左栏收成顶部 chips、网格 3 列。

## 2. 目标设备与访问

| 项 | 值 |
|---|---|
| 设备 | 小米平板 5（nabu），aarch64，Arch Linux ARM |
| SSH | `ssh -i ~/.ssh/sanye_id_rsa user@192.168.31.252` |
| 显示 | Wayland，合成器是自研 **deniald**（不是 wlroots/Mutter） |
| 会话环境 | `WAYLAND_DISPLAY=wayland-1`，`XDG_RUNTIME_DIR=/run/user/1000` |
| 用户 | `user`（uid 1000） |

## 3. 工具链（全部在设备上，直接设备编译，无需交叉编译）

```
qt6-base/qt6-declarative/qt6-wayland/qt6-svg/qt6-multimedia(+ffmpeg后端)  6.12.0
qmake6 / cmake / ninja / g++ / make                                       可用
ffmpeg n9.0.2                                                             /usr/bin/ffmpeg
磁盘可用                                                                   54G
```

Qt 6.12 的 Wayland QPA 默认 **CSD（客户端自绘装饰）**——标题栏由应用自己画。
按设计稿自绘：左侧 logo +「图片查看器」+ 搜索 + 排序 + 缩略图大小滑块，
右侧最小化/最大化/关闭。窗口控制在 QML 里用 `Window.maximized`、`Window.close()` 等
即可（Wayland 下合成器支持 min/max/close 请求）。

## 4. 构建 / 运行 / 截图（实测命令）

代码同步：**设备上没有 rsync**，用 `scp -r` 或 `tar | ssh` 同步源码目录。

```bash
# 从本机同步到设备（工作目录约定：设备 ~/Gallery）
scp -i ~/.ssh/sanye_id_rsa -r /home/aimol/Documents/Workspace/Gallery/* user@192.168.31.252:~/Gallery/

# 在设备上（ssh 进去后）
cd ~/Gallery                       # 代码建议部署到设备上构建
cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build
# 运行（前台 ssh 跑会随 ssh 退出而死，建议 systemd-run 或 nohup+setsid）
systemd-run --user --scope -p MemoryMax=1G \
  env WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 \
  QT_QPA_PLATFORM=wayland ./build/gallery
```

> 注意：骨架里的 `CMakelists.txt` 拼写错误，请改名为 `CMakeLists.txt`。

```bash
# 截图（验证 UI 的主要手段）
env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 grim /tmp/shot.png
# 然后把图 scp 回来肉眼检查：
scp user@192.168.31.252:/tmp/shot.png .   # 物理分辨率 2560x1600（逻辑 1600x1000，scale 1.6）
```

- 应用退出别用 kill -9：Wayland 客户端正常退出才有干净状态。
- 桌面上已有测试目录可直接用（见 §5），不需要造测试图片；用 grim 截的图存到
  `~/Pictures/Screenshots/` 就能立刻进相册（真实端到端数据）。

## 5. 数据源（实测事实）

**Android（droidloom）直接写 Linux 目录**，没有独立挂载点，扫 Linux 文件系统即可：

| 目录 | 说明 | 实测状态 |
|---|---|---|
| `~/Pictures` | 主相册（**递归**） | 有内容 |
| `~/Pictures/Camera` | **Android 相机**（安卓直接写这里；`~/DCIM` 不存在） | 目录存在但当前为空 |
| `~/Pictures/Screenshots` | 截图（有内容，也是 grim 的输出去处） | 有内容 |
| `~/Pictures/Wallpapers`、`~/Pictures/截图` | 其它子目录 | 递归扫进来即可 |
| `~/Downloads` | 下载 | 有内容 |
| `~/Documents` | 文档 | 有内容 |

**关键去重规则**：这些根目录互相嵌套（Camera/Screenshots 在 Pictures 里面）。
递归扫描时一个文件必须只归到「路径最长匹配」的根，否则会在「全部照片」里重复计数。
（上一个 Flutter 原型就栽在这。）

## 6. 桌面集成

- `.desktop` 文件放 `~/.local/share/applications/`，桌面网格与启动器**自动发现**
  （同时保证 `Exec` 里的可执行路径存在）。
- `Exec` 建议包一层脚本设置环境：`Exec=env WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 /opt/gallery/bin/gallery`
  （Wayland 客户端从 .desktop 启动时这两个变量默认不在环境里）。
- `StartupWMClass` 设为可执行名或 `dev.denial.gallery`，保证窗口与图标正确分组。
- 合成器对 Wayland 窗口只画**细边框+阴影**（SSD），没有标题栏——标题栏必须自绘（见 §3）。
- 窗口最小化/最大化：xdg-toplevel 协议标准请求，Qt 直接支持。

## 7. 交互规范（必须遵守，来自 GALLERY.md §4）

| 操作 | 行为 |
|---|---|
| 单击缩略图 | 进入查看模式 |
| 双击图片 | 「适应窗口」↔「100%」切换 |
| 双指捏合 | 自由缩放 10%–800% |
| 缩放 > 适应窗口时拖动 | 平移 |
| 底部上一张/下一张按钮、左右方向键 | 按当前文件夹顺序切换 |
| 点击 filmstrip 项 | 切换并自动滚动跟随 |
| Esc | 查看/编辑 → 返回网格 |
| 删除 | **确认后移到 XDG 回收站**（`~/.local/share/Trash/{files,info}`），绝不直接 unlink |

## 8. 已知坑与既定决策（前一个 Flutter 原型的教训）

1. **文件归属去重**：见 §5 的最长路径前缀规则。
2. **缩略图缓存**：`~/.cache/denial/gallery/thumbs/<key>.png`，key = hash(path|mtime|size)；
   视频首帧用 `ffmpeg -ss 1 -i <file> -frames:v 1 -vf scale=256:-2 -y <out.png>`（8 秒超时）。
   生成并发限制 2，滚动时按需生成。
3. **格式支持**：JPEG/PNG/WebP/GIF/BMP 引擎直接解；**AVIF 首期跳过**（Qt 6.12 也不一定带，
   探测后再说）；SVG 可用 qt6-svg 但首期可延后；RAW 不做。
4. **大图内存**：Qt 的 QImage 加载 4032×3024 ≈ 46MB RGBA，峰值远低于 200MB 目标；
   查看器全图加载即可，首期不做区域解码。
5. **目录监听**：`QFileSystemWatcher`（递归）即可，Linux 下就是 inotify；
   400ms 防抖后再全量重扫（文件量级在千级，全扫 < 1s）。
6. **触摸/键盘**：真实触摸屏走 Wayland 正常；自动化测试可用 uinput 注入工具
   `/tmp/gt.py`（`tap/drag/hold`，坐标为逻辑 1600×1000）——注意脚本自身有已知问题
   （见 §9），以手动/截图验证为主。
7. **合成器特性**：窗口装饰只有边框；**没有全局菜单协议**；`grim` 截图可用；
   屏幕逻辑分辨率 1600×1000（横屏）/ 1000×1600（竖屏，分辨率跟随窗口自动切换）。

## 9. 首期范围（YAGNI）

**做**：网格（分组/文件夹/搜索/排序/缩略图滑块）、查看（缩放/平移/双击/旋转显示/
filmstrip/底部栏/信息面板）、删除进回收站、收藏（`~/.config/denial/gallery-favorites.json`）、
视频缩略图（ffmpeg）、竖屏适配。

**不做（后续）**：裁剪/写回、分享、幻灯片、AVIF/SVG、EXIF 深度解析（首期信息面板
展示尺寸/大小/mtime/路径即可）、RAW、云同步、人脸识别。

## 10. 验收标准

以 `docs/GALLERY.md` §9 为准（复制了一份在本文档末尾下方？——没有，直接看 GALLERY.md）。
核心自查：

- [ ] 网格能列出真实截图与相机目录，日期分组正确，无重复计数
- [ ] 缩略图生成且缓存命中（第二次打开秒出）
- [ ] 查看：双击/捏合/平移/旋转/切换全部正常，Esc 返回
- [ ] 删除进回收站而非 unlink
- [ ] 竖屏：chips + 3 列
- [ ] grim 截图确认视觉与设计稿一致

## 11. 代码位置建议

```
CMakeLists.txt          # 注意：现有骨架文件名拼写是 CMakelists.txt，改名 CMakeLists.txt
src/main.cpp            # QGuiApplication + QQuickView（或 QQmlApplicationEngine）
qml/Main.qml            # 标题栏三段式 + 网格/查看 Stack
qml/GridPage.qml        # 左栏 + 日期分组网格（GridView，cellSize 由滑块驱动）
qml/ViewerPage.qml      # filmstrip + Flickable/TransformedContent + 底部操作栏
qml/InfoPanel.qml
src/library.h/.cpp      # 扫描/watch/收藏/分组（QAbstractListModel 给网格用）
src/thumbnails.h/.cpp   # 缩略图生成与缓存（QThreadPool 限并发 2 + QProcess 调 ffmpeg）
tests/                  # 模型层单元测试（分组/去重/回收站路径）
```
