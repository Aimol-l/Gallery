// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QImage>
#include <QQuickImageProvider>
#include <QSemaphore>
#include <QString>

class QFileInfo;

namespace gallery::core {

// QML 图片提供者：image://thumbs/<percent-encoded path>
// 256px 缩略图缓存到 ~/.cache/denial/gallery/thumbs/<hash>.png；
// 视频用 ffmpeg 取第 1 秒首帧（8 秒超时）。
class ThumbnailProvider : public QQuickImageProvider
{
public:
    ThumbnailProvider();

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    QString cacheFilePath(const QString &sourcePath, const QFileInfo &info) const;
    QImage generateImage(const QString &sourcePath) const;
    QImage generateVideoFrame(const QString &sourcePath) const;

    QString m_cacheDir;
    // 生成并发上限 2（视频要起 ffmpeg 进程）
    QSemaphore m_generationSlots{2};
};

} // namespace gallery::core
