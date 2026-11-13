"""Just Say It — Stefano Roman Gunness · MIT. Platform-independent note rules."""
import html
import re
from pathlib import Path

VERSION = '2.7.0'
REPO = 'stefanoromang/just-say-it'


def version_parts(value):
    if not re.fullmatch(r'v?\d+\.\d+(?:\.\d+)?', value):
        raise ValueError('Invalid release version')
    return tuple(int(p) for p in value.lstrip('v').split('.')) + (0,) * (3 - len(value.lstrip('v').split('.')))


def release_asset(release):
    version_parts(release['tag_name'])
    for asset in release.get('assets', []):
        if re.fullmatch(r'just-say-it_[0-9.]+_all\.deb', asset.get('name', '')):
            if not asset.get('browser_download_url', '').startswith('https://github.com/' + REPO + '/releases/download/'):
                raise ValueError('Unexpected update location')
            if not re.fullmatch(r'sha256:[a-fA-F0-9]{64}', asset.get('digest', '')):
                raise ValueError('Release checksum unavailable')
            return asset
    return None


def unique_note(directory, stem):
    path = Path(directory) / (stem + '.txt')
    i = 2
    while path.exists():
        path = Path(directory) / (stem + ' (' + str(i) + ').txt')
        i += 1
    return path


def parse_transcript(text):
    result = []
    for block in text.replace('\r\n', '\n').replace('\r', '\n').split('\n\n'):
        lines = block.strip().splitlines()
        if not lines or lines[0].startswith(('WEBVTT', 'NOTE')):
            continue
        timing = next((i for i, line in enumerate(lines) if '-->' in line), None)
        if timing is not None:
            lines = lines[timing + 1:]
        cue_speaker = 'Speaker'
        for line in lines:
            line = line.strip()
            if not line or re.fullmatch(r'\d+', line):
                continue
            speaker = 'Speaker'
            tag = re.match(r'^<v(?:\.[^ >]+)?\s+([^>]+)>', line)
            if tag:
                speaker, line = tag[1], line[tag.end():]
            else:
                label = re.match(r'^([^:\d]{1,100}):\s*(.*)$', line)
                if label:
                    speaker, line = label[1], label[2]
                elif timing is not None:
                    speaker = cue_speaker
            cue_speaker = speaker
            line = html.unescape(re.sub(r'<[^>]+>', '', line)).strip()
            if line and len(line) <= 12000 and len(speaker) <= 200:
                result.append({'speaker': speaker, 'text': line})
    return result


def merge_caption(lines, row, session):
    if not isinstance(row, dict) or row.get('service') not in ('teams', 'meet'):
        return session
    for key, size in [('session', 64), ('segment', 100), ('speaker', 200), ('text', 12000)]:
        if not isinstance(row.get(key), str) or not 0 < len(row[key].strip()) <= size:
            return session
    session = session or row['session']
    if session != row['session']:
        return session
    for i, old in enumerate(lines):
        if old.get('segment') == row['segment'] and old.get('session') == row['session']:
            lines[i] = row
            break
    else:
        lines.append(row)
    return session


def combined(local, captions):
    if not captions:
        return local
    return 'MEETING PLATFORM TRANSCRIPT (speaker names supplied by the platform)\n' + '\n'.join(r['speaker'] + ': ' + r['text'] for r in captions) + '\n\nLOCAL AUDIO BACKUP (may overlap the platform transcript; do not count repeated statements twice)\n' + local


def route(result, raw, ai):
    if result.startswith('route:notetaker:'):
        return result[len('route:notetaker:'):], raw
    if result.startswith('route:assistant:'):
        return result[len('route:assistant:'):], ai
    if result == 'route:none':
        return None, ai
    raise ValueError('Route not ready')
