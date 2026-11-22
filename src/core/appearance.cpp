// SPDX-License-Identifier: GPL-3.0-or-later
#include "gallery/core/appearance.h"

#include <QGuiApplication>
#include <QStyleHints>

#include <QDebug>

namespace gallery::core {

Appearance::Appearance(QObject *parent)
    : QObject(parent)
{
    update();
    qInfo() << "Gallery: system color scheme dark =" << m_systemDark;
    if (auto *hints = QGuiApplication::styleHints()) {
        connect(hints, &QStyleHints::colorSchemeChanged,
                this, &Appearance::update);
    }
}

void Appearance::update()
{
    const bool dark = QGuiApplication::styleHints()
                      && QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark;
    if (dark == m_systemDark)
        return;
    m_systemDark = dark;
    qInfo() << "Gallery: system color scheme dark =" << dark;
    emit systemDarkChanged();
}

} // namespace gallery::core
