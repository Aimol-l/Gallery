// SPDX-License-Identifier: GPL-3.0-or-later
// Gallery — Denial 平板原生图片查看器
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QFont>
#include <QGuiApplication>
#include <QIcon>
#include <QKeyEvent>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQuickStyle>
#include <QMetaObject>
#include <QMouseEvent>
#include <QSettings>
#include <QThreadPool>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QTimer>
#include <QVariant>
#include <QWheelEvent>

#include "gallery/core/cachecleaner.h"
#include "gallery/core/filetypes.h"
#include "gallery/core/thumbnailprovider.h"

int main(int argc, char *argv[])
{
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("denial"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("dev.denial"));
    QGuiApplication::setApplicationName(QStringLiteral("gallery"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.1.14"));
    // Wayland app_id，必须与 .desktop 文件名 / StartupWMClass 一致
    QGuiApplication::setDesktopFileName(QStringLiteral("dev.denial.gallery"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/resources/dev.denial.gallery.svg")));

    // 支持「打开方式」/命令行传入单个文件
    QString initialPath;
    for (int i = 1; i < argc; ++i) {
        const QString argument = QString::fromLocal8Bit(argv[i]);
        if (argument.startsWith(QLatin1Char('-')))
            continue;
        const QFileInfo info(argument);
        if (!info.isFile())
            continue;
        const QString suffix = info.suffix().toLower();
        if (gallery::core::isImageSuffix(suffix) || gallery::core::isVideoSuffix(suffix)) {
            initialPath = info.absoluteFilePath();
            break;
        }
    }

    QFont appFont(QStringLiteral("Noto Sans CJK SC"));
    appFont.setPixelSize(13);
    QGuiApplication::setFont(appFont);

    // 单实例：已有实例时把文件/激活请求转发过去，然后直接退出
    static const QString instanceName = QStringLiteral("dev.denial.gallery");
    {
        QLocalSocket probe;
        probe.connectToServer(instanceName);
        if (probe.waitForConnected(150)) {
            probe.write(initialPath.toUtf8());
            probe.flush();
            probe.waitForBytesWritten(300);
            probe.disconnectFromServer();
            return 0;
        }
    }

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // 启动时按设置的上限在后台修剪缩略图缓存
    {
        QSettings settings;
        const int limitMb = settings.value(QStringLiteral("Gallery/thumbCacheLimitMB"), 1024).toInt();
        if (limitMb > 0) {
            QThreadPool::globalInstance()->start([limitMb] {
                const auto result = gallery::core::pruneThumbnailCache(qint64(limitMb) * 1024 * 1024);
                if (result.removed > 0) {
                    qInfo().nospace() << "Gallery: pruned " << result.removed
                                      << " thumbnails, freed " << (result.freed / 1024 / 1024)
                                      << " MB";
                }
            });
        }
    }

    qInfo() << "Gallery: platform =" << QGuiApplication::platformName();
    QQmlApplicationEngine engine;
    // 安装后 QML 模块的 qmldir 在 <prefix>/share/gallery/qml，构建目录里则靠 qt.conf
    engine.addImportPath(QDir(QCoreApplication::applicationDirPath()
                              + QStringLiteral("/../share/gallery/qml")).absolutePath());
    engine.addImageProvider(QStringLiteral("thumbs"),
                            new gallery::core::ThumbnailProvider);
    engine.loadFromModule(QStringLiteral("Gallery"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;

    // 开发辅助：GALLERY_SIZE=1000x1600 用于验证竖屏布局
    if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst())) {
        const QStringList size = qEnvironmentVariable("GALLERY_SIZE").split(QLatin1Char('x'));
        if (size.size() == 2) {
            bool okW = false;
            bool okH = false;
            const int w = size.at(0).toInt(&okW);
            const int h = size.at(1).toInt(&okH);
            if (okW && okH) {
                win->setWidth(w);
                win->setHeight(h);
            }
        }

        // 开发辅助：GALLERY_OPEN_INDEX=N 自动进入查看模式
        if (qEnvironmentVariableIsSet("GALLERY_OPEN_INDEX")) {
            const int index = qEnvironmentVariableIntValue("GALLERY_OPEN_INDEX");
            const bool showInfo = qEnvironmentVariableIntValue("GALLERY_INFO") != 0;
            QTimer::singleShot(700, win, [win, index, showInfo] {
                QMetaObject::invokeMethod(win, "devOpen", Q_ARG(int, index),
                                          Q_ARG(bool, showInfo));
            });
        }
        // 开发辅助：打开删除确认框 / 直接移到回收站
        if (qEnvironmentVariableIsSet("GALLERY_DELETE_INDEX")) {
            const int index = qEnvironmentVariableIntValue("GALLERY_DELETE_INDEX");
            QTimer::singleShot(700, win, [win, index] {
                QMetaObject::invokeMethod(win, "devRequestDelete", Q_ARG(int, index));
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_TRASH_INDEX")) {
            const int index = qEnvironmentVariableIntValue("GALLERY_TRASH_INDEX");
            QTimer::singleShot(700, win, [win, index] {
                QMetaObject::invokeMethod(win, "devTrash", Q_ARG(int, index));
            });
        }
        // 开发辅助：对当前查看的照片弹删除确认框 / 确认删除
        if (qEnvironmentVariableIntValue("GALLERY_REQUEST_DELETE") != 0) {
            QTimer::singleShot(900, win, [win] {
                QMetaObject::invokeMethod(win, "devRequestDeleteCurrent");
            });
        }
        if (qEnvironmentVariableIntValue("GALLERY_CONFIRM_DELETE") != 0) {
            QTimer::singleShot(1300, win, [win] {
                QMetaObject::invokeMethod(win, "devConfirmDelete");
            });
        }
        if (qEnvironmentVariableIntValue("GALLERY_ROTATE") != 0) {
            QTimer::singleShot(900, win, [win] {
                QMetaObject::invokeMethod(win, "devRotate");
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_SEARCH")) {
            const QString text = qEnvironmentVariable("GALLERY_SEARCH");
            QTimer::singleShot(500, win, [win, text] {
                QMetaObject::invokeMethod(win, "devSearch", Q_ARG(QString, text));
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_SORT")) {
            const int mode = qEnvironmentVariableIntValue("GALLERY_SORT");
            QTimer::singleShot(500, win, [win, mode] {
                QMetaObject::invokeMethod(win, "devSort", Q_ARG(int, mode));
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_FILTER")) {
            const QString id = qEnvironmentVariable("GALLERY_FILTER");
            QTimer::singleShot(500, win, [win, id] {
                QMetaObject::invokeMethod(win, "devFilter", Q_ARG(QString, id));
            });
        }
        if (qEnvironmentVariableIntValue("GALLERY_FAVORITE") != 0) {
            QTimer::singleShot(1000, win, [win] {
                QMetaObject::invokeMethod(win, "devFavorite");
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_SELECT")) {
            const int index = qEnvironmentVariableIntValue("GALLERY_SELECT");
            QTimer::singleShot(500, win, [win, index] {
                QMetaObject::invokeMethod(win, "devSelect", Q_ARG(int, index));
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_ZOOM")) {
            const double value = qEnvironmentVariable("GALLERY_ZOOM").toDouble();
            QTimer::singleShot(500, win, [win, value] {
                QMetaObject::invokeMethod(win, "devZoom", Q_ARG(double, value));
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_SETTINGS")) {
            const int page = qEnvironmentVariableIntValue("GALLERY_SETTINGS");
            QTimer::singleShot(500, win, [win, page] {
                QMetaObject::invokeMethod(win, "devSettings", Q_ARG(int, page));
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_ACCENT")) {
            const QString color = qEnvironmentVariable("GALLERY_ACCENT");
            QTimer::singleShot(500, win, [win, color] {
                QMetaObject::invokeMethod(win, "devAccent", Q_ARG(QString, color));
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_APPEARANCE")) {
            const QString mode = qEnvironmentVariable("GALLERY_APPEARANCE");
            QTimer::singleShot(400, win, [win, mode] {
                QMetaObject::invokeMethod(win, "devAppearance", Q_ARG(QString, mode));
            });
        }
        if (qEnvironmentVariableIntValue("GALLERY_CLEAR_CACHE") != 0) {
            QTimer::singleShot(700, win, [win] {
                QMetaObject::invokeMethod(win, "devClearCache");
            });
        }
        if (qEnvironmentVariableIsSet("GALLERY_SCALE")) {
            const double value = qEnvironmentVariable("GALLERY_SCALE").toDouble();
            QTimer::singleShot(500, win, [win, value] {
                QMetaObject::invokeMethod(win, "devScale", Q_ARG(double, value));
            });
        }
        // 开发辅助：长按第一张缩略图（600ms 阈值）
        if (qEnvironmentVariableIntValue("GALLERY_LONGPRESS_TEST") != 0) {
            QTimer::singleShot(1000, win, [win] {
                const QPointF pos(330, 240);
                QMouseEvent press(QEvent::MouseButtonPress, pos,
                                  win->mapToGlobal(pos.toPoint()),
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
                QCoreApplication::sendEvent(win, &press);
            });
            QTimer::singleShot(1700, win, [win] {
                const QPointF pos(330, 240);
                QMouseEvent release(QEvent::MouseButtonRelease, pos,
                                    win->mapToGlobal(pos.toPoint()),
                                    Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
                QCoreApplication::sendEvent(win, &release);
            });
            // 可选：长按进入多选后，点击顶部「删除」按钮，验证确认框
            if (qEnvironmentVariableIntValue("GALLERY_LONGPRESS_CONFIRM") != 0) {
                QTimer::singleShot(2100, win, [win] {
                    const QPointF pos(win->width() - 64, 81);
                    QMouseEvent press(QEvent::MouseButtonPress, pos,
                                      win->mapToGlobal(pos.toPoint()),
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
                    QCoreApplication::sendEvent(win, &press);
                });
                QTimer::singleShot(2180, win, [win] {
                    const QPointF pos(win->width() - 64, 81);
                    QMouseEvent release(QEvent::MouseButtonRelease, pos,
                                        win->mapToGlobal(pos.toPoint()),
                                        Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
                    QCoreApplication::sendEvent(win, &release);
                });
            }
        }
        // 开发辅助：向右方向键，验证网格键盘导航
        if (qEnvironmentVariableIsSet("GALLERY_KEY_TEST")) {
            QTimer::singleShot(900, win, [win] {
                QKeyEvent press(QEvent::KeyPress, Qt::Key_Right, Qt::NoModifier);
                QCoreApplication::sendEvent(win, &press);
                QKeyEvent release(QEvent::KeyRelease, Qt::Key_Right, Qt::NoModifier);
                QCoreApplication::sendEvent(win, &release);
            });
        }
        // 开发辅助：向舞台中心发送滚轮事件，验证滚轮切换 / Ctrl+滚轮缩放
        if (qEnvironmentVariableIsSet("GALLERY_WHEEL_TEST")) {
            const QString mode = qEnvironmentVariable("GALLERY_WHEEL_TEST");
            const int repeat = qMax(1, qEnvironmentVariableIntValue("GALLERY_WHEEL_REPEAT"));
            const QPoint angle = (mode == QLatin1String("ctrl"))
                                     ? QPoint(0, 120) : QPoint(0, -120);
            const Qt::KeyboardModifiers modifiers = (mode == QLatin1String("ctrl"))
                                                        ? Qt::ControlModifier : Qt::NoModifier;
            auto *wheelTimer = new QTimer(win);
            wheelTimer->setInterval(350); // 大于 Viewer 的切换防抖间隔
            wheelTimer->setProperty("sent", 0);
            QObject::connect(wheelTimer, &QTimer::timeout, win,
                             [win, angle, modifiers, wheelTimer, repeat] {
                const int sent = wheelTimer->property("sent").toInt() + 1;
                wheelTimer->setProperty("sent", sent);
                if (sent > repeat) {
                    wheelTimer->stop();
                    wheelTimer->deleteLater();
                    return;
                }
                const QPointF pos(win->width() * 0.6, win->height() * 0.5);
                QWheelEvent event(pos, win->mapToGlobal(pos.toPoint()), QPoint(), angle,
                                  Qt::NoButton, modifiers, Qt::NoScrollPhase, false);
                QCoreApplication::sendEvent(win, &event);
            });
            QTimer::singleShot(1100, win, [wheelTimer] { wheelTimer->start(); });
        }
        // 开发辅助：发送一次 Esc（退出查看模式回网格）
        if (qEnvironmentVariableIntValue("GALLERY_ESCAPE") != 0) {
            QTimer::singleShot(1600, win, [win] {
                QKeyEvent event(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
                QCoreApplication::sendEvent(win, &event);
            });
        }
    }

    // 单实例服务：接收第二个进程转发来的文件/激活请求
    QLocalServer instanceServer;
    QLocalServer::removeServer(instanceName);
    if (!instanceServer.listen(instanceName))
        qWarning() << "Gallery: cannot start instance server:" << instanceServer.errorString();

    QObject::connect(&instanceServer, &QLocalServer::newConnection, &app,
                     [&instanceServer, &engine] {
        while (QLocalSocket *socket = instanceServer.nextPendingConnection()) {
            auto *win = engine.rootObjects().isEmpty()
                            ? nullptr
                            : qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
            QObject::connect(socket, &QLocalSocket::readyRead, socket, [socket, win] {
                const QString message = QString::fromUtf8(socket->readAll());
                if (win) {
                    QMetaObject::invokeMethod(win, "openFromLauncher", Q_ARG(QString, message));
                    win->requestActivate();
                }
                socket->disconnectFromServer();
            });
            QObject::connect(socket, &QLocalSocket::disconnected,
                             socket, &QLocalSocket::deleteLater);
            if (socket->bytesAvailable() > 0) {
                const QString message = QString::fromUtf8(socket->readAll());
                if (win) {
                    QMetaObject::invokeMethod(win, "openFromLauncher", Q_ARG(QString, message));
                    win->requestActivate();
                }
            }
        }
    });

    if (!initialPath.isEmpty()) {
        // 等 QML 根对象就绪再投递（首次启动可能晚于固定延时），就绪前持续轮询
        auto *openTimer = new QTimer(&app);
        openTimer->setInterval(150);
        QObject::connect(openTimer, &QTimer::timeout, &app, [&engine, initialPath, openTimer] {
            if (engine.rootObjects().isEmpty())
                return;
            auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
            if (!win)
                return;
            QMetaObject::invokeMethod(win, "openFromLauncher", Q_ARG(QString, initialPath));
            openTimer->stop();
            openTimer->deleteLater();
        });
        openTimer->start();
    }

    // 开发辅助：GALLERY_SCREENSHOT=/tmp/shot.png 时渲染一帧后退出（配合 offscreen 平台）
    if (qEnvironmentVariableIsSet("GALLERY_SCREENSHOT")) {
        const QString path = qEnvironmentVariable("GALLERY_SCREENSHOT");
        int delay = 1900;
        if (qEnvironmentVariableIsSet("GALLERY_SCREENSHOT_DELAY"))
            delay = qEnvironmentVariableIntValue("GALLERY_SCREENSHOT_DELAY");
        QTimer::singleShot(delay, &app, [&engine, path] {
            if (!engine.rootObjects().isEmpty()) {
                if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()))
                    win->grabWindow().save(path);
            }
            QCoreApplication::quit();
        });
    }

    return app.exec();
}
