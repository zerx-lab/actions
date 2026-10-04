# FluxDown AUR 自动化

维护 FluxDown 相关 AUR 包，每日定时（`check-updates.yml`，UTC 00:00）对比上游版本与 AUR 版本。更新流程先校验发布资产，再改写 PKGBUILD，在 devtools 干净 chroot 中实际构包，成功后生成 .SRCINFO 并推送到 AUR。

## 包列表

| AUR 包 | 目录 | 上游版本来源 | 工作流 |
|--------|------|--------------|--------|
| [`zerx-lab-fluxdown-bin`](https://aur.archlinux.org/packages/zerx-lab-fluxdown-bin) | [`aur/`](aur/) | GitHub Releases `v*` 稳定 tag，含完整桌面 x86_64 资产 | [fluxdown-aur-update.yml](../.github/workflows/fluxdown-aur-update.yml) |
| [`fluxdown-cli-bin`](https://aur.archlinux.org/packages/fluxdown-cli-bin) | [`aur-cli/`](aur-cli/) | GitHub Releases `v*` 稳定 tag，含完整 CLI x86_64 + aarch64 资产 | [fluxdown-cli-aur-update.yml](../.github/workflows/fluxdown-cli-aur-update.yml) |

## 发布契约

- 检测与更新共用 `scripts/release.py`，从 `zerx-lab/FluxDown` 的统一 `vX.Y.Z` release 取版本，不再使用官网 latest API 或旧 `cli-v*` tag。
- 自动检测分页查询，排除 draft / prerelease，并按数字版本选择**该组件资产齐全**的最新稳定版。组件未随最新 release 发布时，继续使用此前完整版本；手动指定版本则严格查询对应 tag，资产缺失即失败，不回退到其他版本。
- 桌面资产：`FluxDown-<版本>-linux-x64.tar.gz` + `SHA256SUMS-app.txt`。CLI 资产：`FluxDown-CLI-<版本>-linux-{x64,arm64}.tar.gz` + `SHA256SUMS-cli.txt`。实际下载计算 SHA256，与对应组件清单逐项校验。
- 当前 PKGBUILD 面向 GPUI / 统一发布格式，不支持旧 Flutter tarball。

## 安装布局

- 桌面版将 `fluxdown-desktop`、`fluxdown-agent`、`fluxdownd`、`fluxdown_nmh` 放在 `/opt/fluxdown` 同一目录，满足兄弟进程查找要求；安装发布包根目录的 desktop 和 PNG，不再依赖 Flutter `lib/`、`data/`。
- GPUI 依赖对齐上游 Arch 包（含 X11 / Wayland / Vulkan 等）。桌面入口为 `/usr/bin/fluxdown-desktop`，agent 入口为 `/usr/bin/fluxdown-agent`；保留原 `flux_down` 入口，旧 `--silentStart` 自启请求转交 agent 的 `--autostart`，与上游升级行为一致。
- 继续安装 Chromium / Chrome 和 Firefox Native Messaging Host 清单，指向 `/opt/fluxdown/fluxdown_nmh`。
- CLI 是 musl 静态二进制，安装 `/usr/bin/fluxdown`；与桌面包无文件冲突。

## 构包校验

发布前运行 `scripts/check-package.sh`：以 systemd 为 PID 1 启动特权 Linux Docker 容器，挂载 cgroup 并为 `/run` 提供 tmpfs，满足 devtools 的 system bus / scope 要求；安装 devtools / namcap，使用 `extra-x86_64-build` 干净 chroot 构包，再用 `makepkg --printsrcinfo` 生成元数据。构包失败不会推送 AUR，退出时销毁专用容器。CLI 两架构下载均校验 SHA256，chroot 实际构建 x86_64 包。

本地回归与手动构包（后两条需要 Linux Docker，允许 privileged chroot）：

```bash
python3 -B -m unittest discover -s fluxdown/scripts -p 'test_*.py' -v
python3 fluxdown/scripts/release.py app 0.5.3 --download-dir /tmp/fluxdown-assets
bash fluxdown/scripts/check-package.sh fluxdown/aur /tmp/fluxdown-assets
```

手动构包时，PKGBUILD 的版本和校验和须与下载资产一致；GitHub 工作流会自动更新这些字段。

## 所需 Secrets

| Secret | 用途 |
|--------|------|
| `AUR_SSH_PRIVATE_KEY` | AUR 账户 SSH 私钥，推送 PKGBUILD / .SRCINFO 到 `aur.archlinux.org` |

## 手动触发

```bash
# 桌面包（留空 version 则取资产齐全的最新稳定版）
gh workflow run fluxdown-aur-update.yml

# CLI 包（同样从统一 v* release 选择 CLI 资产）
gh workflow run fluxdown-cli-aur-update.yml
gh workflow run fluxdown-cli-aur-update.yml --field version=0.5.3
```
