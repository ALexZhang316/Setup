param(
    [string]$RepoRoot,
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

. (Join-Path $PSScriptRoot '..\lib\Setup.Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Setup.Discovery.ps1')

function New-LauncherScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = @'
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('codex', 'claude')]
    [string]$AppId
)

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
    }
    else {
        $normalizedPath = $Path
    }

    if ($Seen.ContainsKey($normalizedPath)) {
        return
    }

    $Seen[$normalizedPath] = $true
    $Paths.Add($normalizedPath) | Out-Null
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

$exePath = Resolve-AppExecutablePath -AppId $AppId
if (-not $exePath) {
    throw "Executable not found for app: $AppId"
}

Start-Process -FilePath $exePath
'@

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Register-AppLauncher {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$App,

        [Parameter(Mandatory = $true)]
        [string]$LauncherScriptPath
    )

    $exePath = Resolve-AppExecutablePath -AppId $App.Id
    if (-not $exePath) {
        throw ("未检测到 {0} 可执行文件。" -f $App.DisplayName)
    }

    $powershellExe = Get-WindowsPowerShellPath
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -AppId "{1}"' -f $LauncherScriptPath, $App.Id
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    $action = New-ScheduledTaskAction -Execute $powershellExe -Argument $taskArgs
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $App.TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

    $shortcutPath = Join-Path (Get-DesktopDirectory) $App.ShortcutName
    $shortcutShell = New-Object -ComObject WScript.Shell
    $shortcut = $shortcutShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $shortcut.Arguments = '/run /tn "{0}"' -f $App.TaskName
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.Description = $App.Description
    $shortcut.IconLocation = '{0},0' -f $exePath
    $shortcut.Save()

    $task = Get-ScheduledTask -TaskName $App.TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        throw ("计划任务创建失败：{0}" -f $App.TaskName)
    }

    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        throw ("桌面快捷方式创建失败：{0}" -f $shortcutPath)
    }

    Write-Host ("  Ready: {0} -> {1}" -f $App.ShortcutName, $App.TaskName)
}

try {
    Ensure-ProcessElevated -ScriptPath $PSCommandPath -RepoRoot $RepoRoot -Elevated:$Elevated

    $launcherRoot = Join-Path $env:LOCALAPPDATA 'AdminAppLaunchers'
    $launcherScriptPath = Join-Path $launcherRoot 'Launch-PackagedApp.ps1'
    $apps = @(
        [pscustomobject]@{
            Id = 'codex'
            DisplayName = 'Codex'
            TaskName = 'Codex Admin Launcher'
            ShortcutName = 'Codex.lnk'
            Description = 'Start Codex with highest privileges'
        },
        [pscustomobject]@{
            Id = 'claude'
            DisplayName = 'Claude'
            TaskName = 'Claude Admin Launcher'
            ShortcutName = 'Claude Desktop.lnk'
            Description = 'Start Claude with highest privileges'
        }
    )

    Write-Host '开始检查前置条件...'
    foreach ($app in $apps) {
        $exePath = Resolve-AppExecutablePath -AppId $app.Id
        if (-not $exePath) {
            throw ("未检测到以下应用的可执行文件：{0}。请先安装并至少启动一次后完全退出，再运行本脚本。" -f $app.DisplayName)
        }

        Write-Host ("  {0} -> {1}" -f $app.DisplayName, $exePath)
    }

    Ensure-Directory -Path $launcherRoot
    New-LauncherScript -Path $launcherScriptPath
    Assert-FileExists -Path $launcherScriptPath -Label 'launcher script'

    foreach ($app in $apps) {
        Register-AppLauncher -App $app -LauncherScriptPath $launcherScriptPath
    }

    Write-Host ("管理员启动器创建完成：{0}/{1}" -f $apps.Count, $apps.Count)
    Write-Host ("  Launcher -> {0}" -f $launcherScriptPath)
    Write-Host '  验证 -> 计划任务、launcher script、桌面快捷方式均已存在'
}
catch {
    Write-SetupFailure -Title '管理员启动器安装失败。' -Message $_.Exception.Message
    exit 1
}
