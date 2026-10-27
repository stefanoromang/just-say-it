#!/bin/zsh
# Just Say It – uninstaller for macOS
# Created by Stefano Roman Gunness · MIT License
set -e
pkill -x JustSayIt 2>/dev/null || true
rm -rf "$HOME/Applications/Just Say It.app"
echo "Removed ~/Applications/Just Say It.app"

read "reply?Also delete your settings, dictionary, snippets and history? [y/N] "
if [[ "$reply" == [yY]* ]]; then
  rm -rf "$HOME/Library/Application Support/JustSayIt"
  echo "Removed your Just Say It data."
fi

read "reply?Also delete the local code-signing keychain used to build the app? [y/N] "
if [[ "$reply" == [yY]* ]]; then
  security delete-keychain "$HOME/Library/Keychains/justsayit-signing.keychain-db" 2>/dev/null || true
  echo "Removed the signing keychain."
fi

echo "Done. You can also remove Just Say It from System Settings › Privacy & Security (Accessibility, Microphone, Screen Recording)."
