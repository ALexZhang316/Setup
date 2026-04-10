# Setup

这是一个用于迁移和恢复个人 AI 开发环境的 Windows 仓库。

它不是业务代码仓库，而是一个“配置快照 + 安装脚本”仓库，用来把 Codex、Claude Code、Claude Desktop 相关配置在新电脑上尽量一键恢复。

## 仓库作用

这个仓库存放的是你已经整理好的本地环境快照，包括：

- `Codex` 的全局配置、指令和 skills
- `Claude Code` 的全局配置和插件启用状态
- `Claude Desktop` 的偏好设置和扩展设置
- 若干本地辅助脚本，例如管理员启动器和聊天快捷键映射

你可以把它理解成“我的 AI 开发环境备份仓库”。

## 目录说明

- `codex-profile/`
  用来恢复 `%USERPROFILE%\.codex`

- `claude-code-profile/`
  用来恢复 `%USERPROFILE%\.claude`，以及 Claude Desktop 相关设置

- `Install-Codex-Profile.cmd`
  安装 Codex 配置

- `Install-Claude-Code-Profile.cmd`
  安装 Claude Code 配置，并尝试安装插件、同步 Claude Desktop 偏好

- `Install-All.cmd`
  统一安装入口。先做总预检，再按顺序调用各个安装脚本

- `Install-Admin-Launchers.cmd`
  创建 Codex / Claude 的管理员启动快捷方式

- `Install-Chat-Enter-Newline.cmd`
  安装聊天快捷键映射：`Enter` 换行，`Ctrl+Enter` 发送

## 新电脑首次使用

建议按下面顺序操作。

### 1. 先安装基础软件

至少先安装：

- Git
- Codex
- Claude

如果你计划使用快捷键映射脚本，还需要允许脚本自动安装 AutoHotkey，或者提前自行安装 AutoHotkey v2。

### 2. 先把 Codex 和 Claude 各启动一次

这是必要步骤，不是可选步骤。

原因很简单：很多应用第一次启动时才会创建自己的用户目录、缓存目录、插件目录。如果你还没启动过，安装脚本即使执行成功，也可能没有完整的目标位置可写。

启动一次后，把 `Codex`、`Claude`、`Claude Desktop` 完全退出。

### 3. 克隆仓库

推荐直接使用 `git clone`，不要在压缩包里直接运行脚本。

```powershell
git clone <你的仓库地址> D:\Setup
cd D:\Setup
```

### 4. 优先运行统一安装入口

```powershell
.\Install-All.cmd
```

这个脚本会：

- 先统一检查前置条件
- 询问你是否安装管理员启动器
- 询问你是否安装聊天热键
- 在全部预检通过后，按顺序调用子脚本

如果你只想单独恢复某一部分，也可以继续直接运行单个 `.cmd` 脚本。

### 5. 如果不想用统一入口，也可以手动逐个运行

```powershell
.\Install-Codex-Profile.cmd
.\Install-Claude-Code-Profile.cmd
```

这两个脚本是核心。

它们会把仓库中的快照复制到你当前 Windows 用户目录下。

### 6. 按需运行可选脚本

如果你需要管理员启动器：

```powershell
.\Install-Admin-Launchers.cmd
```

如果你需要聊天输入快捷键映射：

```powershell
.\Install-Chat-Enter-Newline.cmd
```

### 7. 重新启动应用

脚本运行结束后，重新打开：

- Codex
- Claude
- Claude Desktop

如果这些应用在安装过程中已经开着，很多配置不会立即生效，所以一定要完全退出后再打开。

## 脚本的保护行为

当前这套脚本已经改成“先检查前置条件，再执行写入”。

如果前置条件不足，脚本会：

- 直接停止
- 输出明确的中文报错
- 不继续做后续写入

这样做的目的，是避免新电脑还没装好软件时，脚本先写进去一半配置，最后留下一个半初始化状态。

其中 [Install-All.cmd](D:/Setup/Install-All.cmd) 会在真正执行任何子脚本之前，先把所有选中步骤需要的前置条件一次性检查完。

## 每个脚本具体做什么

### Install-Codex-Profile.cmd

会把下面这些内容恢复到 `%USERPROFILE%\.codex`：

- `config.toml`
- `AGENTS.md`
- `skills/`

适合在以下场景重新运行：

- 更新了 Codex 配置
- 更新了 AGENTS 规则
- 新增或修改了 skills

前置条件：

- 已安装 Codex
- 最好至少启动过一次 Codex
- 运行脚本时，Codex 最好已经完全退出

### Install-Claude-Code-Profile.cmd

会做这些事情：

- 恢复 `%USERPROFILE%\.claude\CLAUDE.md`
- 恢复 `%USERPROFILE%\.claude\settings.json`
- 尝试调用本机的 `claude.exe` 安装插件
- 同步 Claude Desktop 偏好设置
- 同步 Claude Desktop 的扩展设置

这个脚本已经做过兼容性增强：

- 不再只依赖 `PATH` 里的 `claude`
- 会自动尝试查找常见的本机 `claude.exe` 位置
- 对新电脑更友好

前置条件：

- 已安装 Claude Code
- 已安装 Git
- 至少启动过一次 Claude Code
- 如果要同步 Claude Desktop 设置，也要先安装并启动过一次 Claude Desktop
- 运行脚本时，Claude Code / Claude Desktop 最好都已完全退出

### Install-Admin-Launchers.cmd

会创建高权限启动方式，包括：

- 计划任务
- 桌面快捷方式

用途是让你更方便地以管理员权限启动 Codex 和 Claude。

前置条件：

- 已安装 Codex
- 已安装 Claude
- 两个应用都至少启动过一次
- 运行时需要同意 UAC 提权

### Install-Chat-Enter-Newline.cmd

会安装一个 AutoHotkey 脚本，让聊天输入框中的按键行为变成：

- `Enter`：换行
- `Ctrl+Enter`：发送

这个映射仅针对 Codex / Claude 窗口。

前置条件：

- 已安装至少一个目标应用：Codex 或 Claude
- 目标应用至少启动过一次
- 需要管理员权限
- 需要 AutoHotkey v2
- 如果本机没有 AutoHotkey v2，脚本会尝试通过 `winget` 自动安装；若超时或失败，会直接中文报错退出

## 日常同步方式

这个仓库的正确使用方式不是“脚本自动同步”，而是：

1. 在旧电脑修改仓库里的快照文件
2. `git add` / `git commit` / `git push`
3. 在新电脑执行 `git pull`
4. 重跑对应安装脚本

例如：

- 如果你只改了 `codex-profile/`，就只需要重跑 `Install-Codex-Profile.cmd`
- 如果你只改了 `claude-code-profile/`，就只需要重跑 `Install-Claude-Code-Profile.cmd`

## 如何更新这份仓库

如果你在旧电脑上直接改的是实际配置目录，而不是仓库目录，那么记得把变化同步回仓库。

例如：

- `%USERPROFILE%\.codex\config.toml` 改了以后，要把对应内容更新回 `codex-profile/config.toml`
- `%USERPROFILE%\.claude\settings.json` 改了以后，要把对应内容更新回 `claude-code-profile/settings.json`

否则你推到 GitHub 的还是旧快照，新电脑重新安装时就会恢复成旧状态。

## 验证是否生效

安装完成后，可以这样检查。

### Codex

确认这些文件已经更新：

- `%USERPROFILE%\.codex\config.toml`
- `%USERPROFILE%\.codex\AGENTS.md`
- `%USERPROFILE%\.codex\skills\`

### Claude Code

确认这些文件已经更新：

- `%USERPROFILE%\.claude\CLAUDE.md`
- `%USERPROFILE%\.claude\settings.json`

### Claude Desktop

确认偏好和扩展设置已经同步。

### 管理员启动器

如果运行过 `Install-Admin-Launchers.cmd`，桌面上应出现新的快捷方式。

### 聊天快捷键映射

如果运行过 `Install-Chat-Enter-Newline.cmd`，在 Codex / Claude 输入框中：

- 按 `Enter` 应该换行
- 按 `Ctrl+Enter` 应该发送

## 常见问题

### 1. 脚本执行了，但界面没有变化

最常见原因是应用没有完全退出。

解决方法：

1. 完全关闭 Codex / Claude / Claude Desktop
2. 重新运行脚本
3. 再重新打开应用

### 2. Claude 插件没有安装成功

先确认：

- Claude 已经至少启动过一次
- 本机确实已经安装 Claude Code

如果仍然失败，脚本会打印需要手动执行的插件安装命令。

### 3. 新电脑上脚本不生效

优先检查下面几点：

- 是否先启动过应用一次
- 是否是在解压后的本地目录运行，而不是压缩包里
- 是否运行后立刻重启了应用
- 是否有安全软件或系统策略拦截脚本执行

现在的脚本在这些前置条件不满足时，应该会直接报中文错误，而不是继续部分写入。

### 4. 管理员启动器没有创建成功

这个脚本需要提权。

如果你拒绝了 UAC 弹窗，快捷方式和计划任务就不会创建成功。

### 5. 聊天热键没有生效

通常有几个原因：

- AutoHotkey 没安装成功
- 计划任务没注册成功
- 旧的热键脚本进程仍在运行
- 目标窗口不是 Codex / Claude
- `winget` 自动安装 AutoHotkey 超时或失败

## 推荐使用顺序

新电脑上建议固定按这个顺序操作：

1. 安装 Git / Codex / Claude
2. 各启动一次后退出
3. `git clone` 仓库
4. 运行 `Install-All.cmd`
5. 按提示选择是否安装两个可选功能
6. 重启应用

## 当前结论

这个仓库现在的定位很明确：

它是你自己的 Windows AI 开发环境迁移仓库，用 GitHub 保存快照，用本地 `.cmd` 脚本把快照恢复到新电脑。

如果以后还要继续优化，最值得做的下一步通常是：

- 给每个脚本增加更明确的成功/失败验证输出
- 增加“从本机配置目录反向导出到仓库”的同步脚本
- 把常见排障步骤做成单独文档
