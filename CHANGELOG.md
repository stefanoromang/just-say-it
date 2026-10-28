# Changelog

All notable changes to **Just Say It** (created by Stefano Roman Gunness).

## 1.5 – 2026-10-28

### New: Meetings – auto-join your calls (Mac and Windows)
- Reads your **Google** and **Microsoft** calendars and finds **Zoom, Google Meet and Microsoft Teams** calls.
  - **Mac:** through the accounts in System Settings › Internet Accounts (choose which calendars to watch).
  - **Windows:** through each calendar's private iCal (ICS) link, including recurring meetings.
- **Joins automatically** at start time or 1/2/5 minutes early. Zoom opens straight in the Zoom app; Meet and Teams open their join screen.
- **Takes notes automatically** for each call with the Note Taker, named after the meeting and including the attendees, and stops when the meeting ends.
- Skips declined (Mac) and cancelled meetings. **Join now** button in the Meetings tab and the menu bar / tray.

### Windows fixes
- Reading the text box no longer fails when Windows is slow on first use.

### Testing
- New tests for meeting-link detection (Mac 30 checks, Windows 33) and calendar reading with recurring meetings; the Windows self-test reads a sample calendar.

## 1.4 – 2026-10-28

### New: Note Taker (Mac and Windows)
- **Press Right Shift three times** to start recording a conversation; three times again to stop.
- **Live transcript** in a floating window with a timer, labelled **Me** (your microphone) and **Others** (computer audio: the other people on a Zoom, Meet or Teams call).
- **Automatic meeting notes** when you stop: Summary, Key points, Decisions and Action items (Apple Intelligence on Mac, local Ollama on Windows).
- **Saved as Markdown** in Documents › Just Say It Notes, updated while you talk so nothing is lost.
- New **Note Taker** tab with saved notes, plus settings to turn off the shortcut or computer-audio capture.
- Everything is transcribed on your computer.

### Testing
- Windows self-test now also checks the Right Shift ×3 shortcut and conversation transcription.

## 1.3 – 2026-10-28

### Windows – important fixes
- **Fixed a crash on startup in 1.2.** Settings were set up in the wrong order. Please update.
- **Clipboard is restored correctly** after inserting text.
- **Text-box context works in more apps:** reads the focused box and selection across apps, with a fallback for classic Windows text boxes.

### Testing
- **End-to-end self-test on real Windows** (`JustSayIt.exe --selftest report.txt`): synthesizes speech and transcribes it with Whisper, reads context from a real text box, runs screen OCR, pastes text, checks clipboard restore, presses the hotkey and renders the overlay and result card. Runs on GitHub's Windows machines after every change: 11/11 checks pass.

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
