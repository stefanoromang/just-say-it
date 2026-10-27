# Just Say It - installer for Windows
# Created by Stefano Roman Gunness - MIT License
#
# Downloads the latest Just Say It setup from GitHub and runs it.
# No admin rights needed.
#
# One-line install (PowerShell):
#   irm https://raw.githubusercontent.com/stefanoromang/just-say-it/main/install-windows.ps1 | iex

$ErrorActionPreference = "Stop"
$repo = "stefanoromang/just-say-it"

Write-Host ""
Write-Host "Just Say It - free, private voice typing for Windows" -ForegroundColor Magenta
Write-Host "Created by Stefano Roman Gunness"
Write-Host ""

if ([Environment]::OSVersion.Version.Build -lt 19041) {
    Write-Host "Just Say It needs Windows 10 (version 2004) or Windows 11." -ForegroundColor Red
    exit 1
}
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Host "Just Say It needs 64-bit Windows." -ForegroundColor Red
    exit 1
}

Write-Host "Finding the latest version..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "JustSayIt-Installer" }
$asset = $release.assets | Where-Object { $_.name -like "JustSayIt-Setup-*.exe" } | Select-Object -First 1
if (-not $asset) {
    Write-Host "The Windows installer isn't published yet. Please try again in a few minutes:" -ForegroundColor Yellow
    Write-Host "https://github.com/$repo/releases"
    exit 1
}

$out = Join-Path $env:TEMP $asset.name
Write-Host "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB)) MB)..."
Invoke-WebRequest $asset.browser_download_url -OutFile $out -UseBasicParsing

Write-Host "Installing..."
Start-Process -FilePath $out -ArgumentList "/SILENT", "/TASKS=desktopicon,startup" -Wait
Remove-Item $out -ErrorAction SilentlyContinue

$exe = Join-Path $env:LOCALAPPDATA "Programs\JustSayIt\JustSayIt.exe"
if (Test-Path $exe) {
    Start-Process $exe
    Write-Host ""
    Write-Host "Done! Just Say It is running (look for its icon in the system tray)." -ForegroundColor Green
    Write-Host "The first launch downloads the speech model (~470 MB) once."
    Write-Host "Click into any text box, hold Right Alt, talk, and let go."
    Write-Host ""
    Write-Host "Optional - smarter cleanup, Scribe and Rewrite with a free local AI:"
    Write-Host "  1. Install Ollama: https://ollama.com/download/windows"
    Write-Host "  2. Run:  ollama pull llama3.2:3b"
} else {
    Write-Host "Installation did not complete. Download the installer manually: https://github.com/$repo/releases" -ForegroundColor Yellow
}
