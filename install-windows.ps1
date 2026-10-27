# Just Say It - installer for Windows
# Created by Stefano Roman Gunness - MIT License
#
# Just Say It currently runs on macOS only. It is built on Apple's on-device
# speech recognition and Apple Intelligence, which are not available on Windows.
# A Windows version is planned. This script explains that and lets you
# get notified when it ships.

Write-Host ""
Write-Host "Just Say It - free, private voice typing" -ForegroundColor Magenta
Write-Host "Created by Stefano Roman Gunness"
Write-Host ""
Write-Host "Just Say It is not available for Windows yet." -ForegroundColor Yellow
Write-Host ""
Write-Host "The current version is a native Mac app that uses Apple's built-in,"
Write-Host "on-device speech and AI models. A Windows version is planned."
Write-Host ""
Write-Host "In the meantime, Windows has free built-in voice typing:"
Write-Host "  Press  Windows key + H  in any text box to start dictating."
Write-Host ""

$repo = "https://github.com/stefanoromang/just-say-it"
$answer = Read-Host "Open the Just Say It page to follow progress (Watch > Releases)? [Y/n]"
if ($answer -eq "" -or $answer -match "^[yY]") {
    Start-Process "$repo"
}
