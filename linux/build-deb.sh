#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
VERSION=2.7.0
OUT="${1:-linux/dist}"
mkdir -p "$OUT"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/share/just-say-it" "$STAGE/usr/share/applications" "$STAGE/usr/bin"
cp linux/app.py linux/core.py linux/transcribe.py linux/setup-speech.sh linux/just-say-it.desktop "$STAGE/usr/share/just-say-it/"
cp -R integrations/captions "$STAGE/usr/share/just-say-it/captions"
cp -R integrations/ciq "$STAGE/usr/share/just-say-it/ciq"
cp linux/just-say-it.desktop "$STAGE/usr/share/applications/"
cat > "$STAGE/usr/bin/just-say-it" <<'EOF'
#!/bin/sh
exec /usr/bin/python3 /usr/share/just-say-it/app.py "$@"
EOF
chmod 755 "$STAGE/usr/bin/just-say-it" "$STAGE/usr/share/just-say-it/setup-speech.sh"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: just-say-it
Version: $VERSION
Architecture: all
Maintainer: Stefano Roman Gunness <stefanoromang@users.noreply.github.com>
Depends: python3 (>= 3.9), python3-gi, python3-venv, gir1.2-gtk-3.0, gir1.2-webkit2-4.1, ffmpeg, pulseaudio-utils, xdg-utils
Recommends: xdotool, xclip, policykit-1
Section: sound
Priority: optional
Homepage: https://github.com/stefanoromang/just-say-it
Description: Local voice typing and meeting notes (Debian preview)
 GTK desktop app with local Whisper transcription, Teams/Meet captions,
 optional Ollama writing and CollectivIQ delivery. Speech setup required.
EOF
dpkg-deb --root-owner-group --build "$STAGE" "$OUT/just-say-it_${VERSION}_all.deb"
