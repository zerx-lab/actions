#!/usr/bin/env bash
# Zed Nightly 本地全流程测试脚本
# 用法：bash zed/build-and-test.sh [阶段]
#
# 阶段（可选，默认 all）：
#   all       全流程：编译 → 打包 → makepkg → 安装验证
#   compile   仅编译（zed + cli）
#   package   仅打包为 tar.gz（需先完成 compile）
#   makepkg   仅构建 pacman 包（需先完成 package）
#   install   仅安装并验证（需先完成 makepkg）
#   clean     清理所有构建产物
#
# 目录结构（均在 zed/ 下，已加入 .gitignore）：
#   zed/src/           Zed 源码（git clone 拉取）
#   zed/build/         构建产物（tar.gz、pkg.tar.zst 等）
#   zed/test-output/   makepkg 工作目录

set -euo pipefail

# ── 路径配置 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ZED_SRC_DIR="${SCRIPT_DIR}/src"
BUILD_DIR="${SCRIPT_DIR}/build"
PKG_DIR="${SCRIPT_DIR}/test-output"
PKGBUILD_SRC="${SCRIPT_DIR}/aur/PKGBUILD"

ARCHIVE_NAME="zed-nightly-linux-x86_64.tar.gz"
APP_PREFIX="/usr/lib/zed-nightly.app"
APP_ID="dev.zed.Zed-Nightly"

# ── 颜色 ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR ]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}══ $* ${NC}"; }

# ── 前置检查 ──────────────────────────────────────────────────────────────────
check_deps() {
    step "前置检查"
    local missing=()
    for cmd in cargo objcopy ldd envsubst tar sha256sum makepkg git readelf; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        error "缺少以下工具：${missing[*]}"
        exit 1
    fi
    success "依赖工具检查通过"

    if [ ! -d "${ZED_SRC_DIR}" ]; then
        error "找不到 Zed 源码目录：${ZED_SRC_DIR}"
        echo ""
        echo "请先克隆源码："
        echo "  git clone --depth=1 https://github.com/zed-industries/zed ${ZED_SRC_DIR}"
        exit 1
    fi
    success "Zed 源码目录存在：${ZED_SRC_DIR}"
}

# ── 版本信息 ──────────────────────────────────────────────────────────────────
get_version_info() {
    COMMIT_SHA=$(git -C "${ZED_SRC_DIR}" rev-parse HEAD)
    COMMIT_SHORT="${COMMIT_SHA:0:7}"
    BUILD_DATE=$(date -u +%Y%m%d)
    PKGVER="0.${BUILD_DATE}.${COMMIT_SHORT}"
    TAG_NAME="zed-nightly-${BUILD_DATE}-${COMMIT_SHORT}"
}

# ── 阶段 1：编译 ──────────────────────────────────────────────────────────────
do_compile() {
    step "阶段 1/4：编译 Zed（zed + cli）"

    # 设置 nightly channel
    echo -n "nightly" > "${ZED_SRC_DIR}/crates/zed/RELEASE_CHANNEL"
    info "RELEASE_CHANNEL = $(cat "${ZED_SRC_DIR}/crates/zed/RELEASE_CHANNEL")"

    # 安装所需 rust target
    if command -v rustup &>/dev/null; then
        rustup target add wasm32-wasip2 wasm32-unknown-unknown 2>/dev/null || true
    fi

    info "开始编译（使用 mold 链接器加速）..."
    info "commit: ${COMMIT_SHORT}，版本: ${PKGVER}"

    cd "${ZED_SRC_DIR}"
    RUSTFLAGS="-C link-arg=-fuse-ld=mold -C link-args=-Wl,--disable-new-dtags,-rpath,\$ORIGIN/../lib" \
    CARGO_INCREMENTAL=0 \
    CARGO_TERM_COLOR=always \
        cargo build --release --package zed --package cli 2>&1

    local zed_size cli_size
    zed_size=$(du -sh target/release/zed | cut -f1)
    cli_size=$(du -sh target/release/cli | cut -f1)
    success "编译完成：zed=${zed_size}  cli=${cli_size}"
    cd "${REPO_ROOT}"
}

# ── 阶段 2：打包为 tar.gz ─────────────────────────────────────────────────────
do_package() {
    step "阶段 2/4：打包为 tar.gz（对齐官方 bundle-linux 结构）"

    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"

    local target_dir="${ZED_SRC_DIR}/target"
    local stage_dir="${BUILD_DIR}/stage"
    local zed_app="${stage_dir}/zed-nightly.app"

    # ── 1. Strip 调试符号 ────────────────────────────────────────────────────
    info "objcopy --strip-debug..."
    local size_before size_after
    size_before=$(du -sh "${target_dir}/release/zed" | cut -f1)
    cp "${target_dir}/release/zed" "${BUILD_DIR}/zed.work"
    cp "${target_dir}/release/cli" "${BUILD_DIR}/cli.work"
    objcopy --strip-debug "${BUILD_DIR}/zed.work"
    objcopy --strip-debug "${BUILD_DIR}/cli.work"
    size_after=$(du -sh "${BUILD_DIR}/zed.work" | cut -f1)
    success "zed strip：${size_before} → ${size_after}"

    # ── 2. 构建 .app 目录结构 ────────────────────────────────────────────────
    info "构建 zed-nightly.app 目录结构..."
    mkdir -p "${zed_app}/bin"
    mkdir -p "${zed_app}/libexec"
    mkdir -p "${zed_app}/lib"
    mkdir -p "${zed_app}/share/icons/hicolor/512x512/apps"
    mkdir -p "${zed_app}/share/icons/hicolor/1024x1024/apps"
    mkdir -p "${zed_app}/share/applications"

    cp "${BUILD_DIR}/cli.work" "${zed_app}/bin/zed"
    chmod 755 "${zed_app}/bin/zed"
    cp "${BUILD_DIR}/zed.work" "${zed_app}/libexec/zed-editor"
    chmod 755 "${zed_app}/libexec/zed-editor"

    # ── 3. 收集运行时共享库 ──────────────────────────────────────────────────
    info "收集运行时共享库（排除系统基础库）..."
    local lib_count=0
    while IFS= read -r lib; do
        [ -z "$lib" ] && continue
        [[ "$lib" == linux-vdso* ]] && continue
        cp "$lib" "${zed_app}/lib/" 2>/dev/null && (( lib_count++ )) || true
    done < <(
        ldd "${BUILD_DIR}/zed.work" \
            | awk '{print $3}' \
            | grep -v '^\(not\|linux-vdso\)' \
            | grep -Ev '\<(libstdc\+\+\.so|libc\.so|libgcc_s\.so|libm\.so|libpthread\.so|libdl\.so|libasound\.so)\>' \
            | grep -v '^$' \
            | sort -u
    )
    success "收集了 ${lib_count} 个运行时共享库"

    # ── 4. 图标 ──────────────────────────────────────────────────────────────
    info "复制 nightly 专属图标..."
    cp "${ZED_SRC_DIR}/crates/zed/resources/app-icon-nightly.png" \
        "${zed_app}/share/icons/hicolor/512x512/apps/zed.png"
    cp "${ZED_SRC_DIR}/crates/zed/resources/app-icon-nightly@2x.png" \
        "${zed_app}/share/icons/hicolor/1024x1024/apps/zed.png"
    success "图标已复制（512x512 + 1024x1024）"

    # ── 5. 生成 desktop 文件 ─────────────────────────────────────────────────
    info "从官方模板生成 desktop 文件..."
    export APP_NAME="Zed Nightly"
    export APP_CLI="zed"
    export APP_ICON="zed"
    export APP_ARGS="%U"
    export DO_STARTUP_NOTIFY="true"
    envsubst < "${ZED_SRC_DIR}/crates/zed/resources/zed.desktop.in" \
        > "${zed_app}/share/applications/${APP_ID}.desktop"
    # 追加 StartupWMClass（与 zed-editor 运行时设置的 app_id 一致）
    echo "StartupWMClass=${APP_ID}" >> "${zed_app}/share/applications/${APP_ID}.desktop"
    chmod +x "${zed_app}/share/applications/${APP_ID}.desktop"
    success "desktop 文件已生成（含 StartupWMClass=${APP_ID}）"

    # ── 6. 打包 ──────────────────────────────────────────────────────────────
    info "打包为 tar.gz..."
    tar -czf "${BUILD_DIR}/${ARCHIVE_NAME}" -C "${stage_dir}" "zed-nightly.app"
    sha256sum "${BUILD_DIR}/${ARCHIVE_NAME}" > "${BUILD_DIR}/${ARCHIVE_NAME}.sha256"
    local archive_size sha256
    archive_size=$(du -sh "${BUILD_DIR}/${ARCHIVE_NAME}" | cut -f1)
    sha256=$(awk '{print $1}' "${BUILD_DIR}/${ARCHIVE_NAME}.sha256")

    success "打包完成：${ARCHIVE_NAME}（${archive_size}）"
    info "SHA256：${sha256}"

    echo ""
    info "包内结构："
    tar -tzvf "${BUILD_DIR}/${ARCHIVE_NAME}"
}

# ── 阶段 3：makepkg ───────────────────────────────────────────────────────────
do_makepkg() {
    step "阶段 3/4：makepkg 构建 pacman 包"

    local archive="${BUILD_DIR}/${ARCHIVE_NAME}"
    if [ ! -f "$archive" ]; then
        error "找不到 tar.gz，请先执行 package 阶段"
        exit 1
    fi

    local sha256
    sha256=$(awk '{print $1}' "${BUILD_DIR}/${ARCHIVE_NAME}.sha256")

    rm -rf "${PKG_DIR}"
    mkdir -p "${PKG_DIR}"

    # 将 tar.gz 放到 makepkg 工作目录（makepkg 要求 source 文件在旁边）
    cp "$archive" "${PKG_DIR}/${ARCHIVE_NAME}"

    info "生成 PKGBUILD（pkgver=${PKGVER}）..."

    # 读取仓库 PKGBUILD 的 depends 段，替换版本/source/sha256
    # 直接内联生成，避免 envsubst 污染 PKGBUILD 中的 shell 变量
    cat > "${PKG_DIR}/PKGBUILD" << PKGEOF
# Maintainer: zerx-lab <https://github.com/zerx-lab>
# 本文件由 build-and-test.sh 自动生成用于本地测试

pkgname=zerx-lab-zed-nightly-bin
pkgver=${PKGVER}
pkgrel=1
pkgdesc="Zed 编辑器 Nightly 预编译版本（来自 main 分支每日构建）"
arch=('x86_64')
url="https://zed.dev"
license=('GPL-3.0-or-later' 'AGPL-3.0-or-later')
provides=('zed')
conflicts=('zed' 'zed-git' 'zed-preview' 'zed-preview-bin')
depends=(
    'alsa-lib'
    'fontconfig'
    'libgit2'
    'libxcb'
    'libxkbcommon-x11'
    'openssl'
    'sqlite'
    'zlib'
    'libxkbcommon'
    'wayland'
    'vulkan-icd-loader'
)
optdepends=(
    'clang: C/C++ language support'
    'rust: Rust language support'
)
source_x86_64=("${ARCHIVE_NAME}")
sha256sums_x86_64=('${sha256}')
options=('!strip')

package() {
    local _appdir="\${srcdir}/zed-nightly.app"
    local _installdir="\${pkgdir}/usr/lib/zed-nightly.app"
    local _app_prefix="${APP_PREFIX}"

    if [ ! -d "\${_appdir}" ]; then
        echo "错误：找不到解压后的 zed-nightly.app 目录"
        ls "\${srcdir}"
        return 1
    fi

    # ── 完整 .app 目录结构 ───────────────────────────────────────────────────
    # cli（bin/zed）通过 rpath \$ORIGIN/../lib 查找共享库，
    # 通过相对路径 ../libexec/zed-editor 调用编辑器主进程，
    # 必须保持整个目录结构完整。
    install -dm755 "\${_installdir}/bin"
    install -dm755 "\${_installdir}/libexec"
    install -dm755 "\${_installdir}/lib"

    install -Dm755 "\${_appdir}/bin/zed" "\${_installdir}/bin/zed"
    install -Dm755 "\${_appdir}/libexec/zed-editor" "\${_installdir}/libexec/zed-editor"

    if [ -d "\${_appdir}/lib" ] && [ -n "\$(ls -A "\${_appdir}/lib" 2>/dev/null)" ]; then
        cp -a "\${_appdir}/lib/." "\${_installdir}/lib/"
    fi

    # ── /usr/bin/zed 软链 ────────────────────────────────────────────────────
    install -dm755 "\${pkgdir}/usr/bin"
    ln -sf "/usr/lib/zed-nightly.app/bin/zed" "\${pkgdir}/usr/bin/zed"

    # ── 图标（hicolor 主题规范）─────────────────────────────────────────────
    install -Dm644 "\${_appdir}/share/icons/hicolor/512x512/apps/zed.png" \
        "\${pkgdir}/usr/share/icons/hicolor/512x512/apps/zed.png"
    install -Dm644 "\${_appdir}/share/icons/hicolor/1024x1024/apps/zed.png" \
        "\${pkgdir}/usr/share/icons/hicolor/1024x1024/apps/zed.png"

    # ── desktop 文件（对齐官方 install.sh）──────────────────────────────────
    local _desktop_dst="\${pkgdir}/usr/share/applications/${APP_ID}.desktop"
    install -Dm644 "\${_appdir}/share/applications/${APP_ID}.desktop" "\${_desktop_dst}"

    # Icon=zed 保持不变（图标已装入 /usr/share/icons/hicolor/，由桌面环境查找）
    # Exec/TryExec 改为 cli 绝对路径（对齐 install.sh 的 sed 替换，避免依赖 PATH）
    sed -i "s|Exec=zed |Exec=\${_app_prefix}/bin/zed |g" "\${_desktop_dst}"
    sed -i "s|Exec=zed\$|Exec=\${_app_prefix}/bin/zed|g" "\${_desktop_dst}"
    sed -i "s|TryExec=zed|TryExec=\${_app_prefix}/bin/zed|g" "\${_desktop_dst}"
    # StartupWMClass 已在打包时写入，无需再追加
}
PKGEOF

    info "运行 makepkg..."
    (cd "${PKG_DIR}" && makepkg --noconfirm --nodeps 2>&1)

    local pkg_file
    pkg_file=$(ls "${PKG_DIR}"/*.pkg.tar.zst 2>/dev/null | head -1)
    if [ -z "$pkg_file" ]; then
        error "makepkg 未生成 .pkg.tar.zst"
        exit 1
    fi

    local pkg_size
    pkg_size=$(du -sh "$pkg_file" | cut -f1)
    success "makepkg 完成：$(basename "$pkg_file")（${pkg_size}）"

    echo ""
    info "包内文件（非目录）："
    tar --use-compress-program=zstd -tvf "$pkg_file" 2>/dev/null \
        | grep '^-' | awk '{print "  " $NF}'
}

# ── 阶段 4：安装并验证 ────────────────────────────────────────────────────────
do_install() {
    step "阶段 4/4：pacman 安装并验证"

    local pkg_file
    pkg_file=$(ls "${PKG_DIR}"/*.pkg.tar.zst 2>/dev/null | head -1)
    if [ -z "$pkg_file" ]; then
        error "找不到 .pkg.tar.zst，请先执行 makepkg 阶段"
        exit 1
    fi

    info "安装：$(basename "$pkg_file")"
    sudo pacman -U --noconfirm "$pkg_file" 2>&1

    echo ""
    info "验证安装结果..."
    local failed=0

    # 1. which zed
    if which zed &>/dev/null; then
        success "which zed → $(which zed)"
    else
        error "which zed 失败"; (( failed++ ))
    fi

    # 2. 软链正确
    local link
    link=$(readlink /usr/bin/zed 2>/dev/null || echo "")
    if [ "$link" = "/usr/lib/zed-nightly.app/bin/zed" ]; then
        success "软链：/usr/bin/zed → ${link}"
    else
        error "软链异常：${link}"; (( failed++ ))
    fi

    # 3. zed --version
    local ver
    ver=$(zed --version 2>&1)
    if echo "$ver" | grep -q 'nightly'; then
        success "zed --version → ${ver}"
    else
        error "版本输出异常：${ver}"; (( failed++ ))
    fi

    # 4. rpath
    local rpath
    rpath=$(readelf -d /usr/lib/zed-nightly.app/bin/zed 2>/dev/null \
        | grep -E 'RPATH|RUNPATH' | awk '{print $NF}' || true)
    if echo "$rpath" | grep -q 'ORIGIN'; then
        success "rpath：${rpath}"
    else
        error "rpath 异常：${rpath:-空}"; (( failed++ ))
    fi

    # 5. cli → zed-editor 查找路径
    local editor_path="/usr/lib/zed-nightly.app/libexec/zed-editor"
    if [ -f "$editor_path" ]; then
        success "zed-editor 存在：${editor_path}（$(du -sh "$editor_path" | cut -f1)）"
    else
        error "zed-editor 不存在"; (( failed++ ))
    fi

    # 6. ldd 无缺失库
    local missing_libs
    missing_libs=$(ldd /usr/lib/zed-nightly.app/bin/zed 2>&1 | grep 'not found' || true)
    if [ -z "$missing_libs" ]; then
        success "ldd：无缺失共享库"
    else
        error "ldd 检测到缺失库：\n${missing_libs}"; (( failed++ ))
    fi

    # 7. 图标
    if [ -f /usr/share/icons/hicolor/512x512/apps/zed.png ] && \
       [ -f /usr/share/icons/hicolor/1024x1024/apps/zed.png ]; then
        success "图标：512x512 + 1024x1024 均存在"
    else
        error "图标文件缺失"; (( failed++ ))
    fi

    # 8. desktop 文件关键字段
    local desktop="/usr/share/applications/${APP_ID}.desktop"
    if [ -f "$desktop" ]; then
        success "desktop 文件存在：${desktop}"
        echo ""
        info "desktop 文件关键字段："
        grep -E '^(Exec|TryExec|Icon|StartupWMClass|StartupNotify)' "$desktop" \
            | sed 's/^/  /'

        # 检查 StartupWMClass
        if grep -q "StartupWMClass=${APP_ID}" "$desktop"; then
            success "StartupWMClass=${APP_ID} ✓（KDE 启动图标匹配正常）"
        else
            warn "StartupWMClass 缺失或不匹配，KDE 启动时可能显示终端图标"
            (( failed++ ))
        fi

        # 检查 Exec 是否为绝对路径
        if grep -q "Exec=${APP_PREFIX}/bin/zed" "$desktop"; then
            success "Exec 已替换为绝对路径 ✓"
        else
            warn "Exec 未替换为绝对路径"
            (( failed++ ))
        fi

        # 检查 Icon 未被误替换为不存在的路径
        local icon_val
        icon_val=$(grep '^Icon=' "$desktop" | head -1 | cut -d= -f2-)
        if [ "$icon_val" = "zed" ]; then
            success "Icon=zed（由 hicolor 主题解析）✓"
        else
            warn "Icon=${icon_val}（注意：若此路径不存在则图标会丢失）"
        fi
    else
        error "desktop 文件不存在"; (( failed++ ))
    fi

    # 9. pacman 包信息
    echo ""
    info "pacman -Qi："
    pacman -Qi zerx-lab-zed-nightly-bin 2>&1 \
        | grep -E '^(名字|版本|描述|安装后大小|安装日期)' \
        | sed 's/^/  /'

    # 总结
    echo ""
    echo "════════════════════════════════════════════════"
    if [ "$failed" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}全部验证通过 ✓${NC}"
    else
        echo -e "${RED}${BOLD}有 ${failed} 项验证失败，请检查上方输出${NC}"
    fi
    echo "════════════════════════════════════════════════"
}

# ── 清理 ──────────────────────────────────────────────────────────────────────
do_clean() {
    step "清理构建产物"
    rm -rf "${BUILD_DIR}" "${PKG_DIR}"
    success "已清理：${BUILD_DIR}  ${PKG_DIR}"
}

# ── 入口 ──────────────────────────────────────────────────────────────────────
STAGE="${1:-all}"

echo "════════════════════════════════════════════════"
echo -e "${BOLD} Zed Nightly 本地全流程测试${NC}"
echo " 仓库根目录  : ${REPO_ROOT}"
echo " Zed 源码    : ${ZED_SRC_DIR}"
echo " 构建输出    : ${BUILD_DIR}"
echo " 执行阶段    : ${STAGE}"
echo "════════════════════════════════════════════════"
echo ""

case "$STAGE" in
    clean)
        do_clean
        exit 0
        ;;
    compile|package|makepkg|install|all)
        check_deps
        get_version_info
        info "commit  : ${COMMIT_SHORT}"
        info "pkgver  : ${PKGVER}"
        ;;
    *)
        error "未知阶段：${STAGE}"
        echo "可选值：all / compile / package / makepkg / install / clean"
        exit 1
        ;;
esac

case "$STAGE" in
    compile)  do_compile ;;
    package)  do_package ;;
    makepkg)  do_makepkg ;;
    install)  do_install ;;
    all)
        do_compile
        do_package
        do_makepkg
        do_install
        ;;
esac
