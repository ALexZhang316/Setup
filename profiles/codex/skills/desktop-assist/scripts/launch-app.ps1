param(
    [string]$App,
    [string[]]$Args,
    [switch]$List,
    [switch]$Resolve,
    [switch]$Wait,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

$catalog = [ordered]@{
    chrome = @{ kind = "exe"; target = "C:\Program Files\Google\Chrome\Application\chrome.exe" }
    edge = @{ kind = "exe"; target = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" }
    word = @{ kind = "exe"; target = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE" }
    excel = @{ kind = "exe"; target = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE" }
    powerpoint = @{ kind = "exe"; target = "C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE" }
    onenote = @{ kind = "exe"; target = "C:\Program Files\Microsoft Office\root\Office16\ONENOTE.EXE" }
    downloads = @{ kind = "path"; target = "$env:USERPROFILE\Downloads" }
    desktop = @{ kind = "path"; target = [Environment]::GetFolderPath("Desktop") }
    documents = @{ kind = "path"; target = [Environment]::GetFolderPath("MyDocuments") }
    pictures = @{ kind = "path"; target = [Environment]::GetFolderPath("MyPictures") }
}

if ($List) {
    foreach ($keyName in $catalog.Keys) {
        $item = $catalog[$keyName]
        Write-Output ([pscustomobject]@{
            app = $keyName
            kind = $item.kind
            target = $item.target
            present = Test-Path -LiteralPath $item.target
        })
    }
    exit 0
}

if (-not $App) {
    throw "Specify -App or use -List."
}

$key = $App.ToLowerInvariant()
if (-not $catalog.Contains($key)) {
    throw "Unsupported app or folder: $App"
}

$entry = $catalog[$key]
if (-not (Test-Path -LiteralPath $entry.target)) {
    throw "Target not found: $($entry.target)"
}

if ($Resolve) {
    Write-Output $entry.target
    exit 0
}

$startArgs = @{
    FilePath = $entry.target
}
if ($Args) {
    $startArgs.ArgumentList = $Args
}
if ($Wait) {
    $startArgs.Wait = $true
}
if ($PassThru) {
    $startArgs.PassThru = $true
}

Start-Process @startArgs
