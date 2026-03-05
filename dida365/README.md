# 滴答清单（Dida365）自动化服务

自动监测滴答清单 Linux 版本更新，发布 GitHub Release 并同步 AUR 包。

## 工作流

**[`dida365-linux-release.yml`](../.github/workflows/dida365-linux-release.yml)**

| 触发方式 | 说明 |
|----------|------|
| `schedule` | 每 6 小时自动检查一次 |
| `workflow_dispatch` | 在 Actions 页面手动触发 |

执行流程：
1. 检测官网最新版本号（通过 HTTP
 重定向）
2. 如已有对应 Release 则跳过
3. 下载全部 Linux 包（DEB / RPM / AppImage，x64 & ARM64）
4. 生成 SHA256 校验文件
5. 创建 GitHub Release，上传所有包
6. 更新 `dida365/aur/PKGBUILD` 版本和 SHA256，推送到 AUR

## 目录

```
dida365/
  aur/
    PKGBUILD    # AUR 包定义（zerx-lab-dida365-bin），由 CI 自动更新
  README.md     # 本文件
```

## AUR 包

包名：`zerx-lab-dida365-bin`，从官方 `.deb` 重新打包为 Arch 可用格式。

**本地验证打包：**

```bash
cd dida365/aur
makepkg -si
```

## 所需 Secrets

| Secret | 说明 |
|--------|------|
| `AUR_SSH_PRIVATE_KEY` | AUR 账户 SSH 私钥，用于推送 PKGBUILD |