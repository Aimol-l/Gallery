// SPDX-License-Identifier: GPL-3.0-or-later
#include "gallery/core/trash.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>

namespace gallery::core {
namespace {

QString uniqueTargetPath(const QString &filesDir, const QString &fileName)
{
    const QFileInfo info(fileName);
    const QString base = info.completeBaseName();
    const QString suffix = info.suffix();

    QString candidate = QDir(filesDir).filePath(fileName);
    int n = 1;
    while (QFileInfo::exists(candidate)) {
        const QString numbered = QStringLiteral("%1.%2").arg(base).arg(n++);
        const QString name = suffix.isEmpty() ? numbered
                                              : numbered + QLatin1Char('.') + suffix;
        candidate = QDir(filesDir).filePath(name);
    }
    return candidate;
}

} // namespace

bool moveToTrash(const QString &filePath, QString *error)
{
    const QFileInfo source(filePath);
    if (!source.exists()) {
        if (error)
            *error = QStringLiteral("文件不存在：%1").arg(filePath);
        return false;
    }

    const QString trashRoot = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                              + QStringLiteral("/Trash");
    const QString filesDir = trashRoot + QStringLiteral("/files");
    const QString infoDir = trashRoot + QStringLiteral("/info");
    if (!QDir().mkpath(filesDir) || !QDir().mkpath(infoDir)) {
        if (error)
            *error = QStringLiteral("无法创建回收站目录：%1").arg(trashRoot);
        return false;
    }

    const QString target = uniqueTargetPath(filesDir, source.fileName());
    const QString targetName = QFileInfo(target).fileName();

    bool moved = QFile::rename(filePath, target);
    if (!moved) {
        // 跨文件系统时 rename 会失败：退化为复制后删除
        moved = QFile::copy(filePath, target);
        if (moved && !QFile::remove(filePath)) {
            QFile::remove(target);
            moved = false;
        }
    }
    if (!moved) {
        if (error)
            *error = QStringLiteral("无法移动文件到回收站：%1").arg(filePath);
        return false;
    }

    QFile infoFile(infoDir + QLatin1Char('/') + targetName + QStringLiteral(".trashinfo"));
    if (!infoFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        // 尽量回滚，避免文件进了回收站却没有 .trashinfo
        QFile::rename(target, filePath);
        if (error)
            *error = QStringLiteral("无法写入回收站信息文件");
        return false;
    }

    const QString encodedPath = QString::fromLatin1(
        QUrl::toPercentEncoding(source.absoluteFilePath(), QByteArrayLiteral("/")));
    const QString deletionDate = QDateTime::currentDateTime().toString(Qt::ISODate);

    infoFile.write("[Trash Info]\n");
    infoFile.write("Path=" + encodedPath.toUtf8() + "\n");
    infoFile.write("DeletionDate=" + deletionDate.toUtf8() + "\n");
    infoFile.close();
    return true;
}

} // namespace gallery::core
