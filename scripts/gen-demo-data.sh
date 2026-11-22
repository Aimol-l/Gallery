#!/usr/bin/env bash
# 生成 README 截图用的演示图片库（纯 ImageMagick 绘制，无外部素材）。
#
# 用法:
#   ./scripts/gen-demo-data.sh [输出目录]      # 默认 assets/demo
#
# 说明:
#   - 输出结构模拟真实 home：Pictures/{Camera,Screenshots}、Downloads、Documents。
#   - 截图时把它当 GALLERY_HOME 用：
#       GALLERY_HOME=assets/demo ./build/linux-release/bin/gallery
#   - 文件 mtime 人为错开，让网格出现「昨天 / 3 天前 / 上周」日期分组。
#   - 用它截图时建议把 XDG_CACHE_HOME / XDG_CONFIG_HOME 指到临时目录，
#     避免演示数据写进真实缓存与用户设置。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/assets/demo}"
SIZE=1600x1200

for dir in Pictures/Camera Pictures/Screenshots Downloads Documents; do
    mkdir -p "$OUT/$dir"
done

# 日落山脉：天空渐变 + 太阳 + 三层剪影
sunset() { # 输出 天空顶 天空底 太阳 远山 中山 近山
    magick -size "$SIZE" "gradient:$2-$3" \
        -fill "$4" -draw 'circle 1180,330 1180,520' \
        -fill "$5" -draw 'polygon 0,760 300,620 560,720 820,600 1080,740 1350,640 1600,780 1600,1200 0,1200' \
        -fill "$6" -draw 'polygon 0,900 260,800 520,900 760,820 1040,920 1280,840 1600,960 1600,1200 0,1200' \
        -fill "$7" -draw 'polygon 0,1080 400,980 700,1060 1000,1000 1300,1080 1600,1020 1600,1200 0,1200' \
        -attenuate 0.3 +noise Gaussian -quality 88 "$1"
}

# 流体渐变：plasma 灰度图做索引，套两色渐变 CLUT
fluid() { # 输出 暗色 亮色
    magick -size "$SIZE" plasma:fractal -blur 0x24 -colorspace Gray -normalize -colors 256 \
        \( -size 1x256 "gradient:$2-$3" \) -clut -quality 88 "$1"
}

# 同心圆：纯色底 + 描边圆环
rings() { # 输出 底色 描边色
    magick -size "$SIZE" "xc:$2" -stroke "$3" -strokewidth 26 -fill none \
        -draw 'circle 800,600 800,180' \
        -draw 'circle 800,600 800,300' \
        -draw 'circle 800,600 800,420' \
        -draw 'circle 800,600 800,540' \
        -attenuate 0.3 +noise Gaussian -quality 88 "$1"
}

# 点阵：渐变底 + 半径递增的圆点
dots() { # 输出 底色顶 底色底 点色
    local draw=""
    local y x r
    for y in 150 330 510 690 870 1050; do
        for x in 140 380 620 860 1100 1340; do
            r=$(( 18 + (x + y) % 46 ))
            draw+="circle $x,$y $x,$((y + r)) "
        done
    done
    magick -size "$SIZE" "gradient:$2-$3" -fill "$4" -draw "$draw" -quality 88 "$1"
}

# 斜条纹：大色带旋转后裁切
stripes() { # 输出 底色 条纹色
    magick -size 2400x2400 "xc:$2" -fill "$3" \
        -draw 'rectangle 0,0 300,2400' \
        -draw 'rectangle 600,0 1000,2400' \
        -draw 'rectangle 1300,0 1900,2400' \
        -draw 'rectangle 2200,0 2400,2400' \
        -rotate 28 -gravity center -crop "$SIZE+0+0" +repage -quality 88 "$1"
}

# 几何构成：半圆 + 三角 + 横向色块
shapes() { # 输出 底色顶 底色底 主色 副色
    magick -size "$SIZE" "gradient:$2-$3" \
        -fill "$4" -draw 'circle 460,860 460,1240' \
        -fill "$5" -draw 'polygon 900,260 1520,1080 280,1080' \
        -fill 'rgba(255,255,255,0.10)' -draw 'rectangle 0,0 1600,280' \
        -attenuate 0.3 +noise Gaussian -quality 88 "$1"
}

echo "==> 生成演示图库到 ${OUT}"
sunset  "$OUT/Pictures/01-sunset-plum.jpg"  '#2b1055' '#ff8c42' '#ffe0a3' '#4a2c6d' '#2a1747' '#140d26'
sunset  "$OUT/Pictures/02-sunset-teal.jpg"  '#04263b' '#2ec4b6' '#e8fff6' '#0f5e63' '#093f47' '#04222a'
fluid   "$OUT/Pictures/03-fluid-aurora.jpg" '#06121f' '#38f9d7'
fluid   "$OUT/Pictures/04-fluid-ember.jpg"  '#1a0a12' '#ff9a8b'
rings   "$OUT/Pictures/05-rings-indigo.jpg" '#141b3d' '#7c8cff'
stripes "$OUT/Pictures/06-stripes-sand.jpg" '#f6e7d8' '#d4a373'

sunset  "$OUT/Pictures/Camera/01-sunset-amber.jpg" '#3d1b00' '#ffb703' '#fff3c4' '#7a4a12' '#4d2c0a' '#24140a'
fluid   "$OUT/Pictures/Camera/02-fluid-mint.jpg"   '#062019' '#9ef01a'

dots    "$OUT/Pictures/Screenshots/01-dots-violet.jpg" '#1b1035' '#3c1a78' '#c4a1ff'
fluid   "$OUT/Pictures/Screenshots/02-fluid-violet.jpg" '#0d0219' '#b388ff'
sunset  "$OUT/Pictures/Screenshots/03-sunset-rose.jpg" '#2d0b1e' '#ff6f91' '#ffe3ec' '#5c1f3a' '#3a1226' '#1c0913'

shapes  "$OUT/Downloads/01-shapes-ocean.jpg" '#071b2b' '#0e3b52' '#2ec4b6' '#f7b267'
fluid   "$OUT/Downloads/02-fluid-lagoon.jpg" '#021019' '#4cc9f0'

shapes  "$OUT/Documents/01-shapes-clay.jpg" '#2b1b17' '#4a2c23' '#ff9f68' '#8e6cff'

# 一条演示视频：查看器会用 ffmpeg 取首帧
if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -loglevel error -y -f lavfi \
        -i "gradients=s=1280x720:c0=0x0b132b:c1=0x5bc0be:c2=0x3a506b:d=3" \
        -pix_fmt yuv420p -c:v libx264 -preset ultrafast \
        "$OUT/Pictures/07-clip-ocean.mp4"
else
    echo "   (跳过演示视频：未找到 ffmpeg)"
fi

# 错开 mtime：昨天 / 3 天前 / 上周，制造日期分组
touch -d 'yesterday' "$OUT"/Pictures/0[1-4]-*
touch -d '3 days ago' "$OUT"/Pictures/0[5-7]-*
touch -d '3 days ago' "$OUT"/Pictures/Camera/*
touch -d '8 days ago' "$OUT"/Pictures/Screenshots/* "$OUT"/Downloads/* "$OUT"/Documents/*

du -sh "$OUT"
