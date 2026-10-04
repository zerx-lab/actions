# 滴答清单（Dida365）自动化服务

监测滴答清单 Linux 版本更新，将官方 x86_64 DEB 重新打包并同步到 AUR 包 `zerx-lab-dida365-bin`。当前流程不创建 GitHub Release。

## 工作流

- [`check-updates.yml`](../.github/workflows/check-updates.yml)：每天 UTC 00:00 检测版本，与 AUR 比较，有更新时调用滴答清单更新工作流。
- [`dida365-linux-release.yml`](../.github/workflows/dida365-linux-release.yml)：支持 `workflow_call` 和手动 `workflow_dispatch`；手动指定 `version` 时按该版本下载，留空时检测最新版。

两个入口共用 [`scripts/upstream.sh`](scripts/upstream.sh)。官网下载入口对默认 curl User-Agent 返回 HTTP 404，检测时必须使用 `Mozilla/5.0`。脚本只读取官网响应中的重定向地址，以官方 CDN 的 Linux x64 DEB 文件名提取版本，**不跟随重定向、不连接 CDN**，避免下载节点故障阻塞每日版本检查。官网连接超时为 10 秒、请求总时限为 30 秒；HTTP 错误或地址不符合预期时明确报错，不写出空版本。

更新流程：
1. 确定目标版本。
2. 从固定版本的官方 CDN 地址下载 `dida-<版本>-amd64.deb`，不再使用随最新版变化的下载入口。CDN 使用默认 DNS，不固定 IP、不改用第三方下载镜像；连接超时 15 秒、单次下载时限 300 秒，瞬时网络错误最多重试 3 次，重试窗口 600 秒。下载最终失败会直接终止，不更新或发布包定义。
3. 核对 DEB 内部 `Version` 与目标版本一致，再计算 SHA256。
4. 更新 `aur/PKGBUILD` 的版本和校验和，由发布 action 生成 `.SRCINFO` 并推送到 AUR。

PKGBUILD 也使用相同的固定版本 CDN 地址，避免上游更新后旧 PKGBUILD 下载到新包而校验失败。

## 验证和触发

在仓库根目录执行：

```bash
# 非发布检查：输出 version=<最新版本>
bash dida365/scripts/upstream.sh

# 工作流语法检查
actionlint .github/workflows/*.yml

# 发布到 AUR（留空 version 检测最新版）
gh workflow run dida365-linux-release.yml
# 指定版本
gh workflow run dida365-linux-release.yml --field version=8.0.20
```

本地打包建议在 Arch Linux 使用 devtools 干净 chroot：

```bash
cd dida365/aur
extra-x86_64-build
```

## 所需 Secrets

| Secret | 说明 |
|--------|------|
| `AUR_SSH_PRIVATE_KEY` | AUR 账户 SSH 私钥，用于推送包定义 |
