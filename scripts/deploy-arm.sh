#!/usr/bin/env bash
# 同步源码到 Denial 平板并直接设备编译（无 rsync，用 scp -r）
set -euo pipefail

HOST="${GALLERY_HOST:-user@192.168.31.252}"
KEY="${GALLERY_SSH_KEY:-$HOME/.ssh/sanye_id_rsa}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SSH=(ssh -i "$KEY" "$HOST")
SCP=(scp -i "$KEY" -r)

echo "==> 同步源码到 ${HOST}:~/Gallery"
"${SSH[@]}" 'mkdir -p ~/Gallery'
"${SCP[@]}" \
    "$SOURCE_DIR/CMakeLists.txt" \
    "$SOURCE_DIR/qml" \
    "$SOURCE_DIR/src" \
    "$SOURCE_DIR/include" \
    "$SOURCE_DIR/packaging" \
    "${HOST}:~/Gallery/"

echo "==> 设备端构建"
"${SSH[@]}" 'cd ~/Gallery && cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release && ninja -C build'

echo "==> 完成：设备上 ~/Gallery/build/bin/gallery"
