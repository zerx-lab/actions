#!/usr/bin/env bash
# 本地测试脚本：验证 Zed Nightly 打包逻辑（strip 效果 + 包结构）
# 用法：bash zed/test-local-package.sh [ZED_SRC_DIR]
#   ZED_SRC_DIR: 已编译好的 Zed 源码目录（默认为 /tmp/zed-src）

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────
ZED_SRC_DIR="${1:-/tmp/zed-src}"
WORK_DIR="/tmp/zed-nightly-test"
BUILD_DATE=$(date -u +%Y%m%d)
PKGVER="0.${BUILD_DATE}.test001"
ARCHIVE_NAME="zed-nightly-linux-x86_64.tar.gz"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── 前置检查 ──────────────────────────────────────────────────────────────────
check_deps() {
    info "检查依赖工具..."
    local missing=()
    for cmd in objcopy strip du tar sha256sum; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        error "缺少以下工具: ${missing[*]}"
        exit 1
    fi
    success "依赖检查通过"
}

check_zed_binary() {
    local zed_bin="${ZED_SRC_DIR}/target/release/zed"
    if [ ! -f "$zed_bin" ]; then
        error "找不到 Zed 二进制文件: $zed_bin"
        echo ""
        echo "请先编译 Zed："
        echo "  git clone https://github.com/zed-industries/zed $ZED_SRC_DIR"
        echo "  cd $ZED_SRC_DIR"
        echo "  echo -n nightly > crates/zed/RELEASE_CHANNEL"
        echo "  cargo build --release --package zed"
        exit 1
    fi
    success "找到 Zed 二进制: $zed_bin"
}

# ── 主流程 ────────────────────────────────────────────────────────────────────
run_test() {
    info "清理工作目录: $WORK_DIR"
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR/dist"

    local zed_bin="${ZED_SRC_DIR}/target/release/zed"
    local dist_dir="${WORK_DIR}/dist/zed-${PKGVER}"

    # ── 步骤 1：记录 strip 前的大小 ──────────────────────────────────────────
    echo ""
    info "步骤 1/5：检查原始二进制大小"
    local size_before
    size_before=$(du -sh "$zed_bin" | cut -f1)
    echo "  strip 前大小: ${size_before}"

    # 复制一份副本用于操作（不破坏原始编译结果）
    cp "$zed_bin" "${WORK_DIR}/zed.orig"
    cp "$zed_bin" "${WORK_DIR}/zed.work"

    # ── 步骤 2：strip 调试符号 ───────────────────────────────────────────────
    echo ""
    info "步骤 2/5：执行 objcopy --strip-debug"
    objcopy --strip-debug "${WORK_DIR}/zed.work"
    local size_after
    size_after=$(du -sh "${WORK_DIR}/zed.work" | cut -f1)
    echo "  strip 后大小: ${size_after}"

    # 对比 strip 前后大小（字节）
    local bytes_before bytes_after
    bytes_before=$(stat -c%s "${WORK_DIR}/zed.orig")
    bytes_after=$(stat -c%s "${WORK_DIR}/zed.work")
    local saved=$(( (bytes_before - bytes_after) / 1024 / 1024 ))
    success "strip 节省了约 ${saved} MB（${bytes_before} → ${bytes_after} 字节）"

    # ── 步骤 3：构建包目录结构 ───────────────────────────────────────────────
    echo ""
    info "步骤 3/5：构建包目录结构"
    mkdir -p "${dist_dir}"
    mkdir -p "${dist_dir}/share/icons/hicolor/512x512/apps"
    mkdir -p "${dist_dir}/share/icons/hicolor/1024x1024/apps"

    cp "${WORK_DIR}/zed.work" "${dist_dir}/zed"
    chmod 755 "${dist_dir}/zed"

    # 复制图标
    local icon_512="${ZED_SRC_DIR}/crates/zed/resources/app-icon-nightly.png"
    local icon_1024="${ZED_SRC_DIR}/crates/zed/resources/app-icon-nightly@2x.png"

    if [ -f "$icon_512" ]; then
        cp "$icon_512" "${dist_dir}/share/icons/hicolor/512x512/apps/zed.png"
        success "已复制 512x512 图标"
    else
        warn "未找到 512x512 图标: $icon_512"
    fi

    if [ -f "$icon_1024" ]; then
        cp "$icon_1024" "${dist_dir}/share/icons/hicolor/1024x1024/apps/zed.png"
        success "已复制 1024x1024 图标"
    else
        warn "未找到 1024x1024 图标: $icon_1024"
    fi

    # ── 步骤 4：打包并计算 SHA256 ────────────────────────────────────────────
    echo ""
    info "步骤 4/5：打包为 tar.gz"
    cd "${WORK_DIR}/dist"
    tar -czf "${ARCHIVE_NAME}" "zed-${PKGVER}/"
    sha256sum "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256"
    local archive_size
    archive_size=$(du -sh "${ARCHIVE_NAME}" | cut -f1)
    local sha256
    sha256=$(awk '{print $1}' "${ARCHIVE_NAME}.sha256")
    success "打包完成: ${ARCHIVE_NAME} (${archive_size})"
    echo "  SHA256: ${sha256}"
    cd - > /dev/null

    # ── 步骤 5：验证包结构 ───────────────────────────────────────────────────
    echo ""
    info "步骤 5/5：验证包内文件结构"
    local archive_path="${WORK_DIR}/dist/${ARCHIVE_NAME}"
    echo "── 包内容 ──────────────────────────────"
    tar -tzvf "${archive_path}"
    echo "────────────────────────────────────────"

    # 检查关键文件是否存在（用固定完整路径，避免 cd 后变量失效）
    # 注意：用子 shell + grep -c 避免 pipefail 下 grep -q 提前退出导致 tar SIGPIPE 误报
    local file_list
    file_list=$(tar -tzf "${archive_path}")
    local missing_files=()
    echo "${file_list}" | awk -F'/' 'NF==2 && $2=="zed"' | grep -q . \
        || missing_files+=("zed 二进制")
    echo "${file_list}" | grep -qF "512x512/apps/zed.png" \
        || missing_files+=("512x512 图标")
    echo "${file_list}" | grep -qF "1024x1024/apps/zed.png" \
        || missing_files+=("1024x1024 图标")

    if [ ${#missing_files[@]} -gt 0 ]; then
        warn "包中缺少以下文件: ${missing_files[*]}"
    else
        success "包结构验证通过，所有关键文件均存在"
    fi

    # ── 总结 ─────────────────────────────────────────────────────────────────
    echo ""
    echo "════════════════════════════════════════"
    echo -e "${GREEN}测试完成，结果汇总：${NC}"
    echo "  二进制大小（strip 前）: ${size_before}"
    echo "  二进制大小（strip 后）: ${size_after}"
    echo "  tar.gz 压缩包大小:      ${archive_size}"
    echo "  输出目录: ${WORK_DIR}/dist/"
    echo "════════════════════════════════════════"
}

# ── 入口 ──────────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════"
echo " Zed Nightly 本地打包测试"
echo " Zed 源码目录: ${ZED_SRC_DIR}"
echo "════════════════════════════════════════"
echo ""

check_deps
check_zed_binary
run_test
