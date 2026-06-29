param(
    [string]$ShimDir = "$env:USERPROFILE\AppData\Local\Microsoft\WinGet\Links"
)

$ErrorActionPreference = "Stop"

function New-CmdShim {
    param(
        [string]$Name,
        [string]$Command
    )

    $path = Join-Path $ShimDir "$Name.cmd"
    Set-Content -LiteralPath $path -Value "@echo off`r`n$Command" -NoNewline
    $path
}

New-Item -ItemType Directory -Force -Path $ShimDir | Out-Null

$targets = @(
    @{ Name = "chrome"; Path = "C:\Program Files\Google\Chrome\Application\chrome.exe"; Start = $true },
    @{ Name = "edge"; Path = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"; Start = $true },
    @{ Name = "ahk"; Path = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"; Start = $false },
    @{ Name = "word"; Path = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE"; Start = $true },
    @{ Name = "excel"; Path = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE"; Start = $true },
    @{ Name = "powerpoint"; Path = "C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE"; Start = $true },
    @{ Name = "onenote"; Path = "C:\Program Files\Microsoft Office\root\Office16\ONENOTE.EXE"; Start = $true }
)

$created = @()
foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target.Path)) {
        Write-Warning ("Missing target for launcher " + $target.Name + ": " + $target.Path)
        continue
    }

    $command = if ($target.Start) {
        'start "" "' + $target.Path + '" %*'
    } else {
        '"' + $target.Path + '" %*'
    }

    $created += New-CmdShim -Name $target.Name -Command $command
}

$created | ForEach-Object { Write-Output $_ }
