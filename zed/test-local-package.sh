#!/usr/bin/env bash
# 本地测试脚本：验证 Zed Nightly 打包逻辑，对齐官方 bundle-linux 结构
# 用法：bash zed/test-local-package.sh [ZED_SRC_DIR]
#   ZED_SRC_DIR: 已编译好的 Zed 源码目录（默认为 /tmp/zed-src）
#
# 前置条件：
#   cd <zed源码目录>
#   echo -n nightly > crates/zed/RELEASE_CHANNEL
#   RUSTFLAGS="-C link-arg=-fuse-ld=mold -C link-args=-Wl,--disable-new-dtags,-rpath,\$ORIGIN/../lib" \
#     cargo build --release --package zed --package cli

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────
ZED_SRC_DIR="${1:-/tmp/zed-src}"
WORK_DIR="/tmp/zed-nightly-test"
ARCHIVE_NAME="zed-nightly-linux-x86_64.tar.gz"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR ]${NC} $*" >&2; }

# ── 前置检查 ──────────────────────────────────────────────────────────────────
check_deps() {
    info "检查依赖工具..."
    local missing=()
    for cmd in objcopy ldd tar sha256sum envsubst du stat; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        error "缺少以下工具: ${missing[*]}"
        exit 1
    fi
    success "依赖检查通过"
}

check_zed_build() {
    local zed_bin="${ZED_SRC_DIR}/target/release/zed"
    local cli_bin="${ZED_SRC_DIR}/target/release/cli"
    local ok=true

    if [ ! -f "$zed_bin" ]; then
        error "找不到 zed 二进制: $zed_bin"
        ok=false
    fi
    if [ ! -f "$cli_bin" ]; then
        error "找不到 cli 二进制: $cli_bin"
        warn "需要编译 cli crate，请在 Zed 源码目录执行："
        warn "  RUSTFLAGS=\"-C link-arg=-fuse-ld=mold -C link-args=-Wl,--disable-new-dtags,-rpath,\\\$ORIGIN/../lib\" \\"
        warn "    cargo build --release --package zed --package cli"
        ok=false
    fi
    if [ ! -f "${ZED_SRC_DIR}/crates/zed/resources/app-icon-nightly.png" ]; then
        error "找不到 nightly 图标，路径是否正确？"
        ok=false
    fi
    if [ ! -f "${ZED_SRC_DIR}/crates/zed/resources/zed.desktop.in" ]; then
        error "找不到 desktop 模板文件"
        ok=false
    fi

    [ "$ok" = true ] || exit 1
    success "编译产物检查通过：zed + cli 均存在"
}

# ── 主流程 ────────────────────────────────────────────────────────────────────
run_test() {
    info "清理工作目录: $WORK_DIR"
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR/dist"

    local target_dir="${ZED_SRC_DIR}/target"
    local stage_dir="${WORK_DIR}/stage"
    local zed_app="${stage_dir}/zed-nightly.app"

    # ── 步骤 1：strip 调试符号 ────────────────────────────────────────────────
    echo ""
    info "步骤 1/6：strip 调试符号（objcopy --strip-debug）"

    # 复制副本操作，不破坏原始编译结果
    mkdir -p "${WORK_DIR}/bin"
    cp "${target_dir}/release/zed" "${WORK_DIR}/bin/zed"
    cp "${target_dir}/release/cli" "${WORK_DIR}/bin/cli"

    local size_zed_before size_cli_before
    size_zed_before=$(du -sh "${WORK_DIR}/bin/zed" | cut -f1)
    size_cli_before=$(du -sh "${WORK_DIR}/bin/cli" | cut -f1)

    objcopy --strip-debug "${WORK_DIR}/bin/zed"
    objcopy --strip-debug "${WORK_DIR}/bin/cli"

    local size_zed_after size_cli_after
    size_zed_after=$(du -sh "${WORK_DIR}/bin/zed" | cut -f1)
    size_cli_after=$(du -sh "${WORK_DIR}/bin/cli" | cut -f1)

    local bytes_before bytes_after saved
    bytes_before=$(stat -c%s "${target_dir}/release/zed")
    bytes_after=$(stat -c%s "${WORK_DIR}/bin/zed")
    saved=$(( (bytes_before - bytes_after) / 1024 / 1024 ))

    success "zed  : ${size_zed_before} -> ${size_zed_after}（节省约 ${saved} MB）"
    success "cli  : ${size_cli_before} -> ${size_cli_after}"

    # ── 步骤 2：构建 .app 目录结构 ───────────────────────────────────────────
    echo ""
    info "步骤 2/6：构建 zed-nightly.app 目录结构"

    mkdir -p "${zed_app}/bin"
    mkdir -p "${zed_app}/libexec"
    mkdir -p "${zed_app}/lib"
    mkdir -p "${zed_app}/share/icons/hicolor/512x512/apps"
    mkdir -p "${zed_app}/share/icons/hicolor/1024x1024/apps"
    mkdir -p "${zed_app}/share/applications"

    # cli wrapper -> bin/zed（用户调用入口）
    cp "${WORK_DIR}/bin/cli" "${zed_app}/bin/zed"
    chmod 755 "${zed_app}/bin/zed"

    # 编辑器主进程 -> libexec/zed-editor
    cp "${WORK_DIR}/bin/zed" "${zed_app}/libexec/zed-editor"
    chmod 755 "${zed_app}/libexec/zed-editor"

    success "二进制已放置：bin/zed (cli) + libexec/zed-editor (editor)"

    # ── 步骤 3：收集运行时共享库 ─────────────────────────────────────────────
    echo ""
    info "步骤 3/6：收集运行时共享库（排除系统基础库）"

    # 与官方 bundle-linux 的 find_libs() 逻辑一致
    local lib_count=0
    while IFS= read -r lib; do
        [ -z "$lib" ] && continue
        [ "$lib" = "not" ] && continue
        [[ "$lib" == linux-vdso* ]] && continue
        cp "$lib" "${zed_app}/lib/" 2>/dev/null && (( lib_count++ )) || true
    done < <(
        ldd "${WORK_DIR}/bin/zed" \
            | awk '{print $3}' \
            | grep -v '^\(not\|linux-vdso\)' \
            | grep -Ev '\<(libstdc\+\+\.so|libc\.so|libgcc_s\.so|libm\.so|libpthread\.so|libdl\.so|libasound\.so)\>' \
            | grep -v '^$' \
            | sort -u
    )

    success "收集了 ${lib_count} 个运行时共享库"
    if [ "$lib_count" -gt 0 ]; then
        ls "${zed_app}/lib/" | sed 's/^/    /'
    fi

    # ── 步骤 4：复制图标 ─────────────────────────────────────────────────────
    echo ""
    info "步骤 4/6：复制 nightly 图标"

    local icon_512="${ZED_SRC_DIR}/crates/zed/resources/app-icon-nightly.png"
    local icon_1024="${ZED_SRC_DIR}/crates/zed/resources/app-icon-nightly@2x.png"

    cp "$icon_512" "${zed_app}/share/icons/hicolor/512x512/apps/zed.png"
    success "已复制 512x512 图标"

    if [ -f "$icon_1024" ]; then
        cp "$icon_1024" "${zed_app}/share/icons/hicolor/1024x1024/apps/zed.png"
        success "已复制 1024x1024 图标"
    else
        warn "未找到 1024x1024 图标: $icon_1024"
    fi

    # ── 步骤 5：从官方模板生成 desktop 文件 ──────────────────────────────────
    echo ""
    info "步骤 5/6：用 envsubst 从官方模板生成 desktop 文件"

    export APP_NAME="Zed Nightly"
    export APP_CLI="zed"
    export APP_ICON="zed"
    export APP_ARGS="%U"
    export DO_STARTUP_NOTIFY="true"
    local app_id="dev.zed.Zed-Nightly"

    envsubst < "${ZED_SRC_DIR}/crates/zed/resources/zed.desktop.in" \
        > "${zed_app}/share/applications/${app_id}.desktop"
    chmod +x "${zed_app}/share/applications/${app_id}.desktop"

    success "desktop 文件已生成: ${app_id}.desktop"
    echo "── desktop 内容 ──────────────────────────────"
    cat "${zed_app}/share/applications/${app_id}.desktop"
    echo "──────────────────────────────────────────────"

    # ── 步骤 6：打包并验证 ───────────────────────────────────────────────────
    echo ""
    info "步骤 6/6：打包为 tar.gz 并验证"

    local out_archive="${WORK_DIR}/dist/${ARCHIVE_NAME}"
    tar -czf "$out_archive" -C "$stage_dir" "zed-nightly.app"
    sha256sum "$out_archive" > "${out_archive}.sha256"

    local archive_size sha256
    archive_size=$(du -sh "$out_archive" | cut -f1)
    sha256=$(awk '{print $1}' "${out_archive}.sha256")

    success "打包完成: ${ARCHIVE_NAME} (${archive_size})"
    echo "  SHA256: ${sha256}"

    echo ""
    echo "── 包内结构 ─────────────────────────────────"
    tar -tzvf "$out_archive"
    echo "─────────────────────────────────────────────"

    # 验证关键文件
    echo ""
    info "验证包内关键文件..."
    local file_list
    file_list=$(tar -tzf "$out_archive")

    local missing_files=()
    echo "$file_list" | grep -qF "zed-nightly.app/bin/zed"           || missing_files+=("bin/zed (cli)")
    echo "$file_list" | grep -qF "zed-nightly.app/libexec/zed-editor" || missing_files+=("libexec/zed-editor")
    echo "$file_list" | grep -qF "512x512/apps/zed.png"               || missing_files+=("512x512 图标")
    echo "$file_list" | grep -qF "1024x1024/apps/zed.png"             || missing_files+=("1024x1024 图标")
    echo "$file_list" | grep -qF "dev.zed.Zed-Nightly.desktop"        || missing_files+=("desktop 文件")

    if [ ${#missing_files[@]} -gt 0 ]; then
        warn "包中缺少以下文件: ${missing_files[*]}"
    else
        success "包结构验证通过，所有关键文件均存在"
    fi

    # 验证 rpath
    echo ""
    info "验证 cli 的 rpath..."
    if command -v readelf &>/dev/null; then
        local rpath
        rpath=$(readelf -d "${zed_app}/bin/zed" 2>/dev/null \
            | grep -E 'RPATH|RUNPATH' | awk '{print $NF}' || true)
        if echo "$rpath" | grep -q 'ORIGIN'; then
            success "rpath 含 \$ORIGIN: $rpath"
        else
            warn "未检测到 \$ORIGIN rpath（可能构建时未传 -rpath 参数）: ${rpath:-空}"
        fi
    fi

    # ── 总结 ─────────────────────────────────────────────────────────────────
    echo ""
    echo "════════════════════════════════════════════════"
    echo -e "${GREEN}测试完成，结果汇总${NC}"
    echo "  zed 大小（strip 前）  : ${size_zed_before}"
    echo "  zed 大小（strip 后）  : ${size_zed_after}"
    echo "  cli 大小（strip 后）  : ${size_cli_after}"
    echo "  运行时共享库数量      : ${lib_count}"
    echo "  tar.gz 压缩包大小     : ${archive_size}"
    echo "  SHA256                : ${sha256}"
    echo "  输出目录              : ${WORK_DIR}/dist/"
    echo "════════════════════════════════════════════════"
    echo ""
    echo "手动验证安装（解压后运行）："
    echo "  tar -xzf ${out_archive} -C /tmp/"
    echo "  /tmp/zed-nightly.app/bin/zed --version"
}

# ── 入口 ──────────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════════════"
echo " Zed Nightly 本地打包测试"
echo " Zed 源码目录: ${ZED_SRC_DIR}"
echo "════════════════════════════════════════════════"
echo ""

check_deps
check_zed_build
run_test
