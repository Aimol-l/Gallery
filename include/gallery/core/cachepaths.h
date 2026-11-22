// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QStandardPaths>
#include <QString>

namespace gallery::core {

// ~/.cache/denial/gallery/thumbs（尊重 XDG_CACHE_HOME）
inline QString thumbnailCacheDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
           + QStringLiteral("/denial/gallery/thumbs");
}

// 扫描索引缓存：下次启动先显示上次的索引，再后台增量刷新
inline QString indexCachePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
           + QStringLiteral("/denial/gallery/index.bin");
}

} // namespace gallery::core
