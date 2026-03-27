param(
    [string]$Match
)

$ErrorActionPreference = "Stop"

$windows = Get-Process | Where-Object {
    $_.MainWindowHandle -ne 0 -and -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle)
} | Select-Object `
    Id,
    ProcessName,
    @{Name="Handle";Expression={ $_.MainWindowHandle }},
    @{Name="Title";Expression={ $_.MainWindowTitle }}

if ($Match) {
    $pattern = $Match.ToLowerInvariant()
    $windows = $windows | Where-Object {
        $_.ProcessName.ToLowerInvariant().Contains($pattern) -or $_.Title.ToLowerInvariant().Contains($pattern)
    }
}

$windows | Sort-Object ProcessName, Title
