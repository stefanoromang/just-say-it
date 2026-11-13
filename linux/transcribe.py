"""Runs inside the user's speech venv, not the GTK interpreter."""
import sys
from faster_whisper import WhisperModel

model = WhisperModel(sys.argv[2], device='cpu', compute_type='int8')
languages = sys.argv[3].split(',')
# shortcut: Whisper chooses a language per VAD segment, ultra-short within-word switches need a stronger multilingual model.
segments, _ = model.transcribe(sys.argv[1], language=languages[0] if len(languages) == 1 else None,
                               multilingual=len(languages) > 1, vad_filter=True, beam_size=5,
                               initial_prompt='Languages spoken: ' + ', '.join(languages) + '. Preserve each spoken language; do not translate.')
print(' '.join(s.text.strip() for s in segments if s.no_speech_prob < 0.8))
