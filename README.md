# Setup

Windows AI 开发环境的配置备份与恢复仓库。

用 GitHub 保存配置快照，用脚本在机器之间同步 Codex、Claude Code、Claude Desktop 的设置。

## 目录结构

```
profiles/
  claude-code/        ~/.claude/ 的快照（CLAUDE.md, settings.json）
  claude-desktop/     Claude Desktop 的快照（偏好设置, 扩展清单）
  codex/              ~/.codex/ 的快照（AGENTS.md, config.toml, skills/）
tools/
  Install-Elevated-Runner.ps1    管理员命令执行器安装（可选）
  Elevated-Runner.ps1            管理员命令执行器（计划任务运行）
  New-Elevated-Job.ps1           创建管理员命令 job
  Install-Chat-Enter-Newline.ps1 聊天热键映射（可选）
```

## 脚本

| 脚本 | 作用 |
|------|------|
| `还原配置.cmd` | 把仓库快照还原到本机 |
| `备份配置.cmd` | 把本机当前配置导出回仓库 |
| `安装管理员执行器.cmd` | 创建 Codex Elevated Runner 计划任务 |
| `tools\New-Elevated-Job.ps1` | 从普通 Codex shell 提交管理员命令 |
| `安装聊天热键.cmd` | 安装聊天热键：Enter 换行，Ctrl+Enter 发送 |

## 新电脑首次使用

### 1. 安装基础软件

至少先安装：

- Git
- Codex
- Claude

### 2. 各启动一次后退出

应用首次启动时会创建用户目录。未启动过的话，同步脚本没有目标可写。

### 3. 克隆仓库

```powershell
git clone <你的仓库地址> D:\Setup
cd D:\Setup
```

### 4. 运行同步脚本

```powershell
.\还原配置.cmd
```

脚本会把仓库中的配置文件复制到本机对应位置。未检测到的应用会自动跳过。

### 5. 按需运行可选工具

```powershell
.\安装管理员执行器.cmd      # 需要 UAC
.\安装聊天热键.cmd          # 需要 AutoHotkey v2
```

### 6. 重启应用

配置生效需要重启 Codex / Claude / Claude Desktop。

## 日常同步

1. 在本机修改实际配置
2. 运行 `备份配置.cmd` 导出到仓库
3. `git add` / `git commit` / `git push`
4. 在其他机器 `git pull` 后运行 `还原配置.cmd`

## 路径映射

| 仓库路径 | 本机路径 |
|----------|---------|
| `profiles/claude-code/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `profiles/claude-code/settings.json` | `~/.claude/settings.json` |
| `profiles/claude-desktop/claude_desktop_config.json` | Claude Desktop 配置目录 |
| `profiles/claude-desktop/extensions-installations.json` | Claude Desktop 配置目录 |
| `profiles/codex/AGENTS.md` | `~/.codex/AGENTS.md` |
| `profiles/codex/config.toml` | `~/.codex/config.toml` |
| `profiles/codex/skills/` | `~/.codex/skills/` |

Claude Desktop 配置目录会自动检测：Windows Store 安装 或 传统安装路径。

## 常见问题

### 脚本执行了但没变化

应用没完全退出。关掉后重新运行脚本，再重启应用。

### 聊天热键没生效

检查 AutoHotkey v2 是否安装成功。脚本会尝试通过 winget 自动安装。

### 管理员命令执行器

新版 Windows Codex GUI 不保证 agent shell 继承管理员 token，管理员命令统一走 Codex Elevated Runner。

用于安装软件、修改系统目录、写注册表、管理服务，以及执行需要 High Mandatory Level 的命令。它会安装一个最高权限计划任务 `Codex Elevated Runner`，Codex agent 只需要写入 job 并触发计划任务。

安装：

```powershell
.\安装管理员执行器.cmd
# 或
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Elevated-Runner.ps1
```

在 Codex 中提交管理员命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-Elevated-Job.ps1 -Command "net session; whoami /groups" -Wait
```

也可以提交脚本文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-Elevated-Job.ps1 -ScriptPath .\some-admin-task.ps1 -Wait
```

日志目录：

```powershell
%LOCALAPPDATA%\CodexElevatedRunner\logs
```
