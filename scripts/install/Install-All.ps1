param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

. (Join-Path $PSScriptRoot '..\lib\Setup.Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Setup.Discovery.ps1')

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
            default { Write-SetupWarning '请输入 y 或 n。' }
        }
    }
}

try {
    $coreScripts = @(
        @{ Path = Join-Path $PSScriptRoot 'Install-Codex-Profile.ps1'; Title = '恢复 Codex 配置' },
        @{ Path = Join-Path $PSScriptRoot 'Install-Claude-Code-Profile.ps1'; Title = '恢复 Claude Code 配置' }
    )
    $optionalScripts = @(
        @{ Path = Join-Path $PSScriptRoot 'Install-Admin-Launchers.ps1'; Title = '安装管理员启动器' },
        @{ Path = Join-Path $PSScriptRoot 'Install-Chat-Enter-Newline.ps1'; Title = '安装聊天热键' }
    )

    foreach ($scriptInfo in @($coreScripts + $optionalScripts)) {
        if (-not (Test-Path -LiteralPath $scriptInfo.Path)) {
            throw ("未找到脚本文件：{0}" -f $scriptInfo.Path)
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
    }
    else {
        Write-Host ("  Codex -> {0}" -f $codexExe)
        if (@(Get-RunningProcessRecords -ProcessNames @('Codex.exe', 'codex.exe')).Count -gt 0) {
            $issues.Add('检测到 Codex 仍在运行。请先完全退出 Codex，再执行统一安装。') | Out-Null
        }
    }

    $claudeCli = Get-ClaudeCliPath
    if (-not $claudeCli) {
        $issues.Add('未检测到 Claude Code CLI。请先安装 Claude Code，并至少启动一次后完全退出。') | Out-Null
    }
    else {
        Write-Host ("  Claude Code CLI -> {0}" -f $claudeCli)
        if (@(Get-RunningProcessRecords -ProcessNames @('Claude.exe', 'claude.exe')).Count -gt 0) {
            $issues.Add('检测到 Claude / Claude Desktop 仍在运行。请先完全退出相关应用，再执行统一安装。') | Out-Null
        }
    }

    $gitCmd = Get-GitCommand
    if (-not $gitCmd) {
        $issues.Add('未检测到 Git。Claude Code 插件安装依赖 Git，请先安装 Git，并重新打开终端。') | Out-Null
    }
    else {
        Write-Host ("  Git -> {0}" -f $gitCmd)
    }

    $claudeDesktopSnapshotPath = Join-Path $RepoRoot 'claude-code-profile\claude-desktop'
    if (Test-Path -LiteralPath $claudeDesktopSnapshotPath) {
        $claudeDesktopRoots = @(Get-ClaudeDesktopRoots)
        if ($claudeDesktopRoots.Count -eq 0) {
            $issues.Add('未检测到 Claude Desktop 数据目录。请先安装并启动一次 Claude Desktop，然后完全退出。') | Out-Null
        }
        else {
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
        $supportedApps = @(Resolve-SupportedApps)
        if ($supportedApps.Count -eq 0) {
            $issues.Add('聊天热键至少需要先安装并初始化一个目标应用：Codex 或 Claude。') | Out-Null
        }

        $autoHotkeyExe = Get-AutoHotkeyExe
        if ($autoHotkeyExe) {
            Write-Host ("  AutoHotkey -> {0}" -f $autoHotkeyExe)
        }
        else {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not $winget) {
                $issues.Add('聊天热键需要 AutoHotkey v2；若本机未安装 AutoHotkey，则至少需要可用的 winget。') | Out-Null
            }
            else {
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

    foreach ($scriptInfo in $coreScripts) {
        Invoke-PowerShellScriptStep -Title $scriptInfo.Title -ScriptPath $scriptInfo.Path -Parameters @{ RepoRoot = $RepoRoot }
    }

    if ($installAdminLaunchers) {
        Invoke-PowerShellScriptStep -Title $optionalScripts[0].Title -ScriptPath $optionalScripts[0].Path -Parameters @{ RepoRoot = $RepoRoot }
    }

    if ($installHotkeys) {
        Invoke-PowerShellScriptStep -Title $optionalScripts[1].Title -ScriptPath $optionalScripts[1].Path -Parameters @{ RepoRoot = $RepoRoot }
    }

    Write-Host ''
    Write-Host '==============================================='
    Write-Host ' 所有选定步骤已执行完成'
    Write-Host '==============================================='
    Write-Host '如果 Codex / Claude / Claude Desktop 当前仍在运行，请完全退出后重新打开。'
}
catch {
    Write-SetupFailure -Title '统一安装失败。' -Message $_.Exception.Message
    exit 1
}
