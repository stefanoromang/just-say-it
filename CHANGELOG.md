# Changelog

All notable changes to **Just Say It** (created by Stefano Roman Gunness).

## Unreleased

### Windows
- **End-to-end self-test on real Windows** (`JustSayIt.exe --selftest report.txt`): synthesizes speech and transcribes it with Whisper, reads context from a real text box, runs screen OCR, pastes text, checks clipboard restore, presses the hotkey and renders the overlay and result card. Runs on GitHub's Windows machines after every change.

## 1.2 – 2026-10-27

### Windows
- **Screen context:** reads the visible email or chat with Windows' built-in offline OCR, so names are spelled right and Scribe replies to the right message (Settings › "Use what's on screen as context").
- **More reliable hotkeys:** the keyboard hook now returns instantly and hands work to the app, so Windows can't silently disable the hotkey under load.
- **No more stalls:** reading the text box and browser address now runs safely in the background with a time limit, so slow apps can't freeze dictation.

### Both platforms
- Automatic tests for the text cleanup (fillers, "scratch that", spoken punctuation, dictionary, snippets, cursor fitting): 25 for each app, run on every change via GitHub Actions.

## 1.1 – 2026-10-27
- **New: Just Say It for Windows.** On-device Whisper speech recognition, optional local AI (Ollama), context detection, result card, hotkeys, dictionary, snippets, history. Installer, portable zip and one-line PowerShell install.

## 1.0 – 2026-10-27
- First release for Mac: on-device dictation, AI cleanup, Scribe, Rewrite, tone per app, context awareness, result card, dictionary, snippets, history.
