# GitHub Actions 自动化仓库

本仓库按服务分目录管理各类自动化任务，每个服务目录独立维护工作流、脚本和说明文档。

## 目录结构规范

```
<服务名>/               # 每个自动化服务独立目录
  README.md             # 服务说明：用途、工作流、触发方式、所需 Secrets
  <子模块>/             # 服务相关资源（如 aur/、scripts/、config/ 等）
    ...
.github/
  workflows/
    <服务名>-<动作>.yml # 工作流命名格式：{服务}-{动作}
```

## 服务列表

| 服务目录 | 说明 | 工作流 |
|----------|------|--------|
| [`dida/`](dida/README.md) | 滴答清单 Linux 版本监控，自动发布 Release 并更新 AUR 包 | [dida-linux-release.yml](.github/workflows/dida-linux-release.yml) |

## 规范

### 服务目录

- 每个服务对应一个顶层目录，目录名即服务标识
- 目录内必须包含 `README.md`，说明服务用途、工作流逻辑、所需 Secrets
- 服务相关的脚本、配置、模板文件放在该目录下的子目录中

### 工作流文件

- 统一放在 `.github/workflows/`
- 命名格式：`<服务名>-<动作>.yml`（如 `dida-linux-release.yml`）
- 每个工作流必须包含 `workflow_dispatch` 以支持手动触发

### Secrets

- 在仓库 **Settings → Secrets and variables → Actions** 中配置
- 每个服务的 `README.md` 需列出所需 Secrets 及用途

## 常用命令

```bash
# 手动触发工作流
gh workflow run <workflow-file>

# 查看运行记录
gh run list --workflow=<workflow-file>

# 查看运行日志
gh run view <run-id> --log
```
