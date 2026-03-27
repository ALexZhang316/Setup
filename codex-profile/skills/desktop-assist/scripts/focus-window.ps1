param(
    [string]$Title,
    [string]$ProcessName,
    [int64]$Handle
)

$ErrorActionPreference = "Stop"

if (-not $Title -and -not $ProcessName -and -not $Handle) {
    throw "Specify -Title, -ProcessName, or -Handle."
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FocusWindowNative {
  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

$candidate = $null
if ($Handle) {
    $candidate = Get-Process | Where-Object { $_.MainWindowHandle -eq $Handle } | Select-Object -First 1
} elseif ($Title) {
    $pattern = $Title.ToLowerInvariant()
    $candidate = Get-Process | Where-Object {
        $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -and $_.MainWindowTitle.ToLowerInvariant().Contains($pattern)
    } | Select-Object -First 1
} else {
    $pattern = $ProcessName.ToLowerInvariant()
    $candidate = Get-Process | Where-Object {
        $_.MainWindowHandle -ne 0 -and $_.ProcessName.ToLowerInvariant().Contains($pattern)
    } | Select-Object -First 1
}

if (-not $candidate) {
    throw "No matching window found."
}

[void][FocusWindowNative]::ShowWindowAsync([IntPtr]$candidate.MainWindowHandle, 9)
Start-Sleep -Milliseconds 150
[void][FocusWindowNative]::SetForegroundWindow([IntPtr]$candidate.MainWindowHandle)

$shell = New-Object -ComObject WScript.Shell
[void]$shell.AppActivate($candidate.Id)

[pscustomobject]@{
    id = $candidate.Id
    process = $candidate.ProcessName
    handle = $candidate.MainWindowHandle
    title = $candidate.MainWindowTitle
}
