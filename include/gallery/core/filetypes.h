// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QSet>
#include <QString>

namespace gallery::core {

inline bool isImageSuffix(const QString &suffix)
{
    static const QSet<QString> suffixes = {
        QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("png"),
        QStringLiteral("webp"), QStringLiteral("gif"), QStringLiteral("bmp"),
    };
    return suffixes.contains(suffix);
}

inline bool isVideoSuffix(const QString &suffix)
{
    static const QSet<QString> suffixes = {
        QStringLiteral("mp4"), QStringLiteral("mov"), QStringLiteral("mkv"),
        QStringLiteral("webm"), QStringLiteral("avi"), QStringLiteral("m4v"),
    };
    return suffixes.contains(suffix);
}

} // namespace gallery::core
