# Changelog

All notable changes to **Just Say It**, an original app designed and built by **Stefano Roman Gunness**.

## 2.7 – 2026-11-12

### Speaker-labelled meeting transcripts (optional)
- Menu/Settings: **Add Teams / Meet captions**, off by default. The included Chrome/Edge/Brave extension captures visible Teams web / Google Meet captions through local native messaging. Platform speaker names are preserved; local audio remains a separate labelled backup.
- **Import meeting transcript** accepts authorised UTF-8 VTT/SRT/TXT exports during recording, including Teams desktop exports. Unnamed speakers stay anonymous. Revised caption snapshots are updated, not duplicated; a second live browser meeting cannot mix into the recording.
- Requires one-time connector setup and per-tab capture. No meeting policy is bypassed. Selectors are best-effort, not an official unrestricted transcript API. Live Teams/Meet capture still requires validation in real meetings.

### Daily idle-safe automatic updates
- Check daily while running; automatically install published releases when recording, dictation, open result cards, active-call tracking and CollectivIQ sending are idle. Checking/installation can be disabled separately.
- Mac builds the published tag instead of main, verifies a staged app and retains the previous copy until replacement succeeds. Windows validates the official release URL and SHA-256 digest before automatic installation.
- Mac manual installation requests a clean quit instead of killing a recording. Fixed a Mac stop/start overlap and isolated late recognition callbacks by recording ID.

### Clearer desktop workspace
- Refined Mac navigation/home page, speaker-labelled caption cards, source status and explicit setup/import controls.
- Corrected local/cloud privacy wording when CollectivIQ delivery is enabled.

### New Debian preview
- GTK desktop app, local Whisper setup, optional system audio, transcript import/captions, optional Ollama writing, and the existing CollectivIQ rule.
- Daily checksum-verified `.deb` updates wait for idle. Debian's package installer may require your system password; no password is stored.
- **Not feature parity:** no automatic call detection/calendar joining, global hold key, screen context, automatic insertion or learned dictionary yet. Mac is the hands-on test platform; Debian desktop/audio and Windows interaction have not been manually validated. See `linux/README.md`.

## 2.6 – 2026-11-09

### CollectivIQ: the right notes to the right place, automatically
Every recording is now sent right away with no questions, based on the DDRs you have in CollectivIQ:
- **DDR called Notetaker** → the **raw transcript** goes to it.
- **No Notetaker, but another DDR (your assistant)** → the **AI version** goes to the first one.
- **No DDR at all** → the **AI version** goes to **CIQ Chat**, answered by **Gemini** and **Nemotron** together.
- Your DDRs are checked every time, so it adapts when one is added or removed. Settings show where the last recording went.

## 2.5 – 2026-11-09

### Speak English, Spanish, Portuguese and Italian without switching
- New **Settings › Languages you speak**: pick your main language and up to three more.
- Just Say It listens in all of them at once and picks the right language **phrase by phrase**, so you can switch in the middle of a sentence without saying so. Short switches inside a sentence are caught too. Works for dictation, Scribe and the Note Taker, on Mac and Windows.

### Smarter Scribe
- Scribe first lists every point, name, date and number you said, then writes the message from that list. It writes the actual message to the person ("tell Laura…" becomes a message to Laura), uses the screen only to know who and what you're replying to, and writes in the language of the conversation.
- It checks that no number you said is missing and fixes it if so.
- New **Scribe tone** setting (Formal by default) for more formal, logical messages.
- Dictation cleanup now also handles Spanish, Portuguese and Italian fillers and self-corrections, and fixes words misheard in the wrong language.

### Gets smarter as you use it
- Fix a word in the result card and Just Say It learns: after the same fix twice it's corrected automatically, and names you fix are recognised next time.
- It learns which languages you use most (helps with close calls) and how you write in each kind of app.
- See what it learned, remove fixes, or reset it in **Settings › Gets smarter as you use it**. Everything stays on your computer.

### Esc closes the result card
- Press **Esc** to close the result card from anywhere, even when you're typing in another app. No mouse needed.

## 2.4 – 2026-11-09

### Every call, recorded from start to finish
- **16 call apps** now start the Note Taker automatically: Microsoft Teams, Google Meet, Zoom, FaceTime, Cisco Webex, Slack Huddles, Discord, Skype, Whereby, Jitsi Meet, RingCentral (and RingCentral Video), GoTo Meeting, Zoho Meeting, Signal, WhatsApp and Telegram. Desktop apps and web calls.
- **Nothing stops the recording until the call that started it ends**: not muting, not quiet moments, not the calendar end time and not another meeting starting. A call ends when its app has used neither the microphone nor the speakers for 45 seconds.
- New **End Note Taker** button (Note Taker window, menu bar / tray, Meetings settings). After you end a call's notes, that same call isn't recorded again.
- **Automatic sending:** when a call ends or you press End Note Taker, the notes go to CollectivIQ immediately with no questions. Pick what (Both / AI version / Raw) and where (DDR / CIQ Chat) once in settings.
- **More detailed smart transcript:** each part is cleaned with the context of what came before, and checked so no lines, names or numbers are lost. Long calls are summarized part by part, then combined, so nothing in the middle is skipped.
- Calendar auto-join never interrupts a recording in progress.
- Turn each call app on or off in **Meetings › Record every live call automatically**.

## 2.3 – 2026-11-06

### CollectivIQ: choose what to send, and where
When a meeting ends or you stop the Note Taker, Just Say It asks two quick questions:
1. **What to send:** **Raw** (the transcript exactly as heard), **AI version** (your prompt + the transcript with words and logic fixed) or **Both** (raw first, then the AI version, **in the same chat**).
2. **Where:** **CIQ Chat** (a new CollectivIQ chat, answered by Nemotron) or your **DDR** (default name **Notetaker**). Just Say It opens that DDR's chat, pastes and sends.
- Set the DDR name in the CollectivIQ settings; leave it empty to always use CIQ Chat. If the DDR isn't found, the notes go to a new CIQ chat instead.

## 2.2 – 2026-10-30

### Windows: built-in local AI, always available
- The Windows app now has its **own local AI engine built in** (llama.cpp via LLamaSharp). No Ollama or other program needed, no admin rights, works offline.
- The **installer downloads the model during install** (Qwen 2.5 1.5B, 1.1 GB, checksum-verified). If that's skipped or interrupted, the app finishes the download by itself on first launch.
- Powers smart dictation cleanup, Scribe, AI Rewrite, the **smart transcript** and meeting summaries.
- **Settings › Built-in local AI:** *Fast* (Qwen 2.5 1.5B) or *Better quality* (Llama 3.2 3B, 2 GB). Ollama is still used as an optional fallback if installed.
- New self-test check runs the local AI on a real Windows machine.

## 2.1 – 2026-10-30

### CollectivIQ: answers from Nemotron, with a live preview
- Before pasting each transcript, Just Say It opens **All · Auto**, clicks **All Selected**, keeps **only Nemotron** and clicks **Apply Changes**, then pastes your prompt + transcript and presses Send.
- Choose a different model (GPT, Claude, Gemini, Grok, Llama 4, Kimi, DeepSeek, GLM, Qwen) or **Don't change** in **Answer with**.
- **Show a live preview while sending** (on by default): watch the model being chosen and the transcript sent. Turn it off for fully invisible background sending.

## 2.0 – 2026-10-30

### Notes: plain text, raw and smart transcripts
- Notes are now saved as **.txt** files. Each recording creates:
  - `<date> <title>.txt` – summary, **smart transcript** and **raw transcript** in one file
  - `<date> <title> - Raw.txt` – exactly as heard, with timestamps
  - `<date> <title> - Smart.txt` – misheard words, grammar and logic fixed so it reads clearly (same speakers and facts)

### CollectivIQ, fully in the background
- When a recording ends you choose **Smart**, **Raw** or **Both** (Both sends the raw transcript first, then the smart one).
- Sending happens **invisibly in the background**; the CollectivIQ window appears **only if you need to sign in again**.
- Notifications: **"syncing… your notes are being processed inside CollectivIQ"** when it starts, and **"sent to CollectivIQ"** about 10 seconds after the last message is posted.

### Always running, easy to see
- **Mac:** starts automatically when you log in (Settings › Start Just Say It when I log in). **Windows:** already starts with Windows, installed per user with no admin password.
- **Neon menu-bar / tray icon** that changes color with what you're doing: **cyan** ready · **pink** dictating (1 key) · **purple** Scribe (2 keys) · **green** Note Taker (Right Shift ×3) · **orange** working. Active modes pulse. Bright on both light and dark mode.
- **Flashing "JustSayIt - Note taker is active"** pill while the Note Taker records.
- **New app icon:** a glowing neon waveform.

## 1.9 – 2026-10-30

### New: record every live call automatically (Mac and Windows)
- When a **Microsoft Teams**, **Zoom** or **Google Meet** call starts (one you join, answer or start), the **Note Taker starts by itself** and records you and the other people. When the call ends, it **stops and saves the transcript** (and sends it to CollectivIQ if that's on).
- Works in the **Teams and Zoom apps** and in **Chrome, Edge, Safari, Brave, Arc and Firefox** (Google Meet, Teams on the web, Zoom web client).
- Detects calls by watching which app is using your microphone, so it reacts to real calls, not just opening the app. Recording starts after about 3 seconds and stops about 10 seconds after the call ends.
- **On by default.** Turn it off, or choose Teams / Zoom / Meet individually, in **Meetings › Record every live call automatically**.
- Works alongside calendar auto-join: a call that's already being recorded isn't recorded twice.

## 1.8 – 2026-10-29

### Documentation
- README rewritten: a full **Note Taker** guide (start/stop, what it captures, live window, saved notes, CollectivIQ hand-off, privacy and consent), the story behind the app, and a **Built with** section crediting the platforms and open-source libraries used.
- New **NOTICE.md**: authorship, third-party licenses and trademark notes.

### CollectivIQ: standard meeting-analysis prompt (Mac and Windows)
- Every note or transcript sent to CollectivIQ now starts with a detailed **16-section meeting analysis prompt**: metadata, participants, opening, chronological flow, key points, decisions, open questions, risks, blockers, solutions, resolved issues, timelines, action items (Action → Owner → Due Date), key quotes, closing and overall assessment, in plain text with nested bullets.
- The transcript follows right after **"HERE IS THE INFORMATION :"**.
- Anyone still on the old short default is switched automatically; custom prompts are kept. **Reset to the standard meeting prompt** restores it any time.

## 1.7 – 2026-10-29

### New: send recordings to CollectivIQ, inside the app (Mac and Windows)
- When a Note Taker recording finishes, the note is saved on your computer as before, then **CollectivIQ opens in a Just Say It window** (no external browser), starts a **new chat**, pastes **your prompt + the full transcript** and presses **Send**.
- Each person **signs in once** in that window with their own CollectivIQ email and password (tick **Remember me**); the window keeps them signed in. If they aren't signed in yet, the transcript is sent automatically right after they sign in.
- New **CollectivIQ** page (Mac sidebar and menu bar; Windows Note Taker tab): **Sign in to CollectivIQ**, turn it on, set your prompt, **Send my last note now**.

### Fixed
- Update checks no longer fail when GitHub's API rate limit is reached (common on shared office networks); the app falls back to the public release page. Default prompt: a meeting recap with key points, decisions, action items and open questions.

## 1.6 – 2026-10-28

### New: automatic updates (Mac and Windows)
- Just Say It checks GitHub for a new version when it starts and once a day, and offers **Install update / Later / Skip this version**.
- **Check for Updates…** in the menu bar / tray, and an **Updates** section in Settings (can be turned off).
- Mac: rebuilds from the official installer and restarts. Windows: downloads the new setup, installs silently and restarts.

### Windows: no administrator password, ever
- The app is marked to run as the normal user (`asInvoker`), so Windows never asks for an admin password to start it.
- The installer, the in-app updater and the one-line installer install **for the current user only** (`%LOCALAPPDATA%\Programs\JustSayIt`), with per-user shortcuts and startup.
- If a PC blocks setup programs, the one-line installer falls back to a **no-installer (portable) mode** automatically, or use `-Portable`.
- Fixed: the one-line installer could wait forever after installing, because it waited for the app it had just started.
- New automated check: a **standard Windows account with no admin rights** installs, runs, uninstalls and runs the portable version.

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
