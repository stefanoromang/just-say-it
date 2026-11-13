# Debian / Linux preview — 2.7

This is a new Linux app, not the Windows executable repackaged. The first release is **preview**: source and package checks only; desktop/audio behaviour has not been tested on Linux hardware. Mac is the hands-on reference platform.

## Install

Download `just-say-it_2.7.0_all.deb` from the release and install with your package manager, for example `sudo apt install ./just-say-it_2.7.0_all.deb`. Debian 12+ / compatible Ubuntu desktop required, with PulseAudio or PipeWire's PulseAudio compatibility service.

Run `/usr/share/just-say-it/setup-speech.sh` once. It installs the local speech engine in your user data folder; the chosen multilingual speech model downloads on first use. Optional AI cleanup/Scribe requires a separately installed local Ollama with `qwen2.5:1.5b`. When AI is unavailable, the raw transcript is kept rather than invented output.

Launch **Just Say It** from the app menu. Start/stop Note Taker, Dictate or Scribe from the window. Set a global desktop shortcut to `just-say-it --toggle`. The in-window shortcut is Ctrl+Alt+Space. Copy the result and paste into your target app. Tray support depends on desktop shell; the main window works without a tray.

## Meeting transcripts

Enable **Add Teams / Meet captions** in the tray menu or Settings, set up the included browser extension, turn on captions/transcription in the meeting, and start capture in the extension. Only visible Teams web / Meet captions are read. Teams desktop exports can be imported as VTT/SRT/TXT. Platform names are not verified identities. Local audio is preserved separately; overlapping statements can appear in both sources.

## Automatic updates

Checks the public GitHub release daily while running. New `.deb` downloads are limited to this repository and checked against GitHub's SHA-256 digest. Installation waits for audio, transcription and sending to finish. Debian owns system install paths, so installation uses the system privilege dialog (`pkexec`) and **may require your password**. No password is stored. Disabling automatic updates is supported. The app is not a background system updater when it is closed.

## Known differences from Mac / Windows

- No automatic call detection / calendar auto-join yet: start and stop recordings from the app or a desktop shortcut.
- No system-wide hold-to-dictate, automatic insertion, screen context, learned correction dictionary or full speaker diarisation. Use Copy; Wayland intentionally does not bypass desktop security.
- Local AI is optional Ollama, not Apple's on-device model or Windows' bundled engine.
- Linux audio, WebKit session persistence, hotkeys and package installation still need real Debian validation.

Settings and models: `~/.local/share/JustSayIt` (or `$XDG_DATA_HOME/JustSayIt`). Notes: `~/Documents/Just Say It Notes`. Audio is temporary; on a speech failure it is retained with an explicit status message to prevent data loss.
