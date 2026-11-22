// SPDX-License-Identifier: GPL-3.0-or-later
#include "gallery/core/cachecleaner.h"

#include "gallery/core/cachepaths.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>

#include <algorithm>
#include <vector>

namespace gallery::core {
namespace {

struct Entry
{
    QString path;
    qint64 size = 0;
    QDateTime stamp;
};

} // namespace

PruneResult pruneThumbnailCache(qint64 maxBytes)
{
    PruneResult result;
    if (maxBytes <= 0)
        return result;

    const QDir dir(thumbnailCacheDir());
    if (!dir.exists())
        return result;

    const QDateTime now = QDateTime::currentDateTime();
    std::vector<Entry> entries;
    qint64 total = 0;

    const QFileInfoList files = dir.entryInfoList(
        { QStringLiteral("*.png"), QStringLiteral("*.tmp") }, QDir::Files);
    for (const QFileInfo &info : files) {
        if (info.suffix() == QLatin1String("tmp")) {
            // 半截临时文件：超过 1 小时直接清掉
            if (info.lastModified().secsTo(now) > 3600)
                QFile::remove(info.absoluteFilePath());
            continue;
        }
        Entry entry;
        entry.path = info.absoluteFilePath();
        entry.size = info.size();
        entry.stamp = info.lastModified();
        entries.push_back(entry);
        total += entry.size;
    }

    result.remaining = total;
    if (total <= maxBytes)
        return result;

    std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
        return a.stamp < b.stamp;
    });

    const qint64 target = maxBytes * 9 / 10;
    for (const Entry &entry : entries) {
        if (total <= target)
            break;
        if (QFile::remove(entry.path)) {
            total -= entry.size;
            ++result.removed;
            result.freed += entry.size;
        }
    }
    result.remaining = total;
    return result;
}

} // namespace gallery::core
