# 2.7 review record

Seven focused passes, not a claim of perfection. Runtime validation is on Mac; Windows is cross-built and existing CI checks run; Debian is a new source/package-checked preview.

1. **Recording lifecycle / data loss:** found Mac could start the next recording while final audio was draining. Blocked that overlap and tagged callbacks by recording ID. Finished note processing uses copied state; existing notes are not renamed or overwritten.
2. **Privacy / integration boundary:** opted for per-tab visible-caption capture, not broad page scraping, tokens or tenant-wide APIs. Browser verifies the actual sender host; native host validates HTTPS, caption lengths, active recording token/service and heartbeat. No open local network port. New option defaults off.
3. **Revisions / imports / fallback:** speaker-labelled VTT/SRT/TXT imports, escaped text and anonymous speakers covered by fixtures. Growing captions update by ID; a second live session is rejected. Disabled collection retains prior captions. Local audio is a labelled backup, not silently discarded. File picker result is rechecked against recording state.
4. **Threading / resource use:** Windows caption list snapshot is locked for audio/UI threads. Mac final drain reads pending caption records before copying the finished note. Unchanged browser captions are not written each second. Caption buffer is bounded; one script send at a time remains enforced by the existing CollectivIQ sender.
5. **Updater trust / idle behaviour:** daily while running, independent installation toggle. Calls, notes, speech processing, result cards and CollectivIQ block install. Mac uses published version tags; Windows/Debian validate repository URL/checksum. Downloads never execute an arbitrary release-provided path. Future update installation itself is not exercised against a nonexistent future release.
6. **Installation safety / UI:** Mac installer requests clean quit, stages/code-signature-verifies app, keeps old app until final move succeeds. Home and settings inspected on Mac. Caption source/waiting/setup/import states visible; privacy footer reflects CollectivIQ. Debian UI is not manually validated.
7. **Release / platform honesty:** shared CollectivIQ scripts regenerated for Debian, source/parser/connector checks run, versions aligned. Debian known gaps are documented rather than described as feature parity. No “all meetings work” or “100% bug-free” assertion.

## Evidence and limits

- 110 Mac rule checks and 90 Windows text-rule checks passed locally at review time.
- Python: 9 native-host boundary tests and 9 Debian core tests passed on Mac.
- JS: synthetic caption extraction fixtures passed; these are not real Teams/Meet DOM snapshots.
- Mac native-messaging harness exercised actual framed messages → Python host → native app timer/read/merge code; revisions, separate session rejection and disabling passed. No real meeting audio/caption recording was created or sent during this check.
- Mac candidate installed, code-signature verified, home/settings/menu inspected; English/Spanish and existing CIQ preferences preserved.
- Not exercised: live Teams/Meet selectors and organiser policies; Teams desktop live capture (not implemented); actual exported files from every tenant; end-to-end future update/restart; Windows UI/audio; Debian GUI/audio/hotkeys/privilege prompt. Existing GitHub checks and package build results are recorded separately in Actions.
