// SPDX-License-Identifier: GPL-3.0-or-later
#include "gallery/core/cachecontroller.h"

#include "gallery/core/cachecleaner.h"
#include "gallery/core/cachepaths.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QThreadPool>

namespace gallery::core {
namespace {

QString readableSize(qint64 bytes)
{
    if (bytes < 1024)
        return QStringLiteral("%1 B").arg(bytes);
    if (bytes < 1024 * 1024)
        return QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
    if (bytes < qint64(1024) * 1024 * 1024)
        return QStringLiteral("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
    return QStringLiteral("%1 GB").arg(bytes / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
}

} // namespace

CacheController::CacheController(QObject *parent)
    : QObject(parent)
{
    refresh();
}

QString CacheController::path() const
{
    return thumbnailCacheDir();
}

QString CacheController::sizeText() const
{
    return readableSize(m_bytes);
}

QString CacheController::indexPath() const
{
    return gallery::core::indexCachePath();
}

QString CacheController::indexSizeText() const
{
    return readableSize(m_indexBytes);
}

void CacheController::refresh()
{
    int files = 0;
    qint64 bytes = 0;
    QDirIterator it(path(), { QStringLiteral("*.png") }, QDir::Files);
    while (it.hasNext()) {
        it.next();
        ++files;
        bytes += it.fileInfo().size();
    }
    const qint64 indexBytes = QFileInfo(indexCachePath()).size();
    if (files != m_files || bytes != m_bytes || indexBytes != m_indexBytes) {
        m_files = files;
        m_bytes = bytes;
        m_indexBytes = indexBytes;
        emit changed();
    }
}

void CacheController::pruneToLimit(int maxMb)
{
    if (maxMb <= 0)
        return;
    const qint64 maxBytes = qint64(maxMb) * 1024 * 1024;
    QThreadPool::globalInstance()->start([this, maxBytes] {
        gallery::core::pruneThumbnailCache(maxBytes);
        QMetaObject::invokeMethod(this, "refresh", Qt::QueuedConnection);
    });
}

bool CacheController::clear()
{
    const QDir dir(path());
    bool ok = true;
    const QFileInfoList entries = dir.entryInfoList(
        { QStringLiteral("*.png"), QStringLiteral("*.tmp") }, QDir::Files);
    for (const QFileInfo &entry : entries) {
        if (!QFile::remove(entry.absoluteFilePath()))
            ok = false;
    }
    refresh();
    return ok;
}

} // namespace gallery::core
