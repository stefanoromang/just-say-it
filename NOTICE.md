# Notice

**Just Say It** is an original application conceived, designed and written by **Stefano Roman Gunness**.
Copyright © 2026 Stefano Roman Gunness. Released under the [MIT License](LICENSE).

The product concept, feature set, user experience, names ("Just Say It", "Note Taker", "Scribe"), icon and all source code in this repository are the author's own work.

## Third-party components

Just Say It runs on the following platforms and libraries. Each remains under its own license and belongs to its respective owner.

| Component | Used for | License / terms |
|---|---|---|
| Apple Speech, Foundation Models, Vision, ScreenCaptureKit, EventKit, WebKit | Mac: speech recognition, on-device AI, screen text, call audio, calendars, CollectivIQ window | Apple SDK terms |
| [Whisper.net](https://github.com/sandrohanea/whisper.net) / [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | Windows: on-device speech recognition | MIT |
| OpenAI Whisper models (`ggml-*.bin`, downloaded on first run) | Windows: speech recognition model weights | MIT |
| [LLamaSharp](https://github.com/SciSharp/LLamaSharp) / [llama.cpp](https://github.com/ggml-org/llama.cpp) | Windows: built-in local AI engine | MIT |
| [Qwen 2.5 1.5B Instruct](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF) (downloaded on install) | Windows: default local AI model | Apache 2.0 |
| [Llama 3.2 3B Instruct](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct) (optional download) | Windows: "Better quality" local AI model | Llama 3.2 Community License |
| [NAudio](https://github.com/naudio/NAudio) | Windows: microphone and computer-audio capture | MIT |
| [Ical.Net](https://github.com/ical-org/ical.net) | Windows: reading calendar (ICS) feeds | MIT |
| [System.Speech](https://www.nuget.org/packages/System.Speech) | Windows self-test only | MIT |
| Microsoft WebView2 | Windows: CollectivIQ window | Microsoft terms |
| [Ollama](https://ollama.com) (optional, only if the user already has it) | Windows: fallback local AI | MIT |
| [Inno Setup](https://jrsoftware.org/isinfo.php) | Windows installer | Inno Setup license |

## Services and trademarks

- **CollectivIQ** is an independent service with its own terms of use. The integration requires each user's own CollectivIQ account.
- Zoom, Google Meet, Google Calendar, Microsoft Teams, Outlook, Microsoft 365, macOS and Windows are trademarks of their respective owners. They are referenced only to describe compatibility. Just Say It is not affiliated with, sponsored by or endorsed by any of them.
