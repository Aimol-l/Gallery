// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QtGlobal>

namespace gallery::core {

struct PruneResult
{
    int removed = 0;
    qint64 freed = 0;
    qint64 remaining = 0;
};

// 按总大小上限清理缩略图缓存（先删最旧的，清到上限的 90%）。
PruneResult pruneThumbnailCache(qint64 maxBytes);

} // namespace gallery::core
