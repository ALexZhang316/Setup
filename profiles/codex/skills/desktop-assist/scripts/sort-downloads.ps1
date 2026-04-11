param(
    [string]$Source = "$env:USERPROFILE\Downloads",
    [string]$DestinationRoot = "$env:USERPROFILE\Downloads\sorted",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source folder not found: $Source"
}

$map = @{
    ".doc" = "documents"
    ".docx" = "documents"
    ".pdf" = "documents"
    ".txt" = "documents"
    ".ppt" = "presentations"
    ".pptx" = "presentations"
    ".xls" = "spreadsheets"
    ".xlsx" = "spreadsheets"
    ".csv" = "spreadsheets"
    ".tsv" = "spreadsheets"
    ".zip" = "archives"
    ".rar" = "archives"
    ".7z" = "archives"
    ".msi" = "installers"
    ".exe" = "installers"
    ".png" = "images"
    ".jpg" = "images"
    ".jpeg" = "images"
    ".gif" = "images"
    ".webp" = "images"
    ".mp4" = "video"
    ".mov" = "video"
    ".mp3" = "audio"
    ".wav" = "audio"
}

function Get-Category {
    param([System.IO.FileInfo]$File)
    $ext = $File.Extension.ToLowerInvariant()
    if ($map.ContainsKey($ext)) {
        return $map[$ext]
    }
    return "other"
}

function Get-UniquePath {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $directory = Split-Path -Parent $Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $i = 1
    do {
        $candidate = Join-Path $directory ($name + "-" + $i + $ext)
        $i++
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}

$files = Get-ChildItem -LiteralPath $Source -File | Where-Object {
    $_.DirectoryName -ne $DestinationRoot
}

$actions = foreach ($file in $files) {
    $category = Get-Category -File $file
    $destinationDir = Join-Path $DestinationRoot $category
    $destinationPath = Join-Path $destinationDir $file.Name
    [pscustomobject]@{
        name = $file.Name
        category = $category
        source = $file.FullName
        destination = $destinationPath
    }
}

if (-not $Apply) {
    $actions | Format-Table -AutoSize
    Write-Output ""
    Write-Output "Preview only. Re-run with -Apply to move files."
    exit 0
}

foreach ($action in $actions) {
    $targetDir = Split-Path -Parent $action.destination
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    $finalPath = Get-UniquePath -Path $action.destination
    Move-Item -LiteralPath $action.source -Destination $finalPath
    [pscustomobject]@{
        name = $action.name
        moved_to = $finalPath
    }
}
