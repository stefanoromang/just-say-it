#!/bin/sh
set -eu
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/JustSayIt"
mkdir -p "$DATA"
python3 -m venv "$DATA/speech"
"$DATA/speech/bin/python" -m pip install 'faster-whisper==1.2.1'
printf '%s\n' 'Speech engine installed. The chosen speech model downloads on first use.'
