# sync-to-local.ps1 — 把仓库快照还原到本机对应位置
# 用法：双击 还原配置.cmd，或手动执行本脚本

param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = $PSScriptRoot
}

# ---------- 安全检查 ----------

if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    Write-Host 'USERPROFILE 环境变量为空，无法确定目标路径。' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $RepoRoot)) {
    Write-Host ("仓库根目录不存在: {0}" -f $RepoRoot) -ForegroundColor Red
    exit 1
}

# ---------- Claude Desktop 路径发现 ----------

function Get-ClaudeDesktopPath {
    # Windows Store 安装（当前机器的已知包名）
    $store = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude"
    if (Test-Path -LiteralPath $store) { return $store }

    # 传统安装
    $roaming = "$env:APPDATA\Claude"
    if (Test-Path -LiteralPath $roaming) { return $roaming }

    # 通配符兜底：适配其他包签名后缀
    $wild = Get-Item "$env:LOCALAPPDATA\Packages\Claude_*\LocalCache\Roaming\Claude" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($wild) { return $wild.FullName }

    return $null
}

# ---------- 安全目录同步（先复制到临时位置，旧目录改名为备份，再替换）----------

function Sync-Directory {
    param(
        [string]$Source,
        [string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    $name   = Split-Path -Leaf $Destination
    $staging = Join-Path $parent (".sync-staging-$name")
    $backup  = Join-Path $parent (".sync-backup-$name")

    # 1. 复制到临时目录
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    Copy-Item -LiteralPath $Source -Destination $staging -Recurse -Force

    if (-not (Test-Path -LiteralPath $staging)) {
        throw "复制到临时目录失败: $staging"
    }

    # 2. 尝试原子替换：旧目录改名为备份 → 临时目录改名为正式目标
    $renamed = $false
    if (Test-Path -LiteralPath $Destination) {
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        try {
            Rename-Item -LiteralPath $Destination -NewName ".sync-backup-$name"
            $renamed = $true
        } catch {
            # 目录被占用无法重命名（比如应用正在运行），回退到直接覆写
        }
    }

    if ($renamed) {
        # 原子路径：把临时目录改名为正式目标
        try {
            Rename-Item -LiteralPath $staging -NewName $name
        } catch {
            # 重命名失败 → 回滚
            if (Test-Path -LiteralPath $backup) {
                Rename-Item -LiteralPath $backup -NewName $name -ErrorAction SilentlyContinue
            }
            throw "目录替换失败，已回滚: $_"
        }
        # 替换成功，删除备份
        if (Test-Path -LiteralPath $backup) {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        # 回退路径：直接删除旧内容再复制（目录被占用时的兜底）
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        Rename-Item -LiteralPath $staging -NewName $name
    }

    # 清理残留的临时目录
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------- 路径映射表 ----------

$desktopPath = Get-ClaudeDesktopPath

$mappings = @(
    @{ Repo = 'profiles\claude-code\CLAUDE.md';    Local = "$env:USERPROFILE\.claude\CLAUDE.md";    Type = 'file' }
    @{ Repo = 'profiles\claude-code\settings.json'; Local = "$env:USERPROFILE\.claude\settings.json"; Type = 'file' }
    @{ Repo = 'profiles\codex\AGENTS.md';           Local = "$env:USERPROFILE\.codex\AGENTS.md";     Type = 'file' }
    @{ Repo = 'profiles\codex\config.toml';          Local = "$env:USERPROFILE\.codex\config.toml";   Type = 'file' }
    @{ Repo = 'profiles\codex\skills';               Local = "$env:USERPROFILE\.codex\skills";        Type = 'dir'  }
)

if ($desktopPath) {
    $mappings += @(
        @{ Repo = 'profiles\claude-desktop\claude_desktop_config.json';    Local = "$desktopPath\claude_desktop_config.json";    Type = 'file' }
        @{ Repo = 'profiles\claude-desktop\extensions-installations.json'; Local = "$desktopPath\extensions-installations.json"; Type = 'file' }
    )
} else {
    Write-Host '[跳过] 未检测到 Claude Desktop，跳过桌面端配置。' -ForegroundColor Yellow
}

# ---------- 执行同步 ----------

$ok = 0
$skipped = 0

foreach ($m in $mappings) {
    $src = Join-Path $RepoRoot $m.Repo

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host ("[跳过] 仓库中不存在: {0}" -f $m.Repo) -ForegroundColor Yellow
        $skipped++
        continue
    }

    # 确保目标父目录存在
    $parentDir = Split-Path -Parent $m.Local
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if ($m.Type -eq 'dir') {
        Sync-Directory -Source $src -Destination $m.Local
    } else {
        Copy-Item -LiteralPath $src -Destination $m.Local -Force
    }

    Write-Host ("[完成] {0} -> {1}" -f $m.Repo, $m.Local)
    $ok++
}

# ---------- Claude Code 插件安装 ----------

$settingsPath = Join-Path $RepoRoot 'profiles\claude-code\settings.json'
if (Test-Path -LiteralPath $settingsPath) {
    $claudeExe = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeExe) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
            $pluginIds = @()
            if ($settings.enabledPlugins) {
                # enabledPlugins 是一个对象，键就是插件 ID
                $pluginIds = @($settings.enabledPlugins.PSObject.Properties.Name)
            }

            if ($pluginIds.Count -gt 0) {
                Write-Host ''
                Write-Host ("正在安装 {0} 个 Claude Code 插件..." -f $pluginIds.Count)
                $pluginOk = 0
                $pluginFail = 0

                foreach ($id in $pluginIds) {
                    $output = ''
                    try {
                        $output = & claude plugin install $id --scope user 2>&1 | Out-String
                    } catch {
                        # 极少数情况下 PowerShell 无法启动外部进程时才会走到这里
                        Write-Host ("  [失败] {0}: {1}" -f $id, $_.Exception.Message) -ForegroundColor Yellow
                        $pluginFail++
                        continue
                    }

                    # 外部命令非零退出码不会抛异常，必须显式检查 $LASTEXITCODE
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host ("  [完成] {0}" -f $id)
                        $pluginOk++
                    } else {
                        $msg = ($output -replace '\s+$', '')
                        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "退出码 $LASTEXITCODE" }
                        Write-Host ("  [失败] {0}: {1}" -f $id, $msg) -ForegroundColor Yellow
                        $pluginFail++
                    }
                }

                if ($pluginFail -gt 0) {
                    Write-Host ("[警告] {0} 个插件安装失败，可稍后手动安装。" -f $pluginFail) -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host ("[警告] 插件安装跳过: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    } else {
        Write-Host '[跳过] 未找到 claude CLI，跳过插件安装。' -ForegroundColor Yellow
    }
}

# ---------- 摘要 ----------

Write-Host ''
if ($skipped -gt 0) {
    Write-Host ("同步完成：{0} 项成功，{1} 项跳过。" -f $ok, $skipped) -ForegroundColor Yellow
} else {
    Write-Host ("同步完成：{0} 项成功。" -f $ok)
}
