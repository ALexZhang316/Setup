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

if (-not (Test-Path $RepoRoot)) {
    Write-Host ("仓库根目录不存在: {0}" -f $RepoRoot) -ForegroundColor Red
    exit 1
}

# ---------- Claude Desktop 路径发现 ----------

function Get-ClaudeDesktopPath {
    $store = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude"
    if (Test-Path $store) { return $store }

    $roaming = "$env:APPDATA\Claude"
    if (Test-Path $roaming) { return $roaming }

    $wild = Get-Item "$env:LOCALAPPDATA\Packages\Claude_*\LocalCache\Roaming\Claude" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($wild) { return $wild.FullName }

    return $null
}

# ---------- 安全目录同步 ----------

function Sync-Directory {
    param(
        [string]$Source,
        [string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    $name   = Split-Path -Leaf $Destination
    $tempDest = Join-Path $parent (".sync-staging-$name")

    if (Test-Path $tempDest) {
        Remove-Item -LiteralPath $tempDest -Recurse -Force
    }
    Copy-Item -LiteralPath $Source -Destination $tempDest -Recurse -Force

    if (-not (Test-Path $tempDest)) {
        throw "复制到临时目录失败: $tempDest"
    }

    if (Test-Path $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Rename-Item -LiteralPath $tempDest -NewName $name
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

# ---------- 执行导出 ----------

$ok = 0
$skipped = 0

foreach ($m in $mappings) {
    $src = $m.Local
    $dst = Join-Path $RepoRoot $m.Repo

    if (-not (Test-Path $src)) {
        Write-Host ("[跳过] 本机不存在: {0}" -f $src) -ForegroundColor Yellow
        $skipped++
        continue
    }

    # 确保仓库中的目标父目录存在
    $parentDir = Split-Path -Parent $dst
    if (-not (Test-Path $parentDir)) {
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
