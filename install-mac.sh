#!/bin/zsh
# Just Say It – installer for macOS
# Created by Stefano Roman Gunness · MIT License
#
# Builds Just Say It from source on this Mac and installs it to ~/Applications.
# No admin password needed.
#
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/stefanoromang/just-say-it/main/install-mac.sh | zsh

set -e
REPO_URL="https://github.com/stefanoromang/just-say-it.git"

bold() { print -P "%B$1%b"; }
fail() { print -P "%F{red}✗ $1%f"; exit 1; }
ok()   { print -P "%F{green}✓%f $1"; }

bold "Just Say It – free, private voice typing for Mac"
echo "Created by Stefano Roman Gunness"
echo

# 1. Requirements
[[ "$(uname)" == "Darwin" ]] || fail "This installer is for macOS. Windows is not supported yet."
[[ "$(uname -m)" == "arm64" ]] || fail "Just Say It needs a Mac with Apple silicon (M1 or newer)."
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
(( MACOS_MAJOR >= 26 )) || fail "Just Say It needs macOS 26 (Tahoe) or newer. You have $(sw_vers -productVersion)."
ok "macOS $(sw_vers -productVersion) on Apple silicon"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Apple's free Command Line Tools are needed to build the app."
  echo "A window will open – click Install, wait for it to finish, then run this installer again."
  xcode-select --install 2>/dev/null || true
  exit 1
fi
ok "Command Line Tools found"

# 2. Get the source (use this folder if we're already inside it)
SCRIPT_DIR="${0:A:h}"
if [[ -f "$SCRIPT_DIR/Package.swift" && -d "$SCRIPT_DIR/Sources/JustSayIt" ]]; then
  SRC="$SCRIPT_DIR"
else
  SRC="${TMPDIR:-/tmp}/just-say-it-src"
  rm -rf "$SRC"
  echo "Downloading the source…"
  git clone --depth 1 "$REPO_URL" "$SRC" >/dev/null 2>&1 || fail "Could not download the source from $REPO_URL"
fi
ok "Source ready"

# 3. Build and install
echo "Building (this takes about a minute the first time)…"
cd "$SRC"
./build-app.sh >/dev/null 2>"${TMPDIR:-/tmp}/just-say-it-build.log" || {
  tail -20 "${TMPDIR:-/tmp}/just-say-it-build.log"
  fail "Build failed. Full log: ${TMPDIR:-/tmp}/just-say-it-build.log"
}
ok "Installed to ~/Applications/Just Say It.app"

# 4. Launch
open "$HOME/Applications/Just Say It.app"
echo
bold "Almost done!"
echo "1. Click the waveform icon in your menu bar → Open Just Say It…"
echo "2. Click 'Fix' next to Microphone, Accessibility and (optional) Screen Recording."
echo "3. Click into any text box, hold Right Option (⌥), talk, and let go."
echo
echo "Turn on Apple Intelligence (System Settings › Apple Intelligence & Siri) for smart cleanup, Scribe and Rewrite."
