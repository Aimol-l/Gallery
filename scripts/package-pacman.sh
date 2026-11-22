#!/usr/bin/env bash
# 从当前源码目录生成 Arch pacman 包（产物在 dist/pacman/）。
#
# 用法:
#   ./scripts/package-pacman.sh            # 只构建 .pkg.tar.zst
#   ./scripts/package-pacman.sh --install  # 构建并安装（会调用 sudo pacman -U）
#
# 说明:
#   - 包架构跟随当前机器（平板 aarch64 / 本机 x86_64）。
#   - 需要 base-devel + cmake ninja；缺依赖时 makepkg -s 会尝试通过 pacman 安装。
#   - 源码通过本地 tar 包提供，sha256sums 为 SKIP（仅供本地/设备自用，不上 AUR）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGNAME="denial-gallery"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,14p' "${BASH_SOURCE[0]}"
    exit 0
fi

INSTALL=0
for arg in "$@"; do
    case "$arg" in
        -i|--install) INSTALL=1 ;;
        *) echo "未知参数: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$(id -u)" -eq 0 ]]; then
    echo "不要以 root 运行 makepkg。" >&2
    exit 1
fi
for tool in makepkg cmake ninja tar sed; do
    command -v "$tool" >/dev/null 2>&1 || { echo "缺少工具: $tool" >&2; exit 1; }
done

VERSION="$(sed -n 's/^project(Gallery VERSION \([0-9][0-9.]*\).*/\1/p' "$ROOT/CMakeLists.txt")"
if [[ -z "$VERSION" ]]; then
    echo "无法从 CMakeLists.txt 读取版本号" >&2
    exit 1
fi

WORK="$ROOT/dist/pacman"
STAGE="$WORK/$PKGNAME-$VERSION"
TARBALL="$WORK/$PKGNAME-$VERSION.tar.gz"

echo "==> 版本: $VERSION"
rm -rf "$WORK"
mkdir -p "$STAGE/"

echo "==> 收集源码 -> $STAGE"
tar -C "$ROOT" \
    --exclude=./build \
    --exclude=./dist \
    --exclude=./.git \
    --exclude='*.pkg.tar.*' \
    --exclude='./CMakeUserPresets.json' \
    -cf - . | tar -C "$STAGE" -xf -

echo "==> 生成源码包 $TARBALL"
tar -C "$WORK" -czf "$TARBALL" "$PKGNAME-$VERSION"
rm -rf "$STAGE"

echo "==> 生成 PKGBUILD"
cp "$ROOT/packaging/arch/PKGBUILD" "$WORK/PKGBUILD"
sed -i "s/^pkgver=.*/pkgver=$VERSION/" "$WORK/PKGBUILD"

cd "$WORK"
echo "==> makepkg"
if [[ "$INSTALL" -eq 1 ]]; then
    makepkg -sif --noconfirm
else
    makepkg -sf --noconfirm
fi

PACKAGE="$(ls -1t "$WORK"/"$PKGNAME"-"$VERSION"-*.pkg.tar.* 2>/dev/null | head -n1 || true)"
if [[ -z "$PACKAGE" ]]; then
    echo "未找到构建产物" >&2
    exit 1
fi

echo
echo "✅ 打包完成: $PACKAGE"
if [[ "$INSTALL" -eq 0 ]]; then
    echo "   安装: sudo pacman -U \"$PACKAGE\""
fi
