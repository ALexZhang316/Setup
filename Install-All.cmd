@echo off
setlocal
set "SELF=%~f0"
set "TMPPS=%TEMP%\Install-All-%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -LiteralPath $env:SELF -Raw -Encoding UTF8; $marker = ':__POWERSHELL_PAYLOAD__'; $index = $content.LastIndexOf($marker); if ($index -lt 0) { throw 'Marker not found.' }; $script = $content.Substring($index + $marker.Length).TrimStart([char]13, [char]10); $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($env:TMPPS, $script, $utf8NoBom)"
if errorlevel 1 goto :prepare_fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%"
set "EXIT_CODE=%ERRORLEVEL%"

del /q "%TMPPS%" >nul 2>nul

if not "%EXIT_CODE%"=="0" (
    echo.
    echo 安装失败，退出码 %EXIT_CODE%。
    pause
)

exit /b %EXIT_CODE%

:prepare_fail
echo 安装脚本准备失败。
pause
exit /b 1

:__POWERSHELL_PAYLOAD__
$ErrorActionPreference = 'Stop'

function Add-UniquePath {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Seen,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Paths,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$RequireExists
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if ($RequireExists -and -not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (Test-Path -LiteralPath $Path) {
        $normalizedPath = (Resolve-Path -LiteralPath $Path).Path
    } else {
        $normalizedPath = $Path
    }

    if ($Seen.ContainsKey($normalizedPath)) {
        return
    }

    $Seen[$normalizedPath] = $true
    $Paths.Add($normalizedPath) | Out-Null
}

function Fail-Install {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ''
    Write-Host '统一安装失败。' -ForegroundColor Red
    Write-Host ("  {0}" -f $Message) -ForegroundColor Red
    exit 1
}

function Prompt-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [bool]$DefaultYes = $false
    )

    $hint = if ($DefaultYes) { 'Y/n' } else { 'y/N' }

    while ($true) {
        $inputValue = Read-Host ("{0} ({1})" -f $Message, $hint)
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            return $DefaultYes
        }

        switch -Regex ($inputValue.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
            default {
                Write-Host '请输入 y 或 n。' -ForegroundColor Yellow
            }
        }
    }
}

function Get-CodexExecutablePath {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    $command = Get-Command 'codex.exe', 'codex' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command -and $command.Source) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path $command.Source -RequireExists
    }

    foreach ($pkg in @(Get-AppxPackage 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending)) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $pkg.InstallLocation 'app\Codex.exe') -RequireExists
    }

    Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe') -RequireExists
    if ($env:ProgramFiles) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $env:ProgramFiles 'Codex\Codex.exe') -RequireExists
    }
    if (${env:ProgramFiles(x86)}) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Codex\Codex.exe') -RequireExists
    }

    return $candidates | Select-Object -First 1
}

function Get-ClaudeCliPath {
    $command = Get-Command 'claude', 'claude.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($command -and $command.Source) {
        return $command.Source
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    $appDataCliRoot = Join-Path $env:APPDATA 'Claude\claude-code'
    if (Test-Path -LiteralPath $appDataCliRoot) {
        foreach ($versionDir in Get-ChildItem -LiteralPath $appDataCliRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending) {
            Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $versionDir.FullName 'claude.exe') -RequireExists
        }
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        foreach ($packageDir in Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue) {
            if ($packageDir.Name -notlike 'Claude*') {
                continue
            }

            $cliRoot = Join-Path $packageDir.FullName 'LocalCache\Roaming\Claude\claude-code'
            if (-not (Test-Path -LiteralPath $cliRoot)) {
                continue
            }

            foreach ($versionDir in Get-ChildItem -LiteralPath $cliRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending) {
                Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $versionDir.FullName 'claude.exe') -RequireExists
            }
        }
    }

    return $candidates | Select-Object -First 1
}

function Get-ClaudeDesktopRoots {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    $appDataRoot = Join-Path $env:APPDATA 'Claude'
    Add-UniquePath -Seen $seen -Paths $roots -Path $appDataRoot -RequireExists

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        foreach ($packageDir in Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue) {
            if ($packageDir.Name -notlike 'Claude*') {
                continue
            }

            $candidateRoot = Join-Path $packageDir.FullName 'LocalCache\Roaming\Claude'
            Add-UniquePath -Seen $seen -Paths $roots -Path $candidateRoot -RequireExists
        }
    }

    return $roots.ToArray()
}

function Resolve-AppExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('codex', 'claude')]
        [string]$AppId
    )

    $packageNames = @()
    $exeRelativePaths = @()
    $installPathCandidates = New-Object 'System.Collections.Generic.List[string]'

    switch ($AppId) {
        'codex' {
            $packageNames = @('OpenAI.Codex')
            $exeRelativePaths = @('app\Codex.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe')
            if ($env:ProgramFiles) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Codex\Codex.exe')
            }
            if (${env:ProgramFiles(x86)}) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Codex\Codex.exe')
            }
        }
        'claude' {
            $packageNames = @('Claude')
            $exeRelativePaths = @('app\Claude.exe', 'app\claude.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Claude\claude.exe')
            if ($env:ProgramFiles) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Claude\Claude.exe')
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Claude\claude.exe')
            }
            if (${env:ProgramFiles(x86)}) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Claude\Claude.exe')
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Claude\claude.exe')
            }
        }
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    foreach ($packageName in $packageNames) {
        foreach ($pkg in @(Get-AppxPackage $packageName -ErrorAction SilentlyContinue | Sort-Object Version -Descending)) {
            foreach ($relativePath in $exeRelativePaths) {
                Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $pkg.InstallLocation $relativePath) -RequireExists
            }
        }
    }

    foreach ($candidatePath in $installPathCandidates) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path $candidatePath -RequireExists
    }

    return $candidates | Select-Object -First 1
}

function Get-AutoHotkeyExe {
    $candidates = @(
        'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe',
        'C:\Program Files (x86)\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files (x86)\AutoHotkey\v2\AutoHotkey.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $command = Get-Command AutoHotkey64.exe, AutoHotkey.exe, AutoHotkey -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($command) {
        return $command.Source
    }

    return $null
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    Write-Host ''
    Write-Host ("==> {0}" -f $Title) -ForegroundColor Cyan
    & $ScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw ("步骤失败：{0}（退出码 {1}）" -f $Title, $LASTEXITCODE)
    }
}

try {
    $repoRoot = Split-Path -Parent $env:SELF
    $coreScripts = @(
        'Install-Codex-Profile.cmd',
        'Install-Claude-Code-Profile.cmd'
    )
    $optionalScripts = @(
        'Install-Admin-Launchers.cmd',
        'Install-Chat-Enter-Newline.cmd'
    )

    foreach ($scriptName in @($coreScripts + $optionalScripts)) {
        $scriptPath = Join-Path $repoRoot $scriptName
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw ("未找到脚本文件：{0}" -f $scriptPath)
        }
    }

    Write-Host '==============================================='
    Write-Host ' Setup 统一安装入口'
    Write-Host '==============================================='
    Write-Host '这个入口会先做统一预检，全部通过后再开始写入。'
    Write-Host ''

    $installAdminLaunchers = Prompt-YesNo -Message '是否安装管理员启动器？'
    $installHotkeys = Prompt-YesNo -Message '是否安装聊天热键（Enter 换行，Ctrl+Enter 发送）？'

    Write-Host ''
    Write-Host '开始统一检查前置条件...'

    $issues = New-Object 'System.Collections.Generic.List[string]'

    $codexExe = Get-CodexExecutablePath
    if (-not $codexExe) {
        $issues.Add('未检测到 Codex。请先安装 Codex，并至少启动一次后完全退出。') | Out-Null
    } else {
        Write-Host ("  Codex -> {0}" -f $codexExe)
    }

    $claudeCli = Get-ClaudeCliPath
    if (-not $claudeCli) {
        $issues.Add('未检测到 Claude Code CLI。请先安装 Claude Code，并至少启动一次后完全退出。') | Out-Null
    } else {
        Write-Host ("  Claude Code CLI -> {0}" -f $claudeCli)
    }

    $gitCmd = Get-Command 'git.exe', 'git' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCmd) {
        $issues.Add('未检测到 Git。Claude Code 插件安装依赖 Git，请先安装 Git，并重新打开终端。') | Out-Null
    } else {
        Write-Host ("  Git -> {0}" -f $gitCmd.Source)
    }

    $claudeDesktopSnapshotPath = Join-Path $repoRoot 'claude-code-profile\claude-desktop'
    if (Test-Path -LiteralPath $claudeDesktopSnapshotPath) {
        $claudeDesktopRoots = @(Get-ClaudeDesktopRoots)
        if ($claudeDesktopRoots.Count -eq 0) {
            $issues.Add('未检测到 Claude Desktop 数据目录。请先安装并启动一次 Claude Desktop，然后完全退出。') | Out-Null
        } else {
            foreach ($desktopRoot in $claudeDesktopRoots) {
                Write-Host ("  Claude Desktop -> {0}" -f $desktopRoot)
            }
        }
    }

    if ($installAdminLaunchers) {
        foreach ($appId in @('codex', 'claude')) {
            $exePath = Resolve-AppExecutablePath -AppId $appId
            if (-not $exePath) {
                $displayName = if ($appId -eq 'codex') { 'Codex' } else { 'Claude' }
                $issues.Add(("管理员启动器需要先安装并初始化 {0}。" -f $displayName)) | Out-Null
            }
        }
    }

    if ($installHotkeys) {
        $supportedApps = @()
        foreach ($appId in @('codex', 'claude')) {
            $exePath = Resolve-AppExecutablePath -AppId $appId
            if ($exePath) {
                $supportedApps += $exePath
            }
        }

        if ($supportedApps.Count -eq 0) {
            $issues.Add('聊天热键至少需要先安装并初始化一个目标应用：Codex 或 Claude。') | Out-Null
        }

        $autoHotkeyExe = Get-AutoHotkeyExe
        if ($autoHotkeyExe) {
            Write-Host ("  AutoHotkey -> {0}" -f $autoHotkeyExe)
        } else {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not $winget) {
                $issues.Add('聊天热键需要 AutoHotkey v2；若本机未安装 AutoHotkey，则至少需要可用的 winget。') | Out-Null
            } else {
                Write-Host ("  winget -> {0}" -f $winget.Source)
            }
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host ''
        Write-Host '以下前置条件未满足：' -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host ("  - {0}" -f $issue) -ForegroundColor Red
        }
        exit 1
    }

    Write-Host ''
    Write-Host '前置条件检查通过，开始执行安装。' -ForegroundColor Green

    Push-Location $repoRoot
    try {
        Invoke-Step -Title '恢复 Codex 配置' -ScriptPath (Join-Path $repoRoot 'Install-Codex-Profile.cmd')
        Invoke-Step -Title '恢复 Claude Code 配置' -ScriptPath (Join-Path $repoRoot 'Install-Claude-Code-Profile.cmd')

        if ($installAdminLaunchers) {
            Invoke-Step -Title '安装管理员启动器' -ScriptPath (Join-Path $repoRoot 'Install-Admin-Launchers.cmd')
        }

        if ($installHotkeys) {
            Invoke-Step -Title '安装聊天热键' -ScriptPath (Join-Path $repoRoot 'Install-Chat-Enter-Newline.cmd')
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ''
    Write-Host '==============================================='
    Write-Host ' 所有选定步骤已执行完成'
    Write-Host '==============================================='
    Write-Host '如果 Codex / Claude / Claude Desktop 当前仍在运行，请完全退出后重新打开。'
}
catch {
    Fail-Install -Message $_.Exception.Message
}
