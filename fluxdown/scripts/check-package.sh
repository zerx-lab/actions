#!/usr/bin/env bash
# 在 Linux Docker 中用 devtools 干净 chroot 验证，成功后才生成待发布元数据。
set -euo pipefail
package_dir=$(cd "${1:?package directory required}" && pwd)
source_dir=$(cd "${2:?download directory required}" && pwd)

docker run --rm --privileged --tmpfs /run \
  -v "$package_dir:/pkg" \
  -v "$source_dir:/sources:ro" \
  -w /pkg archlinux:base-devel bash -euc '
    pacman -Syu --noconfirm --needed devtools namcap
    # nspawn 需要宿主 machine ID；Docker 基础镜像没有初始化它。
    systemd-machine-id-setup
    useradd -m -U builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
    chmod 440 /etc/sudoers.d/builder
    cp /sources/*.tar.gz /pkg/
    chown -R builder:builder /pkg
    su builder -c "namcap PKGBUILD"
    su builder -c "extra-x86_64-build -r /tmp/archbuild"
    namcap ./*.pkg.tar.zst
    su builder -c "makepkg --printsrcinfo > .SRCINFO"
  '
