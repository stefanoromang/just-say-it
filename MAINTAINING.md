# Maintaining Just Say It

Everything needed to change, build and publish **Just Say It** is in this folder.
Created by **Stefano Roman Gunness** · MIT License.

## Folder layout

| Path | What it is |
|---|---|
| `Sources/JustSayIt/` | Mac app source (Swift / SwiftUI) |
| `Tests/` | Mac text-rule tests (`swift run RuleTests`) |
| `windows/JustSayIt/` | Windows app source (C# / WinForms) |
| `windows/JustSayIt.Tests/` | Windows tests (`dotnet test`) |
| `windows/installer/JustSayIt.iss` | Windows installer script (Inno Setup) |
| `scripts/` | Icon generator and signing-identity setup |
| `docs/` | Images used by the README |
| `.github/workflows/` | GitHub Actions: tests, Windows self-test, Windows release build |
| `build-app.sh` | Builds the Mac app and installs it to `~/Applications` |
| `install-mac.sh`, `install-windows.ps1/.cmd`, `uninstall-mac.sh` | Installers for users |
| `assets/signing/` | Backup of the local Mac code-signing keychain (not in git) |
| `final/` | Latest finished installers: Mac app zip, Windows setup, Windows portable zip (not in git) |
| `README.md`, `CHANGELOG.md`, `NOTICE.md`, `LICENSE` | Docs, history, credits, license |
| `.git/` | Full version history (connected to github.com/stefanoromang/just-say-it) |

Build output (`.build/`, `build/`, `bin/`, `obj/`) is not kept; it's recreated by the build.

## Tools you need

**Mac app (on a Mac with Apple silicon, macOS 26+):**
- Apple Command Line Tools: `xcode-select --install`
- Build and install: `./build-app.sh`
- Tests: `swift run -c release RuleTests`

**Windows app (can be built on Mac or Windows):**
- .NET 10 SDK: https://dotnet.microsoft.com/download
- Build: `dotnet build windows/JustSayIt/JustSayIt.csproj -c Release`
- Tests: `dotnet test windows/JustSayIt.Tests/JustSayIt.Tests.csproj`
- The Windows installer is built automatically by GitHub when you publish a release.

**Publishing:** GitHub CLI (`gh`), signed in as `stefanoromang`.

## Make a change and release it

1. Edit the code (Mac in `Sources/JustSayIt/`, Windows in `windows/JustSayIt/`).
2. Bump the version in **four places**:
   - `build-app.sh` → `CFBundleShortVersionString` and `CFBundleVersion`
   - `windows/JustSayIt/JustSayIt.csproj` → `<Version>`
   - `windows/installer/JustSayIt.iss` → `#define AppVersion`
   - `.github/workflows/windows.yml` (portable zip name) and the setup file name in `README.md`
3. Add an entry to `CHANGELOG.md`.
4. Test locally: `swift run -c release RuleTests` and `dotnet test windows/JustSayIt.Tests/JustSayIt.Tests.csproj`, then `./build-app.sh` to try it on your Mac.
5. Upload: `git add -A && git commit -m "…" && git push`. GitHub runs all checks, including the Windows self-test on a real Windows machine and a no-admin install test.
6. When the checks pass, publish: `gh release create vX.Y … --latest`. GitHub builds and attaches the Windows installer and portable zip, and everyone's app offers the update automatically.

## Signing on a new Mac

`build-app.sh` signs the app with a local identity so macOS remembers its permissions (Microphone, Accessibility, Screen Recording) across rebuilds. On a new Mac it restores that identity from `assets/signing/` automatically. Keep that folder private.

## Where users' data lives

- Mac: settings in `~/Library/Application Support/JustSayIt`, notes in `~/Documents/Just Say It Notes`.
- Windows: settings and models in `%LOCALAPPDATA%\JustSayIt`, notes in `Documents\Just Say It Notes`.
