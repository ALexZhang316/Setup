# sync-to-repo.ps1 — 把本机当前配置导出回仓库快照
# 用法：双击 Sync-To-Repo.cmd，或手动执行本脚本

param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = $PSScriptRoot
}

# ---------- 安全检查 ----------

if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    Write-Host 'USERPROFILE 环境变量为空，无法确定源路径。' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $RepoRoot)) {
    Write-Host ("仓库根目录不存在: {0}" -f $RepoRoot) -ForegroundColor Red
    exit 1
}

# ---------- Claude Desktop 路径发现 ----------

function Get-ClaudeDesktopPath {
    $store = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude"
    if (Test-Path -LiteralPath $store) { return $store }

    $roaming = "$env:APPDATA\Claude"
    if (Test-Path -LiteralPath $roaming) { return $roaming }

    $wild = Get-Item "$env:LOCALAPPDATA\Packages\Claude_*\LocalCache\Roaming\Claude" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($wild) { return $wild.FullName }

    return $null
}

# ---------- Git 未提交改动检查 ----------

function Test-GitDirty {
    param([string]$Root, [string[]]$Paths)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return @() }

    $dirty = @()
    foreach ($p in $Paths) {
        $lines = & git -C $Root status --short -- $p 2>$null
        if ($lines) { $dirty += $lines }
    }
    return $dirty
}

# ---------- 安全目录同步 ----------

function Sync-Directory {
    param(
        [string]$Source,
        [string]$Destination
    )

    $parent  = Split-Path -Parent $Destination
    $name    = Split-Path -Leaf $Destination
    $staging = Join-Path $parent (".sync-staging-$name")
    $backup  = Join-Path $parent (".sync-backup-$name")

    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    Copy-Item -LiteralPath $Source -Destination $staging -Recurse -Force

    if (-not (Test-Path -LiteralPath $staging)) {
        throw "复制到临时目录失败: $staging"
    }

    # 尝试原子替换：旧目录改名为备份 → 临时目录改名为正式目标
    $destinationExists = Test-Path -LiteralPath $Destination
    $renamed = $false
    if ($destinationExists) {
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        try {
            Rename-Item -LiteralPath $Destination -NewName ".sync-backup-$name"
            $renamed = $true
        } catch {
            if (Test-Path -LiteralPath $staging) {
                Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
            }
            throw "目标目录无法改名，可能正在被应用占用。请关闭相关应用后重试: $Destination。原始错误: $($_.Exception.Message)"
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
        # 目标目录不存在时，直接把临时目录改名为正式目标
        Rename-Item -LiteralPath $staging -NewName $name
    }

    # 清理残留的临时目录
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------- 路径映射表（方向：本机 -> 仓库）----------

$desktopPath = Get-ClaudeDesktopPath

$mappings = @(
    @{ Local = "$env:USERPROFILE\.claude\CLAUDE.md";    Repo = 'profiles\claude-code\CLAUDE.md';    Type = 'file' }
    @{ Local = "$env:USERPROFILE\.claude\settings.json"; Repo = 'profiles\claude-code\settings.json'; Type = 'file' }
    @{ Local = "$env:USERPROFILE\.codex\AGENTS.md";     Repo = 'profiles\codex\AGENTS.md';           Type = 'file' }
    @{ Local = "$env:USERPROFILE\.codex\config.toml";   Repo = 'profiles\codex\config.toml';          Type = 'file' }
    @{ Local = "$env:USERPROFILE\.codex\skills";        Repo = 'profiles\codex\skills';               Type = 'dir'  }
)

if ($desktopPath) {
    $mappings += @(
        @{ Local = "$desktopPath\claude_desktop_config.json";    Repo = 'profiles\claude-desktop\claude_desktop_config.json';    Type = 'file' }
        @{ Local = "$desktopPath\extensions-installations.json"; Repo = 'profiles\claude-desktop\extensions-installations.json'; Type = 'file' }
    )
} else {
    Write-Host '[跳过] 未检测到 Claude Desktop，跳过桌面端配置。' -ForegroundColor Yellow
}

# ---------- 检查仓库中是否有未提交改动 ----------

$repoPaths = @($mappings | ForEach-Object { $_.Repo })
$dirtyLines = Test-GitDirty -Root $RepoRoot -Paths $repoPaths
if ($dirtyLines.Count -gt 0) {
    Write-Host '仓库目标路径存在未提交改动，请先提交或清理后再导出：' -ForegroundColor Red
    foreach ($line in $dirtyLines) {
        Write-Host ("  {0}" -f $line) -ForegroundColor Red
    }
    exit 1
}

# ---------- 执行导出 ----------

$ok = 0
$skipped = 0

foreach ($m in $mappings) {
    $src = $m.Local
    $dst = Join-Path $RepoRoot $m.Repo

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host ("[跳过] 本机不存在: {0}" -f $src) -ForegroundColor Yellow
        $skipped++
        continue
    }

    # 确保仓库中的目标父目录存在
    $parentDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if ($m.Type -eq 'dir') {
        Sync-Directory -Source $src -Destination $dst
    } else {
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    Write-Host ("[完成] {0} -> {1}" -f $src, $m.Repo)
    $ok++
}

# ---------- 摘要 ----------

Write-Host ''
if ($skipped -gt 0) {
    Write-Host ("导出完成：{0} 项成功，{1} 项跳过。" -f $ok, $skipped) -ForegroundColor Yellow
} else {
    Write-Host ("导出完成：{0} 项成功。" -f $ok)
}

# 提示用户检查 git 变更
$gitExe = Get-Command git -ErrorAction SilentlyContinue
if ($gitExe) {
    Write-Host ''
    Write-Host '当前 git 状态：'
    & git -C $RepoRoot status --short
}
