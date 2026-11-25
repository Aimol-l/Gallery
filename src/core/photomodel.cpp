// SPDX-License-Identifier: GPL-3.0-or-later
#include "gallery/core/photomodel.h"

#include "gallery/core/cachepaths.h"
#include "gallery/core/filetypes.h"
#include "gallery/core/trash.h"

#include <QByteArrayList>
#include <QDataStream>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPointer>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThreadPool>
#include <QTimer>

#include <algorithm>
#include <numeric>
#include <utility>

namespace {

constexpr quint32 kIndexMagic = 0x47414c4c; // "GALL"
constexpr quint16 kIndexVersion = 3;
constexpr int kMaxWatchedDirs = 8192;
constexpr int kIncrementalEntryLimit = 50000;

QString normalizedRoot(const QString &path)
{
    QString p = QDir::cleanPath(path);
    while (p.endsWith(QLatin1Char('/')) && p.size() > 1)
        p.chop(1);
    return p;
}

bool isUnder(const QString &file, const QString &root)
{
    if (file == root)
        return true;
    return file.startsWith(root + QLatin1Char('/'));
}

bool isUnderAny(const QString &path, const QSet<QString> &dirs)
{
    for (const QString &dir : dirs) {
        if (isUnder(path, dir))
            return true;
    }
    return false;
}

QString humanSize(qint64 bytes)
{
    if (bytes < 1024)
        return QStringLiteral("%1 B").arg(bytes);
    if (bytes < 1024 * 1024)
        return QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
    if (bytes < qint64(1024) * 1024 * 1024)
        return QStringLiteral("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
    return QStringLiteral("%1 GB").arg(bytes / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
}

bool isHiddenRelative(const QString &root, const QString &file)
{
    const QString rel = QDir(root).relativeFilePath(file);
    const auto parts = rel.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        if (part.startsWith(QLatin1Char('.')))
            return true;
    }
    return false;
}

} // namespace

PhotoModel::PhotoModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_roots = buildRoots();
    loadFavorites();
    loadIndexCache();
    rebuild();

    seedPriorityWatches();

    m_rescanTimer.setSingleShot(true);
    m_rescanTimer.setInterval(400);
    connect(&m_rescanTimer, &QTimer::timeout, this, &PhotoModel::processPendingDirs);
    connect(&m_dirWatcher, &QFileSystemWatcher::directoryChanged, this,
            [this](const QString &dir) {
                m_pendingDirs.insert(dir);
                if (!m_scanning && !m_incrementalScanning && !m_rescanTimer.isActive())
                    m_rescanTimer.start();
            });
}

QVector<PhotoModel::Root> PhotoModel::buildRoots() const
{
    // 本地开发可用 GALLERY_HOME 指向一个假 home（放少量测试图片），
    // 避免在 x86 上扫描真实的上十万张图。
    QString home = qEnvironmentVariable("GALLERY_HOME");
    const bool testHome = !home.isEmpty();
    if (home.isEmpty())
        home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);

    // 用户目录走 QStandardPaths：Linux 读 XDG user-dirs 配置（目录名随系统语言，
    // 如中文系统的 图片/下载/文档），Windows/macOS 映射到系统对应目录。
    // 测试环境（GALLERY_HOME）退回假 home 下的固定英文名。
    auto stdDir = [testHome](QStandardPaths::StandardLocation loc) -> QString {
        return testHome ? QString() : QStandardPaths::writableLocation(loc);
    };
    const QString pictures = stdDir(QStandardPaths::PicturesLocation);
    const QString downloads = stdDir(QStandardPaths::DownloadLocation);
    const QString documents = stdDir(QStandardPaths::DocumentsLocation);

    const QVector<Root> candidates = {
        { QStringLiteral("pictures"), tr("图片"),
          pictures.isEmpty() ? home + QStringLiteral("/Pictures") : pictures },
        // Screenshots / Camera 是图片目录下的平台惯例子目录（桌面/平板截图、相机；
        // Android 侧惯例在 DCIM 下），不存在的候选由下面的 isDir 过滤自动隐藏。
        { QStringLiteral("screenshots"), tr("屏幕截图"),
          (pictures.isEmpty() ? home + QStringLiteral("/Pictures") : pictures)
              + QStringLiteral("/Screenshots") },
        { QStringLiteral("camera"), tr("相机"),
          (pictures.isEmpty() ? home + QStringLiteral("/Pictures") : pictures)
              + QStringLiteral("/Camera") },
        { QStringLiteral("camera-dcim"), tr("相机"), home + QStringLiteral("/DCIM/Camera") },
        { QStringLiteral("downloads"), tr("下载"),
          downloads.isEmpty() ? home + QStringLiteral("/Downloads") : downloads },
        { QStringLiteral("documents"), tr("文档"),
          documents.isEmpty() ? home + QStringLiteral("/Documents") : documents },
    };

    QVector<Root> roots;
    for (const Root &root : candidates) {
        if (QFileInfo(root.path).isDir()) {
            // DCIM 候选只在 Pictures/Camera 不存在时生效（同一入口，两种平台惯例）
            if (root.id == QLatin1String("camera-dcim")) {
                bool covered = false;
                for (const Root &existing : roots)
                    if (existing.id == QLatin1String("camera"))
                        covered = true;
                if (covered)
                    continue;
                Root r = root;
                r.id = QStringLiteral("camera");
                r.path = normalizedRoot(r.path);
                roots.append(r);
                continue;
            }
            Root r = root;
            r.path = normalizedRoot(r.path);
            roots.append(r);
        }
    }
    return roots;
}

QString PhotoModel::folderLabel(const QString &id) const
{
    for (const Root &root : m_roots) {
        if (root.id == id)
            return root.label;
    }
    return id;
}

bool PhotoModel::openFileScope(const QString &filePath)
{
    const QFileInfo info(filePath);
    if (!info.isFile())
        return false;
    const QString dir = normalizedRoot(info.absolutePath());

    // 已在某个扫描根覆盖范围内：扫描与侧栏保持原样，主页不受打开方式影响
    for (const Root &root : std::as_const(m_roots)) {
        if (root.id != QLatin1String("external") && isUnder(dir, root.path))
            return true;
    }

    // 扫描根外的文件（如 ~/Misc）：追加一个临时根让该目录可扫，但不进侧栏
    Root external;
    external.id = QStringLiteral("external");
    external.label = QDir(dir).dirName();
    external.path = dir;
    external.flat = true;

    for (Root &root : m_roots) {
        if (root.id == QLatin1String("external")) {
            if (root.path == dir)
                return true;
            root = external;
            m_scopeDir = dir; // 跳过索引缓存读写
            scan();
            return true;
        }
    }
    m_roots.append(external);
    m_scopeDir = dir;
    scan();
    return true;
}

QVariantList PhotoModel::indicesInDirectory(const QString &filePath) const
{
    const QString dir = QFileInfo(filePath).absolutePath();
    QVariantList list;
    list.reserve(m_visible.size());
    for (int i = 0; i < m_visible.size(); ++i) {
        const int photoIndex = photoIndexAt(i);
        if (photoIndex < 0)
            continue;
        const QString &path = m_photos.at(photoIndex).path;
        if (path.left(path.lastIndexOf(QLatin1Char('/'))) == dir)
            list.append(i);
    }
    return list;
}

QVariantList PhotoModel::sidebarEntries() const
{
    QVariantList list;
    for (const Root &root : m_roots) {
        // 临时根（文件管理器打开扫描根外文件时追加）不参与侧栏，
        // 主页的文件夹项始终只反映标准用户目录
        if (root.id == QLatin1String("external"))
            continue;
        list.append(QVariantMap{
            { QStringLiteral("id"), root.id },
            { QStringLiteral("label"), root.label },
        });
    }
    return list;
}

PhotoModel::Signature PhotoModel::signatureFor(const PhotoEntry &entry)
{
    Signature sig;
    sig.msecs = entry.modified.toMSecsSinceEpoch();
    sig.size = entry.size;
    sig.folderHash = qHash(entry.folder);
    sig.video = entry.video ? 1 : 0;
    return sig;
}

bool PhotoModel::makeEntry(const QFileInfo &info, const QString &rootPath,
                           const QVector<Root> &roots, PhotoEntry *entry)
{
    const QString suffix = info.suffix().toLower();
    const bool video = gallery::core::isVideoSuffix(suffix);
    if (!video && !gallery::core::isImageSuffix(suffix))
        return false;
    if (isHiddenRelative(rootPath, info.absoluteFilePath()))
        return false;

    entry->path = QDir::cleanPath(info.absoluteFilePath());
    entry->name = info.fileName();
    entry->modified = info.lastModified();
    entry->size = info.size();
    entry->video = video;

    // 关键去重规则：同一文件只归到「路径最长匹配」的根
    QString bestId;
    int bestLength = -1;
    for (const Root &candidate : roots) {
        if (isUnder(entry->path, candidate.path)) {
            const int length = candidate.path.size();
            if (length > bestLength) {
                bestLength = length;
                bestId = candidate.id;
            }
        }
    }
    entry->folder = bestId;
    return true;
}

void PhotoModel::scanRoots(const QVector<Root> &roots,
                           const std::function<void(const PhotoEntry &)> &onPhoto,
                           const std::function<void(const QString &)> &onDir)
{
    // 只扫描不被其它根覆盖的根（Pictures 覆盖 Screenshots/Camera）。
    // 这些根互不嵌套，每个文件只会被枚举一次，因此不需要额外的去重集合。
    QVector<Root> scanRoots;
    for (const Root &root : roots) {
        bool covered = false;
        for (const Root &other : roots) {
            if (&other == &root)
                continue;
            if (other.path.size() < root.path.size() && isUnder(root.path, other.path)) {
                covered = true;
                break;
            }
        }
        if (!covered)
            scanRoots.append(root);
    }

    for (const Root &root : scanRoots) {
        onDir(root.path);
        QDirIterator it(root.path, QDir::Files | QDir::NoSymLinks | QDir::NoDotAndDotDot,
                        root.flat ? QDirIterator::NoIteratorFlags
                                  : QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            const QFileInfo info = it.fileInfo();
            PhotoEntry entry;
            if (!makeEntry(info, root.path, roots, &entry))
                continue;
            onDir(info.absolutePath());
            onPhoto(entry);
        }
    }
}

QString PhotoModel::favoritesFile() const
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
           + QStringLiteral("/denial/gallery-favorites.json");
}

void PhotoModel::loadFavorites()
{
    QFile file(favoritesFile());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonArray array = QJsonDocument::fromJson(file.readAll()).array();
    for (const QJsonValue &value : array)
        m_favorites.insert(value.toString());
}

void PhotoModel::saveFavorites() const
{
    const QString path = favoritesFile();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QJsonArray array;
    for (const QString &favorite : m_favorites)
        array.append(favorite);
    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
}

QString PhotoModel::indexCachePath() const
{
    return gallery::core::indexCachePath();
}

void PhotoModel::loadIndexCache()
{
    // 单目录作用域不走全局索引缓存（根不同，避免 23MB 索引来回覆写）
    if (!m_scopeDir.isEmpty())
        return;
    QElapsedTimer timer;
    timer.start();

    QFile file(indexCachePath());
    if (!file.open(QIODevice::ReadOnly))
        return;

    QDataStream in(&file);
    in.setVersion(QDataStream::Qt_6_0);
    quint32 magic = 0;
    quint16 version = 0;
    quint32 count = 0;
    in >> magic >> version >> count;
    if (magic != kIndexMagic || version != kIndexVersion || count == 0 || count > 5'000'000)
        return;

    quint32 rootCount = 0;
    in >> rootCount;
    if (rootCount != quint32(m_roots.size()))
        return;
    for (const Root &root : m_roots) {
        QByteArray cachedRoot;
        in >> cachedRoot;
        if (QString::fromUtf8(cachedRoot) != root.path)
            return;
    }
    if (in.status() != QDataStream::Ok)
        return;

    QVector<PhotoEntry> photos;
    photos.reserve(int(count));
    QHash<QByteArray, QString> folderPool;
    QByteArray pathBytes;
    QByteArray folderBytes;
    for (quint32 i = 0; i < count; ++i) {
        qint64 msecs = 0;
        qint64 size = 0;
        quint8 video = 0;
        in >> msecs >> size >> video >> pathBytes >> folderBytes;
        if (in.status() != QDataStream::Ok) {
            photos.clear();
            break;
        }

        PhotoEntry entry;
        entry.path = QString::fromUtf8(pathBytes);
        entry.name = entry.path.mid(entry.path.lastIndexOf(QLatin1Char('/')) + 1);
        entry.modified = QDateTime::fromMSecsSinceEpoch(msecs);
        entry.size = size;
        entry.video = video != 0;

        auto it = folderPool.constFind(folderBytes);
        if (it == folderPool.constEnd())
            it = folderPool.insert(folderBytes, QString::fromUtf8(folderBytes));
        entry.folder = it.value();
        photos.append(entry);
    }
    if (photos.size() != int(count))
        return;

    m_photos = std::move(photos);

    qInfo().nospace() << "Gallery: index cache loaded " << m_photos.size()
                      << " photos in " << timer.elapsed() << " ms";
}

void PhotoModel::saveIndexCache() const
{
    if (!m_scopeDir.isEmpty())
        return;
    const QVector<PhotoEntry> snapshot = m_photos;
    const QString path = indexCachePath();
    QByteArrayList rootPaths;
    rootPaths.reserve(m_roots.size());
    for (const Root &root : m_roots)
        rootPaths.append(root.path.toUtf8());

    QThreadPool::globalInstance()->start([snapshot, path, rootPaths] {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly))
            return;
        QDataStream out(&file);
        out.setVersion(QDataStream::Qt_6_0);
        out << kIndexMagic << kIndexVersion << quint32(snapshot.size())
            << quint32(rootPaths.size());
        for (const QByteArray &rootPath : rootPaths)
            out << rootPath;
        for (const PhotoEntry &entry : snapshot) {
            out << qint64(entry.modified.toMSecsSinceEpoch())
                << entry.size
                << quint8(entry.video ? 1 : 0)
                << entry.path.toUtf8()
                << entry.folder.toUtf8();
        }
        if (!file.commit())
            qWarning() << "Gallery: cannot write index cache" << path;
    });
}

void PhotoModel::setFilter(const QString &filter)
{
    if (m_filter == filter)
        return;
    m_filter = filter;
    emit filterChanged();
    rebuild();
}

void PhotoModel::setSearchText(const QString &text)
{
    if (m_searchText == text)
        return;
    m_searchText = text;
    emit searchTextChanged();
    rebuild();
}

void PhotoModel::setSortMode(int mode)
{
    if (m_sortMode == mode)
        return;
    m_sortMode = mode;
    emit sortModeChanged();
    rebuild();
}

void PhotoModel::setColumns(int columns)
{
    columns = qMax(1, columns);
    if (m_columns == columns)
        return;
    m_columns = columns;
    emit columnsChanged();
    rebuild();
}

void PhotoModel::setRecentDays(int days)
{
    days = qBound(1, days, 3650);
    if (m_recentDays == days)
        return;
    m_recentDays = days;
    emit recentDaysChanged();
    rebuild();
}

void PhotoModel::setScanning(bool scanning)
{
    if (m_scanning == scanning)
        return;
    m_scanning = scanning;
    emit scanningChanged();
}

QString PhotoModel::title() const
{
    if (m_filter == QLatin1String("all"))
        return tr("全部照片");
    if (m_filter == QLatin1String("recent"))
        return tr("最近添加");
    if (m_filter == QLatin1String("favorites"))
        return tr("收藏");
    return folderLabel(m_filter);
}

QDateTime PhotoModel::recentCutoff() const
{
    return QDateTime::currentDateTime().addDays(-m_recentDays);
}

bool PhotoModel::matches(const PhotoEntry &photo, const QDateTime &recentCutoff) const
{
    const bool favorite = m_favorites.contains(photo.path);
    if (m_filter == QLatin1String("recent")) {
        if (photo.modified < recentCutoff)
            return false;
    } else if (m_filter == QLatin1String("favorites")) {
        if (!favorite)
            return false;
    } else if (m_filter != QLatin1String("all")) {
        if (photo.folder != m_filter)
            return false;
    }

    if (!m_searchText.isEmpty()
        && !photo.name.contains(m_searchText, Qt::CaseInsensitive)) {
        return false;
    }
    return true;
}

QString PhotoModel::dayLabel(const QDate &date) const
{
    const QDate today = QDate::currentDate();
    if (date == today)
        return QStringLiteral("今天");
    if (date == today.addDays(-1))
        return QStringLiteral("昨天");
    if (date.year() == today.year())
        return QStringLiteral("%1 月 %2 日").arg(date.month()).arg(date.day());
    return QStringLiteral("%1 年 %2 月 %3 日").arg(date.year()).arg(date.month()).arg(date.day());
}

void PhotoModel::resetStreamingState()
{
    beginResetModel();
    m_photos.clear();
    m_visible.clear();
    m_order.clear();
    m_orderDirty = true;
    m_groups.clear();
    m_rows.clear();
    m_streamVisibleFolders.clear();
    m_streamRowEnd = 0;
    m_counts.clear();
    m_counts[QStringLiteral("all")] = 0;
    m_counts[QStringLiteral("recent")] = 0;
    m_counts[QStringLiteral("favorites")] = 0;
    m_counts[QStringLiteral("visibleFolders")] = 0;
    for (const Root &root : m_roots)
        m_counts[root.id] = 0;
    endResetModel();

    ++m_revision;
    emit photoCountChanged();
    emit countsChanged();
    emit revisionChanged();
}

void PhotoModel::buildOldSignatures()
{
    m_oldSigs.clear();
    m_oldSigs.reserve(m_photos.size());
    for (const PhotoEntry &entry : m_photos)
        m_oldSigs.insert(entry.path, signatureFor(entry));
    qInfo().nospace() << "Gallery: silent scan comparing against " << m_photos.size()
                      << " entries";
}

void PhotoModel::rebuild()
{
    QElapsedTimer rebuildTimer;
    rebuildTimer.start();

    beginResetModel();

    // 全局顺序只排一次：切换筛选时直接按 m_order 过滤，避免每次重排几十万条
    if (m_orderDirty || m_orderSortMode != m_sortMode
        || m_order.size() != m_photos.size()) {
        m_order.resize(m_photos.size());
        std::iota(m_order.begin(), m_order.end(), 0);
        std::sort(m_order.begin(), m_order.end(), [this](int a, int b) {
            const PhotoEntry &pa = m_photos.at(a);
            const PhotoEntry &pb = m_photos.at(b);
            if (pa.modified.date() != pb.modified.date())
                return pa.modified.date() > pb.modified.date();
            switch (m_sortMode) {
            case 1:
                return pa.name.compare(pb.name, Qt::CaseInsensitive) < 0;
            case 2:
                if (pa.size != pb.size)
                    return pa.size > pb.size;
                return pa.modified > pb.modified;
            default:
                if (pa.modified != pb.modified)
                    return pa.modified > pb.modified;
                return pa.name < pb.name;
            }
        });
        m_orderSortMode = m_sortMode;
        m_orderDirty = false;
    }

    const QDateTime cutoff = recentCutoff();
    m_visible.clear();
    m_visible.reserve(m_photos.size());
    for (int flat : std::as_const(m_order)) {
        if (matches(m_photos.at(flat), cutoff))
            m_visible.append(flat);
    }

    m_groups.clear();
    m_rows.clear();
    int i = 0;
    while (i < m_visible.size()) {
        const QDate date = m_photos.at(m_visible.at(i)).modified.date();
        int end = i;
        while (end < m_visible.size()
               && m_photos.at(m_visible.at(end)).modified.date() == date) {
            ++end;
        }

        Group group;
        group.date = date;
        group.label = dayLabel(date);
        group.first = i;
        group.count = end - i;
        const int groupIndex = m_groups.size();
        m_groups.append(group);

        for (int start = i; start < end; start += m_columns) {
            Row row;
            row.first = start;
            row.count = qMin(m_columns, end - start);
            row.group = groupIndex;
            row.firstOfDay = (start == i);
            m_rows.append(row);
        }
        i = end;
    }
    m_streamRowEnd = m_visible.size();

    QVariantMap counts;
    counts[QStringLiteral("all")] = m_photos.size();
    int recent = 0;
    int favorites = 0;
    QHash<QString, int> folderCounts;
    for (const PhotoEntry &photo : m_photos) {
        if (photo.modified >= cutoff)
            ++recent;
        if (m_favorites.contains(photo.path))
            ++favorites;
        ++folderCounts[photo.folder];
    }
    counts[QStringLiteral("recent")] = recent;
    counts[QStringLiteral("favorites")] = favorites;

    QSet<QString> visibleFolders;
    for (int flat : m_visible)
        visibleFolders.insert(m_photos.at(flat).folder);
    counts[QStringLiteral("visibleFolders")] = visibleFolders.size();
    for (const Root &root : m_roots)
        counts[root.id] = folderCounts.value(root.id);
    m_counts = counts;

    endResetModel();
    ++m_revision;
    emit photoCountChanged();
    emit countsChanged();
    emit revisionChanged();

    const qint64 elapsed = rebuildTimer.elapsed();
    if (elapsed > 100 || qEnvironmentVariableIsSet("GALLERY_TIMING")) {
        qWarning().nospace() << "Gallery: slow rebuild " << elapsed << " ms (filter="
                             << m_filter << ", visible=" << m_visible.size() << ")";
    }
}

bool PhotoModel::watchDir(const QString &dir)
{
    if (m_watchedDirs.contains(dir))
        return true;
    if (m_watchedDirs.size() >= kMaxWatchedDirs) {
        if (!m_watchCapped) {
            m_watchCapped = true;
            qWarning().nospace() << "Gallery: directory watch cap reached (" << kMaxWatchedDirs
                                 << "), deeper directories will not auto-refresh";
        }
        return false;
    }
    if (!QFileInfo(dir).isDir())
        return false;
    if (!m_dirWatcher.addPath(dir))
        return false;
    m_watchedDirs.insert(dir);
    return true;
}

void PhotoModel::seedPriorityWatches()
{
    // 根目录和一层子目录优先监听（截图/相机/下载等高频变化的位置）
    for (const Root &root : m_roots) {
        watchDir(root.path);
        m_scanDirs.insert(root.path);
        const QDir dir(root.path);
        const QStringList children =
            dir.entryList(QDir::Dirs | QDir::NoSymLinks | QDir::NoDotAndDotDot);
        for (const QString &child : children) {
            const QString path = root.path + QLatin1Char('/') + child;
            watchDir(path);
            m_scanDirs.insert(path);
        }
    }
}

void PhotoModel::applyScanBatch(const QVector<PhotoEntry> &photos, const QStringList &dirs)
{
    for (const QString &dir : dirs) {
        if (m_scanDirs.contains(dir))
            continue;
        m_scanDirs.insert(dir);
        watchDir(dir);
    }

    if (m_streaming) {
        streamPhotos(photos);
        return;
    }

    for (const PhotoEntry &photo : photos) {
        if (m_deletedThisScan.contains(photo.path))
            continue;
        const auto it = m_oldSigs.find(photo.path);
        if (it == m_oldSigs.end()) {
            m_added.append(photo);
            continue;
        }
        if (it.value() == signatureFor(photo)) {
            m_oldSigs.erase(it); // 标记已见
        } else {
            m_oldSigs.erase(it);
            m_changed.insert(photo.path, photo);
        }
    }
}

void PhotoModel::streamPhotos(const QVector<PhotoEntry> &photos)
{
    QVector<int> matching;
    matching.reserve(photos.size());
    const QDateTime cutoff = recentCutoff();

    for (const PhotoEntry &photo : photos) {
        if (m_deletedThisScan.contains(photo.path))
            continue;

        const int flat = m_photos.size();
        m_photos.append(photo);
        m_orderDirty = true;

        m_counts[QStringLiteral("all")] =
            m_counts.value(QStringLiteral("all")).toInt() + 1;
        if (photo.modified >= cutoff) {
            m_counts[QStringLiteral("recent")] =
                m_counts.value(QStringLiteral("recent")).toInt() + 1;
        }
        if (m_favorites.contains(photo.path)) {
            m_counts[QStringLiteral("favorites")] =
                m_counts.value(QStringLiteral("favorites")).toInt() + 1;
        }
        m_counts[photo.folder] = m_counts.value(photo.folder).toInt() + 1;

        if (matches(photo, cutoff)) {
            matching.append(flat);
            m_streamVisibleFolders.insert(photo.folder);
        }
    }

    if (!matching.isEmpty()) {
        m_visible.append(matching);

        QVector<Row> newRows;
        int position = m_streamRowEnd;
        const int end = m_visible.size();
        while (position + m_columns <= end) {
            newRows.append({ position, m_columns, -1, false });
            position += m_columns;
        }
        if (!newRows.isEmpty()) {
            const int firstRow = m_rows.size();
            beginInsertRows(QModelIndex(), firstRow, firstRow + newRows.size() - 1);
            m_rows.append(newRows);
            endInsertRows();
        }
        m_streamRowEnd = position;
    }

    m_counts[QStringLiteral("visibleFolders")] = m_streamVisibleFolders.size();
    ++m_revision;
    emit photoCountChanged();
    emit countsChanged();
    emit revisionChanged();
}

void PhotoModel::finishScan(qint64 elapsedMs)
{
    setScanning(false);

    if (m_streaming) {
        m_streaming = false;
        QElapsedTimer rebuildTimer;
        rebuildTimer.start();
        rebuild();
        qInfo().nospace() << "Gallery: scanned " << m_photos.size()
                          << " photos in " << elapsedMs << " ms (streamed), final layout in "
                          << rebuildTimer.elapsed() << " ms";
        saveIndexCache();
    } else {
        const bool changed = !m_added.isEmpty() || !m_changed.isEmpty()
                             || !m_oldSigs.isEmpty();
        if (changed) {
            QVector<PhotoEntry> next;
            next.reserve(m_photos.size() + m_added.size());
            for (const PhotoEntry &old : std::as_const(m_photos)) {
                if (m_oldSigs.contains(old.path))
                    continue; // 扫描中没再出现 → 外部删除
                const auto it = m_changed.constFind(old.path);
                next.append(it != m_changed.constEnd() ? it.value() : old);
            }
            for (const PhotoEntry &added : std::as_const(m_added)) {
                if (!m_deletedThisScan.contains(added.path))
                    next.append(added);
            }

            m_photos = std::move(next);
            m_orderDirty = true;
            QElapsedTimer rebuildTimer;
            rebuildTimer.start();
            rebuild();
            qInfo().nospace() << "Gallery: incremental index update (" << m_added.size()
                              << " added, " << m_changed.size() << " changed) in "
                              << rebuildTimer.elapsed() << " ms";
            saveIndexCache();
        }
        qInfo().nospace() << "Gallery: scanned " << m_photos.size()
                          << " photos in " << elapsedMs << " ms"
                          << (changed ? " (updated)" : " (unchanged)");
    }

    m_oldSigs.clear();
    m_added.clear();
    m_changed.clear();
    m_deletedThisScan.clear();
    qInfo().nospace() << "Gallery: watching " << m_watchedDirs.size() << " dirs";
    reconcileWatcher();

    if (m_rescanPending) {
        m_rescanPending = false;
        QTimer::singleShot(50, this, &PhotoModel::scan);
    } else if (!m_pendingDirs.isEmpty() && !m_rescanTimer.isActive()) {
        m_rescanTimer.start();
    }
}

void PhotoModel::reconcileWatcher()
{
    QStringList stale;
    for (const QString &dir : std::as_const(m_watchedDirs)) {
        if (!m_scanDirs.contains(dir))
            stale.append(dir);
    }
    for (const QString &dir : stale) {
        m_dirWatcher.removePath(dir);
        m_watchedDirs.remove(dir);
    }
    m_scanDirs.clear();
}

void PhotoModel::processPendingDirs()
{
    if (m_scanning || m_incrementalScanning)
        return;

    QSet<QString> dirs = m_pendingDirs;
    m_pendingDirs.clear();
    if (dirs.isEmpty())
        return;

    // 去掉被其它待处理目录覆盖的子目录
    QSet<QString> normalized;
    for (const QString &dir : dirs) {
        bool covered = false;
        for (const QString &other : dirs) {
            if (other == dir)
                continue;
            if (other.size() < dir.size() && isUnder(dir, other)) {
                covered = true;
                break;
            }
        }
        if (!covered)
            normalized.insert(dir);
    }
    if (normalized.isEmpty())
        return;

    if (m_photos.isEmpty()) {
        scan();
        return;
    }

    // 大范围变化退回后台全量扫描
    int affected = 0;
    for (const PhotoEntry &photo : std::as_const(m_photos)) {
        if (isUnderAny(photo.path, normalized) && ++affected > kIncrementalEntryLimit) {
            scan();
            return;
        }
    }

    rescanDirs(normalized);
}

void PhotoModel::rescanDirs(const QSet<QString> &dirs)
{
    m_incrementalScanning = true;
    QElapsedTimer timer;
    timer.start();

    QVector<PhotoEntry> entries;
    QSet<QString> scannedDirs;
    int budget = kIncrementalEntryLimit * 2;

    for (const QString &dir : dirs) {
        // 用包含该目录的最深根来判定隐藏路径
        QString rootPath;
        bool flat = false;
        int rootLength = -1;
        for (const Root &root : std::as_const(m_roots)) {
            if (isUnder(dir, root.path) && root.path.size() > rootLength) {
                rootLength = root.path.size();
                rootPath = root.path;
                flat = root.flat;
            }
        }
        if (rootPath.isEmpty())
            rootPath = dir;

        scannedDirs.insert(dir);
        QDirIterator it(dir, QDir::Files | QDir::NoSymLinks | QDir::NoDotAndDotDot,
                        flat ? QDirIterator::NoIteratorFlags : QDirIterator::Subdirectories);
        while (it.hasNext()) {
            if (--budget < 0) {
                m_incrementalScanning = false;
                scan();
                return;
            }
            it.next();
            const QFileInfo info = it.fileInfo();
            PhotoEntry entry;
            if (!makeEntry(info, rootPath, m_roots, &entry))
                continue;
            scannedDirs.insert(info.absolutePath());
            entries.append(entry);
        }
    }

    // 移除这些目录下的旧条目，再合并新条目
    QVector<PhotoEntry> kept;
    kept.reserve(m_photos.size() + entries.size());
    for (const PhotoEntry &photo : std::as_const(m_photos)) {
        if (!isUnderAny(photo.path, dirs))
            kept.append(photo);
    }
    const int removed = m_photos.size() - kept.size();
    kept.append(entries);
    m_photos = std::move(kept);
    m_orderDirty = true;

    // 更新监听：新增目录加入；被删除的子目录移除
    for (const QString &dir : scannedDirs)
        watchDir(dir);
    QStringList stale;
    for (const QString &watched : std::as_const(m_watchedDirs)) {
        if (isUnderAny(watched, dirs) && !scannedDirs.contains(watched))
            stale.append(watched);
    }
    for (const QString &dir : stale) {
        m_dirWatcher.removePath(dir);
        m_watchedDirs.remove(dir);
    }

    rebuild();
    saveIndexCache();
    qInfo().nospace() << "Gallery: incremental rescan (" << removed << " removed, "
                      << entries.size() << " found) in " << timer.elapsed()
                      << " ms for " << dirs.size() << " dir(s)";

    m_incrementalScanning = false;
    if (!m_pendingDirs.isEmpty() && !m_rescanTimer.isActive())
        m_rescanTimer.start();
}

void PhotoModel::scan()
{
    if (m_scanning) {
        m_rescanPending = true;
        return;
    }
    if (m_roots.isEmpty()) {
        setScanning(false);
        return;
    }

    ++m_scanGeneration;
    m_streaming = m_photos.isEmpty();
    m_added.clear();
    m_changed.clear();
    m_deletedThisScan.clear();
    m_oldSigs.clear();
    m_scanDirs.clear();
    m_pendingDirs.clear();

    if (m_streaming)
        resetStreamingState();
    else
        buildOldSignatures();

    m_watchCapped = false;
    seedPriorityWatches();

    setScanning(true);
    const int generation = m_scanGeneration;
    const QVector<Root> roots = m_roots;
    QPointer<PhotoModel> self(this);
    QElapsedTimer started;
    started.start();

    QThreadPool::globalInstance()->start([self, roots, generation, started]() mutable {
        QVector<PhotoEntry> batch;
        QSet<QString> dirs;
        batch.reserve(2048);
        QElapsedTimer flushTimer;
        flushTimer.start();

        auto flush = [&] {
            if (batch.isEmpty() && dirs.isEmpty())
                return;

            const QVector<PhotoEntry> photos = std::move(batch);
            batch = QVector<PhotoEntry>();
            batch.reserve(2048);
            const QStringList dirList(dirs.begin(), dirs.end());
            dirs.clear();

            if (!self)
                return;
            QMetaObject::invokeMethod(self.data(), [self, generation, photos, dirList] {
                if (!self || self->m_scanGeneration != generation)
                    return;
                self->applyScanBatch(photos, dirList);
            }, Qt::QueuedConnection);
            flushTimer.restart();
        };

        scanRoots(roots,
                  [&](const PhotoEntry &entry) {
                      batch.append(entry);
                      if (batch.size() >= 2000 || flushTimer.elapsed() >= 150)
                          flush();
                  },
                  [&](const QString &dir) {
                      dirs.insert(dir);
                      if (flushTimer.elapsed() >= 150)
                          flush();
                  });

        flush();

        if (self) {
            const qint64 elapsed = started.elapsed();
            QMetaObject::invokeMethod(self.data(), [self, generation, elapsed] {
                if (!self || self->m_scanGeneration != generation)
                    return;
                self->finishScan(elapsed);
            }, Qt::QueuedConnection);
        }
    });
}

void PhotoModel::toggleFavorite(int flatIndex)
{
    QVariantMap photo = photoAt(flatIndex);
    if (photo.isEmpty())
        return;
    const QString path = photo.value(QStringLiteral("path")).toString();
    const bool wasFavorite = m_favorites.contains(path);
    if (wasFavorite)
        m_favorites.remove(path);
    else
        m_favorites.insert(path);
    saveFavorites();

    if (m_filter == QLatin1String("favorites")) {
        rebuild();
        return;
    }

    // 只是收藏状态变化，不需要重建整个网格
    m_counts[QStringLiteral("favorites")] =
        qMax(0, m_counts.value(QStringLiteral("favorites")).toInt()
                    + (wasFavorite ? -1 : 1));
    ++m_revision;
    emit countsChanged();
    emit revisionChanged();
}

QVariantMap PhotoModel::photoAt(int flatIndex) const
{
    const int photoIndex = photoIndexAt(flatIndex);
    if (photoIndex < 0)
        return {};
    const PhotoEntry &photo = m_photos.at(photoIndex);
    return {
        { QStringLiteral("index"), flatIndex },
        { QStringLiteral("path"), photo.path },
        { QStringLiteral("name"), photo.name },
        { QStringLiteral("folder"), photo.folder },
        { QStringLiteral("size"), photo.size },
        { QStringLiteral("modified"), photo.modified },
        { QStringLiteral("video"), photo.video },
        { QStringLiteral("favorite"), m_favorites.contains(photo.path) },
    };
}

QVariantMap PhotoModel::photoInfo(int flatIndex) const
{
    const int photoIndex = photoIndexAt(flatIndex);
    if (photoIndex < 0)
        return {};
    const PhotoEntry &photo = m_photos.at(photoIndex);

    QString dimensions = QStringLiteral("—");
    if (!photo.video) {
        QImageReader reader(photo.path);
        const QSize size = reader.size();
        if (size.isValid())
            dimensions = QStringLiteral("%1 × %2").arg(size.width()).arg(size.height());
    }

    QString path = photo.path;
    const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    if (path.startsWith(home + QLatin1Char('/')))
        path = QLatin1Char('~') + path.mid(home.size());

    return {
        { QStringLiteral("name"), photo.name },
        { QStringLiteral("dimensions"), dimensions },
        { QStringLiteral("bytes"), photo.size },
        { QStringLiteral("size"), humanSize(photo.size) },
        { QStringLiteral("modified"), photo.modified.toString(QStringLiteral("yyyy-MM-dd HH:mm")) },
        { QStringLiteral("path"), path },
        { QStringLiteral("fullPath"), photo.path },
        { QStringLiteral("source"), folderLabel(photo.folder) },
        { QStringLiteral("video"), photo.video },
        { QStringLiteral("favorite"), m_favorites.contains(photo.path) },
    };
}

bool PhotoModel::moveToTrash(int flatIndex)
{
    const int photoIndex = photoIndexAt(flatIndex);
    if (photoIndex < 0)
        return false;
    const QString path = m_photos.at(photoIndex).path;
    return movePathsToTrash({ path }) > 0;
}

int PhotoModel::movePathsToTrash(const QStringList &paths)
{
    QSet<QString> requested;
    for (const QString &path : paths) {
        const QString clean = QDir::cleanPath(path);
        if (!clean.isEmpty())
            requested.insert(clean);
    }
    if (requested.isEmpty())
        return 0;

    QSet<QString> removed;
    for (const QString &path : std::as_const(requested)) {
        if (!QFileInfo::exists(path)) {
            emit errorOccurred(QStringLiteral("文件不存在：%1").arg(path));
            continue;
        }
        QString error;
        if (gallery::core::moveToTrash(path, &error))
            removed.insert(path);
        else
            emit errorOccurred(error);
    }
    if (removed.isEmpty())
        return 0;

    QVector<PhotoEntry> kept;
    kept.reserve(m_photos.size());
    for (const PhotoEntry &photo : std::as_const(m_photos)) {
        if (!removed.contains(photo.path))
            kept.append(photo);
    }
    m_photos = std::move(kept);
    m_orderDirty = true;

    for (const QString &path : std::as_const(removed)) {
        m_oldSigs.remove(path);
        m_changed.remove(path);
        m_deletedThisScan.insert(path);
        m_favorites.remove(path);
    }
    m_added.removeIf([&removed](const PhotoEntry &entry) {
        return removed.contains(entry.path);
    });

    saveFavorites();
    rebuild();
    saveIndexCache();
    return removed.size();
}

int PhotoModel::indexForPath(const QString &path) const
{
    const QString clean = QDir::cleanPath(path);
    for (int i = 0; i < m_visible.size(); ++i) {
        const int photoIndex = photoIndexAt(i);
        if (photoIndex >= 0 && m_photos.at(photoIndex).path == clean)
            return i;
    }
    return -1;
}

int PhotoModel::photoIndexAt(int visiblePos) const
{
    if (visiblePos < 0 || visiblePos >= m_visible.size())
        return -1;
    const int idx = m_visible.at(visiblePos);
    return (idx >= 0 && idx < m_photos.size()) ? idx : -1;
}

QString PhotoModel::photoPathInRow(int row) const
{
    if (row < 0 || row >= m_rows.size())
        return {};
    const Row &meta = m_rows.at(row);
    if (meta.count <= 0 || meta.first < 0 || meta.first >= m_visible.size())
        return {};
    const int photoIndex = photoIndexAt(meta.first);
    return photoIndex >= 0 ? m_photos.at(photoIndex).path : QString();
}

int PhotoModel::rowForFlatIndex(int flatIndex) const
{
    int lo = 0;
    int hi = m_rows.size() - 1;
    while (lo <= hi) {
        const int mid = (lo + hi) / 2;
        const Row &row = m_rows.at(mid);
        if (flatIndex < row.first) {
            hi = mid - 1;
        } else if (flatIndex >= row.first + row.count) {
            lo = mid + 1;
        } else {
            return mid;
        }
    }
    return -1;
}

int PhotoModel::rowForPath(const QString &path) const
{
    const QString clean = QDir::cleanPath(path);
    for (int i = 0; i < m_visible.size(); ++i) {
        const int photoIndex = photoIndexAt(i);
        if (photoIndex >= 0 && m_photos.at(photoIndex).path == clean)
            return rowForFlatIndex(i);
    }
    return -1;
}

int PhotoModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant PhotoModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};

    const Row &row = m_rows.at(index.row());
    switch (role) {
    case DayLabelRole:
        return (row.group >= 0 && row.firstOfDay) ? m_groups.at(row.group).label : QString();
    case DayCountRole:
        return row.group >= 0 ? m_groups.at(row.group).count : 0;
    case PhotosRole: {
        QVariantList photos;
        photos.reserve(row.count);
        const int stop = row.first + row.count;
        for (int position = row.first; position < stop; ++position) {
            const int photoIndex = photoIndexAt(position);
            if (photoIndex < 0)
                continue;
            const PhotoEntry &photo = m_photos.at(photoIndex);
            photos.append(QVariantMap{
                { QStringLiteral("index"), position },
                { QStringLiteral("path"), photo.path },
                { QStringLiteral("name"), photo.name },
                { QStringLiteral("video"), photo.video },
                { QStringLiteral("favorite"), m_favorites.contains(photo.path) },
            });
        }
        return photos;
    }
    default:
        return {};
    }
}

QHash<int, QByteArray> PhotoModel::roleNames() const
{
    return {
        { DayLabelRole, "dayLabel" },
        { DayCountRole, "dayCount" },
        { PhotosRole, "photos" },
    };
}
