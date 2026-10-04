#!/usr/bin/env bash
# 在 Linux Docker 中用 devtools 干净 chroot 验证，成功后才生成待发布元数据。
set -euo pipefail
package_dir=$(cd "${1:?package directory required}" && pwd)
source_dir=$(cd "${2:?download directory required}" && pwd)

# devtools 创建 systemd scope；容器必须以 systemd 为 PID 1，不能仅运行 bash。
container=$(docker run --detach --privileged --cgroupns=host \
  --tmpfs /run --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "$package_dir:/pkg" \
  -v "$source_dir:/sources:ro" \
  -e container=docker --stop-signal SIGRTMIN+3 \
  -w /pkg archlinux:base-devel /usr/lib/systemd/systemd)
trap 'docker rm --force "$container" >/dev/null' EXIT

docker exec "$container" bash -euc '
    timeout 30 bash -c "until test -S /run/systemd/private; do sleep 0.2; done"
    systemctl start dbus
    pacman -Syu --noconfirm --needed devtools namcap
    useradd -m -U builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
    chmod 440 /etc/sudoers.d/builder
    cp /sources/*.tar.gz /pkg/
    chown -R builder:builder /pkg
    su builder -c "namcap PKGBUILD"
    # 使用默认 /var/lib/archbuild；systemd 的 /tmp 带 nosuid，会破坏 chroot 内 sudo。
    su builder -c "extra-x86_64-build"
    namcap ./*.pkg.tar.zst
    su builder -c "makepkg --printsrcinfo > .SRCINFO"
  '
