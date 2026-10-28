# Just Say It - installer for Windows
# Created by Stefano Roman Gunness - MIT License
#
# Installs Just Say It for the current user only. No administrator password needed.
#
# One-line install (PowerShell, a normal window, not "Run as administrator"):
#   irm https://raw.githubusercontent.com/stefanoromang/just-say-it/main/install-windows.ps1 | iex
#
# If your PC blocks setup programs, use the no-installer mode:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/stefanoromang/just-say-it/main/install-windows.ps1))) -Portable

param([switch]$Portable)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$repo = "stefanoromang/just-say-it"
$appDir = Join-Path $env:LOCALAPPDATA "Programs\JustSayIt"
$exe = Join-Path $appDir "JustSayIt.exe"

Write-Host ""
Write-Host "Just Say It - free, private voice typing for Windows" -ForegroundColor Magenta
Write-Host "Created by Stefano Roman Gunness"
Write-Host "Installing for $env:USERNAME only (no administrator password needed)."
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
$setup = $release.assets | Where-Object { $_.name -like "JustSayIt-Setup-*.exe" } | Select-Object -First 1
$zip = $release.assets | Where-Object { $_.name -like "JustSayIt-*-portable.zip" } | Select-Object -First 1
if (-not $setup -and -not $zip) {
    Write-Host "The Windows version isn't published yet. Please try again in a few minutes:" -ForegroundColor Yellow
    Write-Host "https://github.com/$repo/releases"
    exit 1
}

function Install-Portable {
    Write-Host "Downloading $($zip.name) ($([math]::Round($zip.size / 1MB)) MB)..."
    $tmp = Join-Path $env:TEMP $zip.name
    Invoke-WebRequest $zip.browser_download_url -OutFile $tmp -UseBasicParsing
    Get-Process JustSayIt -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    Expand-Archive $tmp -DestinationPath $appDir -Force
    Remove-Item $tmp -ErrorAction SilentlyContinue
    # Files downloaded from the internet are marked; clear the mark so Windows doesn't warn on every start.
    Get-ChildItem $appDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    # Start menu + desktop shortcuts and start with Windows (all per-user).
    $shell = New-Object -ComObject WScript.Shell
    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Just Say It.lnk"
    foreach ($lnkPath in @($startMenu, (Join-Path ([Environment]::GetFolderPath("Desktop")) "Just Say It.lnk"))) {
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath = $exe
        $lnk.WorkingDirectory = $appDir
        $lnk.Description = "Free, private voice typing - by Stefano Roman Gunness"
        $lnk.Save()
    }
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "JustSayIt" -Value "`"$exe`" --background" -PropertyType String -Force | Out-Null
}

if ($Portable -or -not $setup) {
    Install-Portable
} else {
    Write-Host "Downloading $($setup.name) ($([math]::Round($setup.size / 1MB)) MB)..."
    $out = Join-Path $env:TEMP $setup.name
    Invoke-WebRequest $setup.browser_download_url -OutFile $out -UseBasicParsing
    Unblock-File $out -ErrorAction SilentlyContinue
    Write-Host "Installing..."
    try {
        # /CURRENTUSER forces a per-user install; it never shows an administrator prompt.
        $p = Start-Process -FilePath $out -ArgumentList "/SILENT", "/CURRENTUSER", "/TASKS=desktopicon,startup" -Wait -PassThru
        $ok = ($p.ExitCode -eq 0) -and (Test-Path $exe)
    } catch { $ok = $false }
    Remove-Item $out -ErrorAction SilentlyContinue
    if (-not $ok -and $zip) {
        Write-Host "The setup program was blocked on this PC. Installing without it instead..." -ForegroundColor Yellow
        Install-Portable
    }
}

if (Test-Path $exe) {
    Start-Process $exe
    Write-Host ""
    Write-Host "Done! Just Say It is installed in $appDir and running (look for its icon in the system tray)." -ForegroundColor Green
    Write-Host "The first launch downloads the speech model (~470 MB) once."
    Write-Host "Click into any text box, hold Right Alt, talk, and let go."
    Write-Host ""
    Write-Host "Optional - smarter cleanup, Scribe and Rewrite with a free local AI:"
    Write-Host "  1. Install Ollama: https://ollama.com/download/windows (also installs per-user, no admin)"
    Write-Host "  2. Run:  ollama pull llama3.2:3b"
} else {
    Write-Host "Installation did not complete. Download it manually: https://github.com/$repo/releases" -ForegroundColor Yellow
}
