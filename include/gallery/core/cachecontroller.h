// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

namespace gallery::core {

// QML 单例：缩略图缓存的统计与清理
class CacheController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(int files READ files NOTIFY changed)
    Q_PROPERTY(qint64 bytes READ bytes NOTIFY changed)
    Q_PROPERTY(QString sizeText READ sizeText NOTIFY changed)
    Q_PROPERTY(QString indexPath READ indexPath CONSTANT)
    Q_PROPERTY(qint64 indexBytes READ indexBytes NOTIFY changed)
    Q_PROPERTY(QString indexSizeText READ indexSizeText NOTIFY changed)

public:
    explicit CacheController(QObject *parent = nullptr);

    QString path() const;
    int files() const { return m_files; }
    qint64 bytes() const { return m_bytes; }
    QString sizeText() const;
    QString indexPath() const;
    qint64 indexBytes() const { return m_indexBytes; }
    QString indexSizeText() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool clear();
    Q_INVOKABLE void pruneToLimit(int maxMb);

signals:
    void changed();

private:
    int m_files = 0;
    qint64 m_bytes = 0;
    qint64 m_indexBytes = 0;
};

} // namespace gallery::core
