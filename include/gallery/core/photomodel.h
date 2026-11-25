// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QHash>
#include <QSet>
#include <QTimer>
#include <QVector>
#include <QtQml/qqmlregistration.h>

#include <functional>

struct PhotoEntry
{
    QString path;
    QString name;
    QString folder; // 归属根的 id（最长路径匹配）
    QDateTime modified;
    qint64 size = 0;
    bool video = false;
};

// 网格模型：每一行是一条「照片行」（含当天第一行附带的日期标题）。
// 行只保存 m_visible 的区间，照片数据在 data() 中按需生成。
// 扫描采用「边扫边显示」；已有索引时静默比对，不整库复制。
class PhotoModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)
    Q_PROPERTY(int sortMode READ sortMode WRITE setSortMode NOTIFY sortModeChanged)
    Q_PROPERTY(int columns READ columns WRITE setColumns NOTIFY columnsChanged)
    Q_PROPERTY(int photoCount READ photoCount NOTIFY photoCountChanged)
    Q_PROPERTY(QString title READ title NOTIFY filterChanged)
    Q_PROPERTY(QVariantMap counts READ counts NOTIFY countsChanged)
    // 实际存在的文件夹入口（id + 本地化显示名），侧栏/竖屏 chips 数据驱动
    Q_PROPERTY(QVariantList sidebarEntries READ sidebarEntries NOTIFY rootsChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(int recentDays READ recentDays WRITE setRecentDays NOTIFY recentDaysChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    enum Roles {
        DayLabelRole = Qt::UserRole + 1,
        DayCountRole,
        PhotosRole,
    };
    Q_ENUM(Roles)

    explicit PhotoModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    QString searchText() const { return m_searchText; }
    void setSearchText(const QString &text);
    int sortMode() const { return m_sortMode; }
    void setSortMode(int mode);
    int columns() const { return m_columns; }
    void setColumns(int columns);
    int photoCount() const { return m_visible.size(); }
    QString title() const;
    QVariantMap counts() const { return m_counts; }
    QVariantList sidebarEntries() const;
    bool scanning() const { return m_scanning; }
    int recentDays() const { return m_recentDays; }
    void setRecentDays(int days);
    int revision() const { return m_revision; }

    Q_INVOKABLE void scan();
    // 打开单个文件：确保其所在目录可被扫描（仅对扫描根外的文件追加一个
    // 不进侧栏的临时根），不改变主页的文件夹项与扫描范围。
    Q_INVOKABLE bool openFileScope(const QString &filePath);
    // 某文件同目录（不含子目录）照片的扁平索引，用于 viewer 的目录播放列表
    Q_INVOKABLE QVariantList indicesInDirectory(const QString &filePath) const;
    Q_INVOKABLE void toggleFavorite(int flatIndex);
    Q_INVOKABLE QVariantMap photoAt(int flatIndex) const;
    Q_INVOKABLE QVariantMap photoInfo(int flatIndex) const;
    Q_INVOKABLE bool moveToTrash(int flatIndex);
    // 多选删除：按路径批量移到回收站，只重建一次模型
    Q_INVOKABLE int movePathsToTrash(const QStringList &paths);

    // 桌面集成 / 键盘导航
    Q_INVOKABLE int indexForPath(const QString &path) const;
    Q_INVOKABLE QString photoPathInRow(int row) const;
    Q_INVOKABLE int rowForPath(const QString &path) const;
    Q_INVOKABLE int rowForFlatIndex(int flatIndex) const;

signals:
    void filterChanged();
    void searchTextChanged();
    void sortModeChanged();
    void columnsChanged();
    void photoCountChanged();
    void countsChanged();
    void rootsChanged();
    void scanningChanged();
    void recentDaysChanged();
    void revisionChanged();
    void errorOccurred(const QString &message);

private:
    struct Root
    {
        QString id;
        QString label;
        QString path;
        bool flat = false; // true：只扫本目录（文件管理器打开的单目录作用域）
    };
    struct Group
    {
        QDate date;
        QString label;
        int first = 0;
        int count = 0;
    };
    struct Row
    {
        int first = 0;
        int count = 0;
        int group = -1;
        bool firstOfDay = false;
    };
    // 静默比对用的轻量签名（不复制整条 PhotoEntry）
    struct Signature
    {
        qint64 msecs = 0;
        qint64 size = 0;
        quint32 folderHash = 0;
        quint8 video = 0;
        bool operator==(const Signature &other) const = default;
    };

    // 成员函数：buildRoots 里的显示名要走 tr()（随语言翻译）
    QVector<Root> buildRoots() const;
    QString folderLabel(const QString &id) const;
    // m_visible 位置 → m_photos 下标；rebuild 中途两者可能短暂不同步，越界返回 -1
    int photoIndexAt(int visiblePos) const;
    static Signature signatureFor(const PhotoEntry &entry);
    static bool makeEntry(const QFileInfo &info, const QString &rootPath,
                          const QVector<Root> &roots, PhotoEntry *entry);
    static void scanRoots(const QVector<Root> &roots,
                          const std::function<void(const PhotoEntry &)> &onPhoto,
                          const std::function<void(const QString &)> &onDir);

    void rebuild();
    void setScanning(bool scanning);
    bool matches(const PhotoEntry &photo, const QDateTime &recentCutoff) const;
    QString dayLabel(const QDate &date) const;
    QDateTime recentCutoff() const;

    void resetStreamingState();
    void buildOldSignatures();

    void applyScanBatch(const QVector<PhotoEntry> &photos, const QStringList &dirs);
    void streamPhotos(const QVector<PhotoEntry> &photos);
    void finishScan(qint64 elapsedMs);

    // 目录监听 / 增量重扫
    bool watchDir(const QString &dir);
    void seedPriorityWatches();
    void reconcileWatcher();
    void processPendingDirs();
    void rescanDirs(const QSet<QString> &dirs);

    QString favoritesFile() const;
    void loadFavorites();
    void saveFavorites() const;

    QString indexCachePath() const;
    void loadIndexCache();
    void saveIndexCache() const;

    QVector<Root> m_roots;
    QVector<PhotoEntry> m_photos;
    QVector<int> m_visible;
    QVector<int> m_order;
    int m_orderSortMode = -1;
    bool m_orderDirty = true;
    QVector<Group> m_groups;
    QVector<Row> m_rows;

    // 边扫边显示的临时状态
    QSet<QString> m_streamVisibleFolders;
    int m_streamRowEnd = 0;

    // 静默扫描比对
    QHash<QString, Signature> m_oldSigs;
    QVector<PhotoEntry> m_added;
    QHash<QString, PhotoEntry> m_changed;
    QSet<QString> m_deletedThisScan;

    // 目录监听 / 增量重扫
    QSet<QString> m_scanDirs;
    QSet<QString> m_watchedDirs;
    QString m_scopeDir; // 非空 = 单目录作用域（跳过索引缓存读写）
    QSet<QString> m_pendingDirs;
    bool m_watchCapped = false;

    QVariantMap m_counts;
    QSet<QString> m_favorites;

    QFileSystemWatcher m_dirWatcher;
    QTimer m_rescanTimer;

    QString m_filter = QStringLiteral("all");
    QString m_searchText;
    int m_sortMode = 0;
    int m_columns = 6;
    int m_recentDays = 30;
    int m_revision = 0;
    int m_scanGeneration = 0;
    bool m_streaming = false;
    bool m_scanning = false;
    bool m_rescanPending = false;
    bool m_incrementalScanning = false;
};
