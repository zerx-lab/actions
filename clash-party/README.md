# Clash Party AUR 自动更新

本目录包含 [Clash Party](https://github.com/mihomo-party-org/clash-party) 的 AUR 打包文件及自动更新工作流。

## 目录结构

```
clash-party/
├── aur/
│   ├── PKGBUILD          # AUR 打包构建脚本
│   ├── .SRCINFO          # AUR 包元数据
│   └── .gitignore        # 忽略构建产物
└── README.md             # 本文件
```

## 关于 Clash Party

Clash Party 是基于 [Mihomo](https://github.com/MetaCubeX/mihomo) 内核的代理工具 GUI 客户端，提供：

- **代理管理**：支持多种代理协议（Shadowsocks、VMess、Trojan、VLESS 等）
- **规则分流**：灵活的流量分流规则配置
- **订阅管理**：支持导入和自动更新代理订阅
- **可视化面板**：直观的连接状态和流量统计

## 版本检测原理

通过 GitHub Releases API 获取最新版本信息：

```
GET https://api.github.com/repos/mihomo-party-org/clash-party/releases/latest
```

响应中 `tag_name` 字段即为最新版本号（格式 `vX.Y.Z`），对应 Linux deb 包下载地址为：

```
https://github.com/mihomo-party-org/clash-party/releases/download/v{version}/clash-party_{version}_amd64.deb
```

## 自动更新工作流

GitHub Actions 工作流 `.github/workflows/clash-party-aur-update.yml` 每 24 小时自动执行：

1. 调用 GitHub Releases API 获取最新版本号
2. 查询 AUR 当前已发布版本
3. 若版本不一致，下载 deb 包并计算 SHA256
4. 更新 `PKGBUILD` 中的 `pkgver` 和 `sha256sums_x86_64`
5. 推送更新到 AUR 仓库

## AUR 包名

```
clash-party-bin
```

## 手动触发

```bash
gh workflow run clash-party-aur-update.yml
```

## 依赖项

| 依赖 | 说明 |
|------|------|
| `alsa-lib` | 音频支持 |
| `at-spi2-core` | 辅助技术支持 |
| `cairo` | 2D 图形库 |
| `dbus` | 进程间通信 |
| `libcups` | 打印支持 |
| `libdrm` | Direct Rendering Manager |
| `libsecret` | 密钥存储 |
| `libxcomposite` | X11 合成扩展 |
| `libxdamage` | X11 损坏通知扩展 |
| `libxext` | X11 扩展库 |
| `libxfixes` | X11 修复扩展 |
| `libxkbcommon` | XKB 键盘处理 |
| `libxrandr` | X11 屏幕分辨率扩展 |
| `mesa` | OpenGL 实现 |
| `nss` | 网络安全服务 |
| `pango` | 文本渲染 |
| `xdg-utils` | XDG 工具集 |

### 可选依赖

| 依赖 | 说明 |
|------|------|
| `libappindicator-gtk3` | 系统托盘图标支持 |
| `libayatana-appindicator` | 系统托盘图标支持（Ayatana） |

## 相关链接

- [Clash Party 项目主页](https://github.com/mihomo-party-org/clash-party)
- [Clash Party Releases](https://github.com/mihomo-party-org/clash-party/releases)
- [Mihomo 内核](https://github.com/MetaCubeX/mihomo)
- [AUR 包页面](https://aur.archlinux.org/packages/clash-party-bin)