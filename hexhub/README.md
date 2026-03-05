# HexHub AUR 自动更新

本目录包含 [HexHub](https://www.hexhub.cn) 的 AUR 打包文件及自动更新工作流。

## 目录结构

```
hexhub/
├── aur/
│   ├── PKGBUILD          # AUR 打包构建脚本
│   └── .gitignore        # 忽略构建产物
└── README.md             # 本文件
```

## 关于 HexHub

HexHub 是为程序员和运维人员量身打造的一站式开发运维工具，集成了：

- **Database**：支持 MySQL、PostgreSQL、Redis、SQLite、Oracle 等多种数据库
- **SSH/SFTP**：功能完善的 SSH 终端和 SFTP 文件管理
- **Docker**：容器管理、镜像管理、Docker-Compose 编辑

## 版本检测原理

通过官方 API 接口获取最新版本信息：

```
GET https://api.hexhub.cn/client/plugin/master-latest-version-list
Header: Origin: https://www.hexhub.cn
```

响应中 `data.linux-amd64-deb.versionName` 字段即为最新版本号，对应 Linux deb 包下载地址为：

```
https://oss.hexhub.cn/plugin/HexHub-amd64-deb-{version}.deb
```

## 自动更新工作流

GitHub Actions 工作流 `.github/workflows/hexhub-aur-update.yml` 每 24 小时自动执行：

1. 调用官方 API 获取最新版本号
2. 查询 AUR 当前已发布版本
3. 若版本不一致，下载 deb 包并计算 SHA256
4. 更新 `PKGBUILD` 中的 `pkgver` 和 `sha256sums_x86_64`
5. 推送更新到 AUR 仓库

## AUR 包名

```
zerx-lab-hexhub-bin
```

## 手动触发

```bash
gh workflow run hexhub-aur-update.yml
```

## 依赖项

| 依赖 | 说明 |
|------|------|
| `gtk3` | GTK3 图形库 |
| `libnotify` | 桌面通知支持 |
| `nss` | 网络安全服务 |
| `libxss` | X11 屏幕保护扩展 |
| `libxtst` | X11 输入扩展 |
| `xdg-utils` | XDG 工具集 |
| `at-spi2-core` | 辅助技术支持 |
| `libsecret` | 密钥存储 |
| `libasound2` | 音频支持 |

## 相关链接

- [HexHub 官网](https://www.hexhub.cn)
- [更新日志](https://www.hexhub.cn/history)
- [AUR 包页面](https://aur.archlinux.org/packages/zerx-lab-hexhub-bin)