// SPDX-License-Identifier: GPL-3.0-or-later
#include "gallery/core/thumbnailprovider.h"

#include "gallery/core/cachepaths.h"
#include "gallery/core/filetypes.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>

namespace gallery::core {
namespace {

constexpr int kThumbSize = 256;

QImage placeholder()
{
    QImage image(kThumbSize, kThumbSize, QImage::Format_ARGB32_Premultiplied);
    image.fill(QColor(QStringLiteral("#e9ebef")));
    return image;
}

} // namespace

ThumbnailProvider::ThumbnailProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
    m_cacheDir = thumbnailCacheDir();
    QDir().mkpath(m_cacheDir);
}

QString ThumbnailProvider::cacheFilePath(const QString &sourcePath, const QFileInfo &info) const
{
    const QString key = sourcePath + QLatin1Char('|')
                        + QString::number(info.lastModified().toMSecsSinceEpoch()) + QLatin1Char('|')
                        + QString::number(info.size());
    const QString hash = QString::fromLatin1(
        QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha1).toHex());
    return m_cacheDir + QLatin1Char('/') + hash + QStringLiteral(".png");
}

QImage ThumbnailProvider::generateImage(const QString &sourcePath) const
{
    QImageReader reader(sourcePath);
    reader.setAutoTransform(true);

    const QSize original = reader.size();
    if (original.isValid()) {
        const QSize target = original.scaled(kThumbSize, kThumbSize, Qt::KeepAspectRatio);
        reader.setScaledSize(target);
    }

    const QImage image = reader.read();
    return image.isNull() ? placeholder() : image;
}

QImage ThumbnailProvider::generateVideoFrame(const QString &sourcePath) const
{
    const QString tempPath = QStandardPaths::writableLocation(QStandardPaths::TempLocation)
                             + QStringLiteral("/gallery-thumb-")
                             + QUuid::createUuid().toString(QUuid::Id128)
                             + QStringLiteral(".png");

    QProcess ffmpeg;
    ffmpeg.start(QStringLiteral("ffmpeg"),
                 { QStringLiteral("-ss"), QStringLiteral("1"),
                   QStringLiteral("-i"), sourcePath,
                   QStringLiteral("-frames:v"), QStringLiteral("1"),
                   QStringLiteral("-vf"), QStringLiteral("scale=256:-2"),
                   QStringLiteral("-y"), tempPath });
    if (!ffmpeg.waitForFinished(8000)) {
        ffmpeg.kill();
        ffmpeg.waitForFinished(1000);
        QFile::remove(tempPath);
        return placeholder();
    }

    QImage frame(tempPath);
    QFile::remove(tempPath);
    return frame.isNull() ? placeholder() : frame;
}

QImage ThumbnailProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    Q_UNUSED(requestedSize)

    const QString sourcePath = QUrl::fromPercentEncoding(id.toUtf8());
    const QFileInfo info(sourcePath);
    if (!info.exists()) {
        const QImage fallback = placeholder();
        if (size)
            *size = fallback.size();
        return fallback;
    }

    const QString cachePath = cacheFilePath(sourcePath, info);
    if (QFileInfo::exists(cachePath)) {
        QImage cached(cachePath);
        if (!cached.isNull()) {
            if (size)
                *size = cached.size();
            return cached;
        }
    }

    // 限制同时生成的缩略图数量；拿到槽位后再查一次缓存，避免重复生成
    m_generationSlots.acquire();
    QImage thumb(cachePath);
    if (thumb.isNull()) {
        thumb = isVideoSuffix(info.suffix().toLower())
                    ? generateVideoFrame(sourcePath)
                    : generateImage(sourcePath);

        const QString tempPath = cachePath + QStringLiteral(".tmp");
        if (thumb.save(tempPath, "PNG"))
            QFile::rename(tempPath, cachePath);
        else
            QFile::remove(tempPath);
    }
    m_generationSlots.release();

    if (size)
        *size = thumb.size();
    return thumb;
}

} // namespace gallery::core
