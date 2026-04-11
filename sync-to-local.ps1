# sync-to-local.ps1 — 把仓库快照还原到本机对应位置
# 用法：双击 Sync-To-Local.cmd，或手动执行本脚本

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

if (-not (Test-Path $RepoRoot)) {
    Write-Host ("仓库根目录不存在: {0}" -f $RepoRoot) -ForegroundColor Red
    exit 1
}

# ---------- Claude Desktop 路径发现 ----------

function Get-ClaudeDesktopPath {
    # Windows Store 安装（当前机器的已知包名）
    $store = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude"
    if (Test-Path $store) { return $store }

    # 传统安装
    $roaming = "$env:APPDATA\Claude"
    if (Test-Path $roaming) { return $roaming }

    # 通配符兜底：适配其他包签名后缀
    $wild = Get-Item "$env:LOCALAPPDATA\Packages\Claude_*\LocalCache\Roaming\Claude" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($wild) { return $wild.FullName }

    return $null
}

# ---------- 安全目录同步（先复制到临时位置，成功后再替换）----------

function Sync-Directory {
    param(
        [string]$Source,
        [string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    $name   = Split-Path -Leaf $Destination
    $tempDest = Join-Path $parent (".sync-staging-$name")

    # 1. 复制到临时目录
    if (Test-Path $tempDest) {
        Remove-Item -LiteralPath $tempDest -Recurse -Force
    }
    Copy-Item -LiteralPath $Source -Destination $tempDest -Recurse -Force

    # 2. 验证临时目录存在（复制成功）
    if (-not (Test-Path $tempDest)) {
        throw "复制到临时目录失败: $tempDest"
    }

    # 3. 删除旧目标、把临时目录重命名为正式目标
    if (Test-Path $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Rename-Item -LiteralPath $tempDest -NewName $name
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

    if (-not (Test-Path $src)) {
        Write-Host ("[跳过] 仓库中不存在: {0}" -f $m.Repo) -ForegroundColor Yellow
        $skipped++
        continue
    }

    # 确保目标父目录存在
    $parentDir = Split-Path -Parent $m.Local
    if (-not (Test-Path $parentDir)) {
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

# ---------- 摘要 ----------

Write-Host ''
if ($skipped -gt 0) {
    Write-Host ("同步完成：{0} 项成功，{1} 项跳过。" -f $ok, $skipped) -ForegroundColor Yellow
} else {
    Write-Host ("同步完成：{0} 项成功。" -f $ok)
}
