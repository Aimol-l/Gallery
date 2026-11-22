// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace gallery::core {

// QML 单例：系统配色（用于「跟随系统」外观）
class Appearance : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool systemDark READ systemDark NOTIFY systemDarkChanged)

public:
    explicit Appearance(QObject *parent = nullptr);

    bool systemDark() const { return m_systemDark; }

signals:
    void systemDarkChanged();

private:
    void update();

    bool m_systemDark = false;
};

} // namespace gallery::core
