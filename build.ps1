# Builds dist\RoadTo60-<version>.zip for a manual CurseForge upload.
# The zip contains the RoadTo60 folder at its root, which is what CurseForge expects.
# Paths inside the zip use forward slashes (Compress-Archive on Windows PowerShell 5.1
# writes backslashes, which some unzip tools turn into odd file names).
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$src = Join-Path $root "RoadTo60"
$toc = Get-Content (Join-Path $src "RoadTo60.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() })
$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zipPath = Join-Path $dist "RoadTo60-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $src -Recurse -File | ForEach-Object {
        $rel = "RoadTo60/" + $_.FullName.Substring($src.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel) | Out-Null
    }
} finally {
    $zip.Dispose()
}
Write-Output "Built $zipPath"
