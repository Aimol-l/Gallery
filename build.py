#!/usr/bin/env python3
"""Gallery 一站式构建 + 打包（pacman / deb / rpm），仅用 Python 标准库。

用法:
  python3 build.py                          # cmake 构建（release）
  python3 build.py --build mcpp --pkg arch  # mcpp 构建 + pacman 包
  python3 build.py --pkg all                # 构建并出 arch+deb+rpm
  python3 build.py --target aarch64 --pkg arch   # 在平板上构建出 pacman 包
  python3 build.py --run                    # 构建后直接运行

原生构建、当场打包：--target 必须与当前机器架构一致，不符直接报错（不支持交叉编译）。
aarch64 包 = 在平板的源码目录里跑同一脚本；源码同步/部署是独立行为，不归本脚本管。

包内容两种 backend 相同: /usr/bin/gallery + desktop + 图标（cmake 另含
/usr/share/gallery/qml）。mcpp 产物的 PT_INTERP 指向 mcpp 沙箱 loader，打包时用
patchelf 改回宿主 loader（无 patchelf 时退化为启动脚本 + /usr/lib/gallery/）。
"""
import argparse
import hashlib
import io
import os
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PKGNAME = "denial-gallery"
PKGREL = 1
DESC = "Native image viewer for Denial tablets (Qt 6 / QML)"
LICENSE = "GPL-3.0-or-later"

# 三种包体系的架构名 (pacman, deb, rpm)
ARCH_NAMES = {
    "x86": ("x86_64", "amd64", "x86_64"),
    "aarch64": ("aarch64", "arm64", "aarch64"),
}
ARCH_DEPS = ["qt6-base", "qt6-declarative", "qt6-wayland", "qt6-svg",
             "ffmpeg", "hicolor-icon-theme"]
ARCH_OPTDEPENDS = ["qt6-imageformats: GIF/WebP 动图与缩略图",
                   "noto-fonts-cjk: 中文界面字体"]
DEB_DEPS = ["libqt6core6t64 | libqt6core6", "libqt6gui6t64 | libqt6gui6",
            "libqt6network6t64 | libqt6network6", "libqt6qml6t64 | libqt6qml6",
            "libqt6quick6t64 | libqt6quick6",
            "libqt6quickcontrols2-6t64 | libqt6quickcontrols2-6",
            "libqt6svg6t64 | libqt6svg6", "libqt6concurrent6t64 | libqt6concurrent6",
            "qml6-module-qtquick-controls", "qml6-module-qtquick-layouts",
            "qml6-module-qtquick-window", "qml6-module-qtquick-templates",
            "ffmpeg", "hicolor-icon-theme"]
RPM_DEPS = ["qt6-qtbase", "qt6-qtdeclarative", "qt6-qtwayland", "qt6-qtsvg",
            "hicolor-icon-theme"]
RPM_RECOMMENDS = ["ffmpeg"]  # Fedora 主仓库没有 ffmpeg（rpmfusion）；仅视频缩略图用
DESKTOP = "packaging/dev.denial.gallery.desktop"
ICON = "resources/dev.denial.gallery.svg"


def log(msg):
    print(f"==> {msg}", flush=True)


def die(msg):
    sys.exit(f"错误: {msg}")


def run(cmd, **kw):
    print(f"    $ {shlex.join(str(c) for c in cmd)}", flush=True)
    subprocess.run([str(c) for c in cmd], check=True, **kw)


def version():
    text = (ROOT / "CMakeLists.txt").read_text()
    m = re.search(r"project\(Gallery VERSION ([0-9][0-9.]*)", text)
    if not m:
        die("无法从 CMakeLists.txt 读取版本号")
    return m.group(1)


def maintainer():
    try:
        email = subprocess.run(["git", "config", "user.email"], cwd=ROOT,
                               capture_output=True, text=True, check=True).stdout.strip()
        name = subprocess.run(["git", "config", "user.name"], cwd=ROOT,
                              capture_output=True, text=True, check=True).stdout.strip()
        if email:
            return f"{name or 'packager'} <{email}>"
    except subprocess.CalledProcessError:
        pass
    return "packager <packager@localhost>"


def machine_arch():
    return os.uname().machine


# ─────────────────────────── 构建阶段 ───────────────────────────

def build_cmake(profile):
    builddir = ROOT / "build" / f"linux-{profile}"
    run(["cmake", "-B", builddir, "-G", "Ninja",
         f"-DCMAKE_BUILD_TYPE={profile.upper()}",
         "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"], cwd=ROOT)
    run(["cmake", "--build", builddir, "-j", os.cpu_count() or 4], cwd=ROOT)
    binp = builddir / "bin" / "gallery"
    if not binp.exists():
        die(f"构建产物不存在: {binp}")
    return builddir, binp


def build_mcpp(profile):
    cmd = ["mcpp", "build"] if profile == "debug" else ["mcpp", "build", "--profile", "release"]
    run(cmd, cwd=ROOT)
    cands = [p for p in (ROOT / "target").rglob("gallery")
             if p.parent.name == "bin" and "dist" not in p.parts]
    if not cands:
        die("mcpp 产物不存在（target/**/bin/gallery）")
    return max(cands, key=lambda p: p.stat().st_mtime)


def host_interpreter():
    """宿主 ELF 的 PT_INTERP 路径（x86_64: /lib64/ld-linux-x86-64.so.2）。"""
    ref = shutil.which("python3") or sys.executable
    try:
        out = subprocess.run(["patchelf", "--print-interpreter", ref],
                             capture_output=True, text=True, check=True).stdout.strip()
        if out.startswith("/"):
            return out
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return ("/lib64/ld-linux-x86-64.so.2" if machine_arch() == "x86_64"
            else "/lib/ld-linux-aarch64.so.1")


def stage(stage: Path, backend, binp, builddir=None):
    log(f"组装 /usr 布局 -> {stage}")
    shutil.rmtree(stage, ignore_errors=True)
    (stage / "usr/bin").mkdir(parents=True)
    for rel, src in [("usr/share/applications/" + Path(DESKTOP).name, ROOT / DESKTOP),
                     ("usr/share/icons/hicolor/scalable/apps/" + Path(ICON).name, ROOT / ICON)]:
        dst = stage / rel
        dst.parent.mkdir(parents=True)
        shutil.copy2(src, dst)

    if backend == "cmake":
        run(["cmake", "--install", builddir, "--prefix", "/usr"],
            env={**os.environ, "DESTDIR": str(stage.resolve())})
        return

    target = stage / "usr/bin/gallery"
    shutil.copy2(binp, target)
    target.chmod(0o755)
    if shutil.which("patchelf"):
        # mcpp 沙箱 loader 不认 RUNPATH；改回宿主 loader 后裸跑即可（宿主 loader 认 RUNPATH=/usr/lib）
        run(["patchelf", "--set-interpreter", host_interpreter(), target])
    else:
        # 无 patchelf：真身挪到 /usr/lib/gallery，用启动脚本带 LD_LIBRARY_PATH
        real = stage / "usr/lib/gallery/gallery.bin"
        real.parent.mkdir(parents=True)
        shutil.move(target, real)
        target.write_text("#!/bin/sh\nLD_LIBRARY_PATH=/usr/lib exec /usr/lib/gallery/gallery.bin \"$@\"\n")
        target.chmod(0o755)


# ─────────────────────────── 底层工具 ───────────────────────────

def tar_bytes(stage: Path, compression):
    """把 stage 目录打成 tar 字节流。compression: '' | 'gz' | 'xz' | 'zst'。
    条目统一 root:root（等价 makepkg 的 fakerroot，安装后文件属主才是 root）。"""
    def add(tf):
        for p in sorted(stage.rglob("*"), key=lambda q: len(q.parts)):
            ti = tf.gettarinfo(str(p), arcname=p.relative_to(stage).as_posix())
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = "root"
            if ti.isfile():
                with open(p, "rb") as f:
                    tf.addfile(ti, f)
            else:
                tf.addfile(ti)
    mode = "w" + (":" + compression if compression else "")
    fmt = dict(format=tarfile.GNU_FORMAT)  # dpkg 不认 Python 默认的 PAX 扩展头
    try:
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode=mode, **fmt) as tf:
            add(tf)
        return buf.getvalue()
    except (tarfile.CompressionError, ValueError):  # python < 3.14 无 zst，落到外部 zstd
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w", **fmt) as tf:
            add(tf)
        return subprocess.run(["zstd", "-q", "-c", "-"], input=buf.getvalue(),
                              capture_output=True, check=True).stdout


def ar_write(out: Path, members):
    """手写 ar 归档（成员名均 <=15 字符，无需长名表）。members: [(name, bytes)]"""
    buf = bytearray(b"!<arch>\n")
    for name, data in members:
        hdr = f"{name + '/':<16}{'0':<12}{'0':<6}{'0':<6}{'100644':<8}{len(data):<10}`\n"
        buf += hdr.encode()
        buf += data
        if len(data) % 2:
            buf += b"\n"
    out.write_bytes(buf)


def ar_list(path: Path):
    out = subprocess.run(["ar", "t", str(path)], capture_output=True, text=True, check=True)
    return out.stdout.split()


# ─────────────────────────── 三种包格式 ───────────────────────────

class SkipPack(Exception):
    pass


def pkg_arch(stage: Path, out: Path, ver: str, arch: str):
    # pacman 包 = zstd 压缩的单个 tar（.PKGINFO/.MTREE/payload 都是 tar 条目），
    # 不是 deb 那种 ar 归档——libarchive 会把 ar 成员当条目读，装出空包。
    total = sum(p.stat().st_size for p in stage.rglob("*") if p.is_file())
    pkginfo = "\n".join(
        [f"pkgname = {PKGNAME}", f"pkgbase = {PKGNAME}", f"pkgver = {ver}-{PKGREL}",
         f"pkgdesc = {DESC}", f"packager = {maintainer()}", f"arch = {arch}",
         f"license = {LICENSE}", f"builddate = {int(time.time())}", f"size = {total}"]
        + [f"depend = {d}" for d in ARCH_DEPS]
        + [f"optdepend = {d}" for d in ARCH_OPTDEPENDS]) + "\n"

    lines = ["#mtree", "/set type=file uid=0 gid=0"]
    dirs, files = [], []
    for p in sorted(stage.rglob("*")):
        rel = p.relative_to(stage).as_posix()
        mode = oct(p.stat().st_mode & 0o777)[2:]
        mtime = f"{int(p.stat().st_mtime)}.0"
        if p.is_dir():
            dirs.append(f"{rel}/ time={mtime} type=dir mode={mode}")
        else:
            data = p.read_bytes()
            files.append(f"{rel} time={mtime} mode={mode} size={len(data)} "
                         f"sha256digest={hashlib.sha256(data).hexdigest()}")
    lines += sorted(dirs) + files
    mtree = ("\n".join(lines) + "\n").encode()

    def root_entry(name, data):
        ti = tarfile.TarInfo(name)
        ti.size, ti.mode = len(data), 0o644
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = "root"
        tf.addfile(ti, io.BytesIO(data))

    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tf:
        root_entry(".PKGINFO", pkginfo.encode())
        root_entry(".MTREE", mtree)
        for p in sorted(stage.rglob("*"), key=lambda q: len(q.parts)):
            ti = tf.gettarinfo(str(p), arcname=p.relative_to(stage).as_posix())
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = "root"
            if ti.isfile():
                with open(p, "rb") as f:
                    tf.addfile(ti, f)
            else:
                tf.addfile(ti)
    try:
        data = zstd_compress(raw.getvalue())
    except ImportError:
        die("需要 zstd（命令或 python compression.zstd）来压 pacman 包")
    pkg = out / f"{PKGNAME}-{ver}-{PKGREL}-{arch}.pkg.tar.zst"
    pkg.write_bytes(data)
    if shutil.which("pacman"):
        run(["pacman", "-Qlp", pkg])
        run(["pacman", "-Qkp", pkg])   # 按 .MTREE 校验包内文件完整性
    else:
        log("pacman 不存在，仅做结构检查")
    return pkg


def zstd_compress(data: bytes) -> bytes:
    try:
        return subprocess.run(["zstd", "-q", "-c", "-"], input=data,
                              capture_output=True, check=True).stdout
    except FileNotFoundError:
        from compression import zstd as pz  # PEP 784（python 3.14+，无 zstd 命令时）
        return pz.compress(data)


def pkg_deb(stage: Path, out: Path, ver: str, arch: str):
    control = "\n".join([
        f"Package: {PKGNAME}",
        f"Version: {ver}-{PKGREL}",
        "Section: graphics",
        "Priority: optional",
        f"Architecture: {arch}",
        f"Maintainer: {maintainer()}",
        f"Depends: {', '.join(DEB_DEPS)}",
        f"Description: {DESC}",
        " Native image viewer for Denial tablets. Qt 6 / QML, Wayland first.",
    ]) + "\n"
    cbuf = io.BytesIO()
    with tarfile.open(fileobj=cbuf, mode="w:gz", format=tarfile.GNU_FORMAT) as tf:
        info = tarfile.TarInfo("./control")
        info.size = len(control.encode())
        info.mode = 0o644
        tf.addfile(info, io.BytesIO(control.encode()))
    data = tar_bytes(stage, "xz")
    deb = out / f"{PKGNAME}_{ver}-{PKGREL}_{arch}.deb"
    ar_write(deb, [("debian-binary", b"2.0\n"),
                   ("control.tar.gz", cbuf.getvalue()), ("data.tar.xz", data)])
    if shutil.which("dpkg-deb"):
        run(["dpkg-deb", "-I", deb])
    else:
        assert ar_list(deb) == ["debian-binary", "control.tar.gz", "data.tar.xz"]
        log("dpkg-deb 不存在，仅做结构检查")
    return deb


def pkg_rpm(stage: Path, out: Path, ver: str, arch: str):
    if not shutil.which("rpmbuild") and not shutil.which("docker"):
        raise SkipPack("rpmbuild 不存在（Arch 可 `sudo pacman -S rpm-tools`，"
                       "Fedora 是 rpm-build），也没有 docker 可代建")
    top = out / "rpm-top"
    for d in ("BUILD", "RPMS", "SOURCES", "SPECS", "SRPMS"):
        (top / d).mkdir(parents=True, exist_ok=True)
    # %files 从 stage 实际内容生成（cmake 带 /usr/share/gallery，mcpp 没有）。
    # 只把包独有的目录标 %dir；/usr、/usr/bin 等公共目录归 filesystem/hicolor 等包，
    # 标了会安装冲突。文件本身放进共享目录没问题。
    dirs = [p.relative_to(stage).as_posix() for p in sorted(stage.rglob("*")) if p.is_dir()]
    entries = ([f"%dir /{d}/" for d in dirs if d.startswith("usr/share/gallery")]
               + [f"/{p.relative_to(stage).as_posix()}"
                  for p in sorted(stage.rglob("*")) if p.is_file()])
    spec = "\n".join([
        "Name: " + PKGNAME,
        f"Version: {ver}",
        f"Release: {PKGREL}%{{?dist}}",
        f"Summary: {DESC}",
        f"License: {LICENSE}",
        f"BuildArch: {arch}",
        f"Requires: {' '.join(RPM_DEPS)}",
        f"Recommends: {' '.join(RPM_RECOMMENDS)}",
        # 二进制对 Qt 的 soname 依赖带精确版本（Qt_6.12），宿主发行版 Qt 版本未必一致；
        # 关闭自动依赖扫描，只按上面的包名装，避免跨 Qt 版本安装被拒
        "AutoReqProv: no",
        "",
        "%description",
        "Native image viewer for Denial tablets. Qt 6 / QML, Wayland first.",
        "",
        "%files",
        *entries,
        "",
    ])
    specfile = top / "SPECS" / f"{PKGNAME}.spec"
    specfile.write_text(spec)

    if shutil.which("rpmbuild"):
        run(["rpmbuild", "-bb", "--target", arch, "--define", f"_topdir {top}",
             "--define", "debug_package %{nil}", "--buildroot", str(stage.resolve()),
             specfile])
    else:
        # 本机无 rpmbuild：进 fedora 容器构建（stage/spec 通过挂载可见）
        log("用 fedora 容器构建 rpm")
        uid = f"{os.getuid()}:{os.getgid()}"
        run(["docker", "run", "--rm", "-v", f"{out.resolve()}:/work",
             "fedora:latest", "bash", "-c",
             "dnf install -y -q rpm-build >/dev/null && "
             "rpmbuild -bb --target " + arch +
             " --define '_topdir /work/rpm-top' --define 'debug_package %{nil}' "
             "--buildroot /work/stage /work/rpm-top/SPECS/" + PKGNAME + ".spec && "
             f"chown -R {uid} /work/rpm-top"])
    rpms = list((top / "RPMS").rglob("*.rpm"))
    if not rpms:
        raise SkipPack("rpmbuild 未产出 .rpm")
    dst = out / rpms[0].name
    shutil.move(rpms[0], dst)
    return dst


# ─────────────────────────── 入口 ───────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", choices=["cmake", "mcpp"], default="cmake", help="构建后端（默认 cmake）")
    ap.add_argument("--target", choices=["x86", "aarch64"], default="x86",
                    help="包架构；必须与当前机器一致（原生构建，不支持交叉。默认 x86）")
    ap.add_argument("--pkg", choices=["none", "arch", "deb", "rpm", "all"], default="none",
                    help="打包格式（默认只构建）")
    ap.add_argument("--profile", choices=["release", "debug"], default="release")
    ap.add_argument("--out", default="dist/buildpy", help="产物目录（默认 dist/buildpy）")
    ap.add_argument("--run", action="store_true", help="构建完成后直接运行")
    ap.add_argument("--keep-stage", action="store_true", help="保留 dist/buildpy/stage/ 供检查")
    args = ap.parse_args()

    arch_machine = {"x86": "x86_64", "aarch64": "aarch64"}[args.target]
    if machine_arch() != arch_machine:
        die(f"--target {args.target} 要在 {arch_machine} 机器上原生构建，本机是 "
            f"{machine_arch()}；aarch64 包请在平板上运行本脚本")

    arch = args.target  # 已校验与本机架构一致

    ver = version()
    log(f"{PKGNAME} {ver}-{PKGREL} | build={args.build} profile={args.profile} "
        f"target={machine_arch()} pkg={args.pkg}")

    for tool in (["cmake"] if args.build == "cmake" else ["mcpp"]):
        if not shutil.which(tool):
            die(f"缺少工具: {tool}")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    if args.build == "cmake":
        builddir, binp = build_cmake(args.profile)
    else:
        binp = build_mcpp(args.profile)
    log(f"二进制: {binp}")

    stage_dir = out / "stage"
    stage(stage_dir, args.build, binp, builddir if args.build == "cmake" else None)

    pkgs = []
    if args.pkg != "none":
        pacman_arch, deb_arch, rpm_arch = ARCH_NAMES[arch]
        wanted = (["arch", "deb", "rpm"] if args.pkg == "all" else [args.pkg])
        for fmt in wanted:
            try:
                if fmt == "arch":
                    pkgs.append(pkg_arch(stage_dir, out, ver, pacman_arch))
                elif fmt == "deb":
                    pkgs.append(pkg_deb(stage_dir, out, ver, deb_arch))
                elif fmt == "rpm":
                    pkgs.append(pkg_rpm(stage_dir, out, ver, rpm_arch))
            except SkipPack as e:
                (log(f"跳过 {fmt}: {e}") if args.pkg == "all"
                 else die(str(e)))

    if not args.keep_stage:
        shutil.rmtree(stage_dir, ignore_errors=True)

    if args.run:
        env = dict(os.environ)
        if args.build == "mcpp":
            env.setdefault("LD_LIBRARY_PATH", "/usr/lib")
        log("运行（Ctrl+C 退出）")
        os.execvpe(str(binp), [str(binp)], env)

    report(pkgs)


def report(pkgs):
    log("完成")
    for p in pkgs:
        print(f"    {p}  ({p.stat().st_size // 1024} KB)")
    if not pkgs:
        print("    （--pkg none，仅构建）")


if __name__ == "__main__":
    main()
