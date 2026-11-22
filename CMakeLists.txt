cmake_minimum_required(VERSION 3.21)

project(Gallery VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Concurrent
)

qt_standard_project_setup()
if(COMMAND qt_policy)
    qt_policy(SET QTP0004 NEW)
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

qt_add_executable(gallery
    src/main.cpp
    src/core/trash.cpp
    src/core/thumbnailprovider.cpp
    src/core/cachecleaner.cpp
    include/gallery/core/cachecleaner.h
    include/gallery/core/cachepaths.h
    include/gallery/core/filetypes.h
    include/gallery/core/trash.h
    include/gallery/core/thumbnailprovider.h
)

# QML 暴露的头文件按模块存放；qmltyperegistrar 生成的是 <basename>，
# 因此把各模块的头目录也加入包含路径。
target_include_directories(gallery PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/include/gallery/core
)

qt_add_resources(gallery "gallery_resources"
    PREFIX "/"
    FILES resources/dev.denial.gallery.svg
)


file(GLOB_RECURSE GALLERY_QML_FILES CONFIGURE_DEPENDS
    RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
    qml/*.qml
)

set_source_files_properties(
    qml/Theme.qml
    qml/AppSettings.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(gallery
    URI Gallery
    VERSION 1.0
    QML_FILES
        ${GALLERY_QML_FILES}
    SOURCES
        include/gallery/core/photomodel.h
        src/core/photomodel.cpp
        include/gallery/core/cachecontroller.h
        src/core/cachecontroller.cpp
        include/gallery/core/appearance.h
        src/core/appearance.cpp
)

target_link_libraries(gallery PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Concurrent
)

# Linux 打包：可执行文件 + .desktop（安装时用）
include(GNUInstallDirs)
install(TARGETS gallery RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

# 安装时也要带上 QML 模块的根 qmldir/qmltypes：
# 构建目录里 Qt 靠 bin/qt.conf 指向 build/Gallery，安装后必须自己提供。
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/Gallery/qmldir"
    "${CMAKE_CURRENT_BINARY_DIR}/Gallery/gallery.qmltypes"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/gallery/qml/Gallery"
)
if(UNIX AND NOT APPLE)
    install(FILES packaging/dev.denial.gallery.desktop
            DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(FILES resources/dev.denial.gallery.svg
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
endif()
