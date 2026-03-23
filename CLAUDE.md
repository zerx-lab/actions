# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库用途

本仓库专门用于通过 GitHub Actions 实现各种自动化任务。每个工作流必须满足：
- 可运行可验证（能够实际触发并产生预期结果）
- YAML 格式通过校验（无语法错误）

## 目录结构约定

```
.github/
  workflows/    # 所有 GitHub Actions 工作流文件（*.yml）
scripts/        # 工作流调用的辅助脚本（可选）
```

## 常用命令

### YAML 格式校验

```bash
# 使用 actionlint 校验工作流语法（推荐）
actionlint .github/workflows/*.yml

# 使用 yamllint 校验 YAML 格式
yamllint .github/workflows/

# 使用 gh 验证工作流（需已推送到 GitHub）
gh workflow list
```

### 通过 gh CLI 操作工作流

```bash
# 列出所有工作流
gh workflow list

# 手动触发工作流（workflow_dispatch）
gh workflow run <workflow-file-or-name>

# 带参数触发
gh workflow run <workflow-file> --field key=value

# 查看最近的运行记录
gh run list --workflow=<workflow-file>

# 查看某次运行详情和日志
gh run view <run-id>
gh run view <run-id> --log

# 等待运行完成
gh run watch <run-id>

# 查看工作流运行状态（实时）
gh run list --limit 5
```

### 调试工作流

```bash
# 重新运行失败的 job
gh run rerun <run-id> --failed

# 重新运行整个工作流
gh run rerun <run-id>
```

## 工作流编写规范

### 触发条件
- 自动化任务优先使用 `schedule`（cron）或 `workflow_dispatch` 触发
- 需要手动验证的工作流必须包含 `workflow_dispatch` 触发器

### 必要字段
每个工作流文件必须包含：
- `name`：工作流的描述性名称
- `on`：明确的触发条件
- `jobs.<job-id>.runs-on`：运行环境（通常为 `ubuntu-latest`）

### 示例工作流模板

```yaml
name: 示例任务

on:
  workflow_dispatch:
  schedule:
    - cron: '0 0 * * *'  # 每天 UTC 00:00 执行

jobs:
  task:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: 执行任务
        run: echo "任务执行"
```

## 验证工作流是否正常

1. 确保 YAML 语法无误（`actionlint` 或 `yamllint`）
2. 推送到 GitHub 后用 `gh workflow run` 触发
3. 用 `gh run watch` 实时观察运行状态
4. 用 `gh run view --log` 查看详细日志确认输出符合预期

## 注意事项

- Secrets 和环境变量在仓库的 Settings > Secrets and variables > Actions 中配置
- 需要写权限的工作流（如推送提交、创建 PR）须在 `permissions` 字段显式声明
- 使用固定版本的 Actions（如 `@v4`）而非 `@main`，保证稳定性

## AUR 打包规范

### 推荐使用 devtools 干净环境打包

AUR 打包**强烈推荐**使用 `devtools` 提供的干净 chroot 环境进行构建，而非直接在本地环境执行 `makepkg`。

原因：
- 干净的 chroot 环境能确保构建过程不依赖本地已安装但未在 `depends`/`makedepends` 中声明的包
- 可以有效排查依赖缺失问题，避免"在我机器上能构建"但其他用户构建失败的情况
- 与 AUR 用户实际使用的 `yay`/`paru` 等工具的干净构建模式行为一致

### 常用命令

```bash
# 安装 devtools
sudo pacman -S devtools

# 使用 extra 仓库的干净 chroot 环境构建（推荐）
extra-x86_64-build

# 如果需要自定义 chroot 路径
extra-x86_64-build -r /var/lib/archbuild

# 本地快速测试（不推荐用于最终验证）
makepkg -si
```

### 打包流程建议

1. 编写/修改 `PKGBUILD` 后，先用 `namcap PKGBUILD` 检查常见问题
2. 使用 `extra-x86_64-build` 在干净环境中构建，确认依赖声明完整
3. 构建成功后，用 `namcap *.pkg.tar.zst` 检查生成的包
4. 确认无误后再推送到 AUR
