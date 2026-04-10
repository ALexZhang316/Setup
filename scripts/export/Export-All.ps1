param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

. (Join-Path $PSScriptRoot '..\lib\Setup.Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Setup.Discovery.ps1')

try {
    $codexScript = Join-Path $PSScriptRoot 'Export-Codex-Profile.ps1'
    $claudeScript = Join-Path $PSScriptRoot 'Export-Claude-Code-Profile.ps1'

    foreach ($scriptPath in @($codexScript, $claudeScript)) {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw ("未找到脚本文件：{0}" -f $scriptPath)
        }
    }

    Write-Host '==============================================='
    Write-Host ' Setup 统一导出入口'
    Write-Host '==============================================='
    Write-Host '这个入口会先做统一预检，全部通过后再开始写入仓库快照。'

    Invoke-PowerShellScriptStep -Title '预检 Codex 快照导出' -ScriptPath $codexScript -Parameters @{ RepoRoot = $RepoRoot; ValidateOnly = $true }
    Invoke-PowerShellScriptStep -Title '预检 Claude 快照导出' -ScriptPath $claudeScript -Parameters @{ RepoRoot = $RepoRoot; ValidateOnly = $true }

    Write-Host ''
    Write-Host '前置条件检查通过，开始执行导出。' -ForegroundColor Green

    Invoke-PowerShellScriptStep -Title '导出 Codex 快照' -ScriptPath $codexScript -Parameters @{ RepoRoot = $RepoRoot }
    Invoke-PowerShellScriptStep -Title '导出 Claude 快照' -ScriptPath $claudeScript -Parameters @{ RepoRoot = $RepoRoot }

    Write-Host ''
    Write-Host '==============================================='
    Write-Host ' 所有导出步骤已执行完成'
    Write-Host '==============================================='
    Write-Host '如需同步到其他机器，请继续 git add / git commit / git push。'
}
catch {
    Write-SetupFailure -Title '统一导出失败。' -Message $_.Exception.Message
    exit 1
}
