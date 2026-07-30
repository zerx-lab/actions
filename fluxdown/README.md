# FluxDown AUR 自动化

维护 FluxDown 相关 AUR 包，每日定时（`check-updates.yml`，UTC 00:00）对比上游版本与 AUR 版本，有更新时自动改写 PKGBUILD、重新生成 .SRCINFO 并推送到 AUR。

## 包列表

| AUR 包 | 目录 | 上游版本来源 | 工作流 |
|--------|------|--------------|--------|
| [`zerx-lab-fluxdown-bin`](https://aur.archlinux.org/packages/zerx-lab-fluxdown-bin) | [`aur/`](aur/) | `https://fluxdown.zerx.dev/api/release`（桌面 GUI，linux-x64 tarball） | [fluxdown-aur-update.yml](../.github/workflows/fluxdown-aur-update.yml) |
| [`fluxdown-cli-bin`](https://aur.archlinux.org/packages/fluxdown-cli-bin) | [`aur-cli/`](aur-cli/) | GitHub Releases `cli-v*` 稳定 tag（musl 静态二进制，x86_64 + aarch64） | [fluxdown-cli-aur-update.yml](../.github/workflows/fluxdown-cli-aur-update.yml) |

## fluxdown-cli-bin 说明

- 上游产物来自 FluxDown 仓库 `release.yml` 的 `build-cli-binaries` job：`FluxDown-CLI-<版本>-linux-{x64,arm64}.tar.gz`，musl 静态链接、零运行时依赖，解压即单个 `fluxdown` 二进制。
- 预发布（`cli-vX.Y.Z-rc.N`，GitHub prerelease）不会推送到 AUR，工作流只取最新稳定 tag。
- SHA256 在工作流内实际下载 tarball 计算，并与 Release 附带的 `SHA256SUMS.txt` 交叉校验，不一致即失败。
- 与桌面包 `zerx-lab-fluxdown-bin` 可共存：桌面包安装 `/usr/bin/flux_down`，CLI 包安装 `/usr/bin/fluxdown`，无文件冲突。

## 所需 Secrets

| Secret | 用途 |
|--------|------|
| `AUR_SSH_PRIVATE_KEY` | AUR 账户 SSH 私钥，推送 PKGBUILD / .SRCINFO 到 `aur.archlinux.org` |

## 手动触发

```bash
# 桌面包（留空 version 则取上游 API 最新版）
gh workflow run fluxdown-aur-update.yml

# CLI 包（留空 version 则取 GitHub Releases 最新稳定 cli-v* tag）
gh workflow run fluxdown-cli-aur-update.yml
gh workflow run fluxdown-cli-aur-update.yml --field version=0.2.3
```
