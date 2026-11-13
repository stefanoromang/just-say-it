# Meeting captions connector

Optional, local-only, Chrome / Edge / Brave extension for **Teams web** and **Google Meet**. It copies visible speaker-labelled captions into an active Just Say It recording. It does not start transcription, change meeting permissions, read chat messages or send audio anywhere.

1. In your browser's Extensions page, enable **Developer mode**, choose **Load unpacked**, and select this `captions` folder. Keep the folder in place.
2. Copy the extension's ID from that page. With Python 3 installed, run `python3 install-connector.py EXTENSION_ID` on Mac/Linux, or `py install-connector.py EXTENSION_ID` on Windows. No admin account is needed. Only that extension ID is allowed to connect.
3. In Just Say It, turn on **Meeting captions** in the menu and start the Note Taker. In the meeting, show **Captions** or **Transcript**. Click the browser extension and **Start capture**.
4. Leave the meeting page open. Check that Just Say It shows **Connected**. The local audio transcript is preserved separately as a backup.

**Limits:** this is visible-page capture, not an official Teams/Meet API integration. Selectors can change; if the app cannot read both a speaker and text it captures nothing, rather than guessing. It cannot recover captions that scrolled out before capture started. Names are the platform's labels, not verified identities. Translated captions can contain translated text. Duplicate platform/local statements may appear in separate labelled sections. One live browser tab is accepted per recording. Disable the option to stop collecting new captions; previously collected text remains in the note.

Teams desktop: export a transcript and use **Import meeting transcript** while the note is recording. Supported files: VTT, SRT and UTF-8 TXT. Import only files you are authorised to access. Meeting policies and consent still apply. No Microsoft/Google passwords or OAuth tokens are collected by this connector.

The Windows native host is built into the installed app. Mac and Linux use Python's standard library. Uninstall: remove the browser extension and its `com.stefano.justsayit.captions.json` native-host registration. This does not delete your notes.
