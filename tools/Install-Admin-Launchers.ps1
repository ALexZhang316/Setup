# Install-Admin-Launchers.ps1 — 为 Codex 和 Claude 创建管理员启动器
# 创建计划任务（以最高权限运行）+ 桌面快捷方式
# 需要管理员权限，脚本会自动请求提权

param(
    [string]$RepoRoot,
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

# ---------- 提权 ----------

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $elevateArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -RepoRoot "{1}" -Elevated' -f $PSCommandPath, $RepoRoot
    try {
        $proc = Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $elevateArgs -Wait -PassThru
        exit $proc.ExitCode
    } catch {
        Write-Host 'UAC 提权被拒绝或失败。此脚本需要管理员权限。' -ForegroundColor Red
        exit 1
    }
}

# ---------- 查找应用可执行文件 ----------

function Find-AppExe {
    param([string]$AppName, [string[]]$PackagePatterns, [string[]]$ExeNames)

    # 先查 Windows Store 包
    foreach ($pattern in $PackagePatterns) {
        $pkg = Get-AppxPackage $pattern -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg) {
            foreach ($exe in $ExeNames) {
                $path = Join-Path $pkg.InstallLocation "app\$exe"
                if (Test-Path $path) { return $path }
            }
        }
    }

    # 再查常见安装路径（含 per-user Programs 子目录）
    $searchBases = @()
    if ($env:LOCALAPPDATA) {
        $searchBases += Join-Path $env:LOCALAPPDATA "Programs"
        $searchBases += $env:LOCALAPPDATA
    }
    if ($env:ProgramFiles)        { $searchBases += $env:ProgramFiles }
    if (${env:ProgramFiles(x86)}) { $searchBases += ${env:ProgramFiles(x86)} }

    foreach ($base in $searchBases) {
        foreach ($exe in $ExeNames) {
            $path = Join-Path $base "$AppName\$exe"
            if (Test-Path $path) { return $path }
        }
    }

    return $null
}

# ---------- 生成启动器脚本（计划任务执行的 PS1）----------

function Write-LauncherScript {
    param([string]$Path)

    # 这个脚本由计划任务调用，负责找到并启动目标应用
    $content = @'
param(
    [Parameter(Mandatory)]
    [ValidateSet('codex', 'claude')]
    [string]$AppId
)
$ErrorActionPreference = 'Stop'

$apps = @{
    codex  = @{ Packages = @('OpenAI.Codex');  Exes = @('Codex.exe') }
    claude = @{ Packages = @('Claude');        Exes = @('Claude.exe', 'claude.exe') }
}

$app = $apps[$AppId]

foreach ($pattern in $app.Packages) {
    $pkg = Get-AppxPackage $pattern -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($pkg) {
        foreach ($exe in $app.Exes) {
            $path = Join-Path $pkg.InstallLocation "app\$exe"
            if (Test-Path $path) { Start-Process $path; return }
        }
    }
}

$name = if ($AppId -eq 'codex') { 'Codex' } else { 'Claude' }
$searchBases = @()
if ($env:LOCALAPPDATA) {
    $searchBases += Join-Path $env:LOCALAPPDATA 'Programs'
    $searchBases += $env:LOCALAPPDATA
}
if ($env:ProgramFiles)        { $searchBases += $env:ProgramFiles }
if (${env:ProgramFiles(x86)}) { $searchBases += ${env:ProgramFiles(x86)} }

foreach ($base in $searchBases) {
    foreach ($exe in $app.Exes) {
        $path = Join-Path $base "$name\$exe"
        if (Test-Path $path) { Start-Process $path; return }
    }
}

throw "找不到 $AppId 的可执行文件。"
'@

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

# ---------- 注册单个应用的启动器 ----------

function Register-Launcher {
    param([string]$AppId, [string]$DisplayName, [string]$TaskName, [string]$ShortcutName, [string]$ExePath, [string]$LauncherScript)

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -AppId "{1}"' -f $LauncherScript, $AppId
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    # 计划任务
    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

    # 桌面快捷方式
    $desktopDir = [Environment]::GetFolderPath('DesktopDirectory')
    if (-not $desktopDir) { $desktopDir = Join-Path $env:USERPROFILE 'Desktop' }
    $lnkPath = Join-Path $desktopDir $ShortcutName

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $shortcut.Arguments = '/run /tn "{0}"' -f $TaskName
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.Description = "以管理员权限启动 $DisplayName"
    $shortcut.IconLocation = "$ExePath,0"
    $shortcut.Save()

    Write-Host ("  [完成] {0}: 任务={1}, 快捷方式={2}" -f $DisplayName, $TaskName, $ShortcutName)
}

# ---------- 主流程 ----------

try {
    Write-Host '检查应用...'

    $codexExe = Find-AppExe -AppName 'Codex' -PackagePatterns @('OpenAI.Codex') -ExeNames @('Codex.exe')
    $claudeExe = Find-AppExe -AppName 'Claude' -PackagePatterns @('Claude') -ExeNames @('Claude.exe', 'claude.exe')

    if (-not $codexExe -and -not $claudeExe) {
        throw '未检测到 Codex 或 Claude。请先安装并至少启动一次。'
    }

    $launcherScript = Join-Path $env:LOCALAPPDATA 'AdminAppLaunchers\Launch-PackagedApp.ps1'
    Write-LauncherScript -Path $launcherScript

    if ($codexExe) {
        Write-Host ("  Codex -> {0}" -f $codexExe)
        Register-Launcher -AppId 'codex' -DisplayName 'Codex' -TaskName 'Codex Admin Launcher' -ShortcutName 'Codex.lnk' -ExePath $codexExe -LauncherScript $launcherScript
    }

    if ($claudeExe) {
        Write-Host ("  Claude -> {0}" -f $claudeExe)
        Register-Launcher -AppId 'claude' -DisplayName 'Claude' -TaskName 'Claude Admin Launcher' -ShortcutName 'Claude Desktop.lnk' -ExePath $claudeExe -LauncherScript $launcherScript
    }

    Write-Host ''
    Write-Host '管理员启动器创建完成。'
}
catch {
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
