#!/usr/bin/env python3
"""Browser native-messaging host. Local files only; no listening port or network access."""
import json
import os
from pathlib import Path
import re
import struct
import sys
import time
from urllib.parse import urlparse


def data_dir():
    if sys.platform == 'darwin':
        return Path.home() / 'Library/Application Support/JustSayIt'
    return Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'JustSayIt'


def accept(message, directory):
    try:
        state = json.loads((directory / 'caption-state.json').read_text())
        if not state.get('enabled') or time.time() - state.get('updated', 0) > 15:
            return {'ok': False, 'status': 'Enable meeting captions and start the Note Taker in Just Say It.'}
        token = state.get('token', '')
        if not re.fullmatch(r'[a-f0-9]{32}', token):
            raise ValueError('Invalid recording')
        url = urlparse(message.get('url', ''))
        host = url.hostname if url.scheme == 'https' else None
        service = 'meet' if host == 'meet.google.com' else 'teams' if host in ('teams.microsoft.com', 'teams.live.com', 'teams.cloud.microsoft') else None
        if not service or service != message.get('service') or state.get('service') not in ('', service):
            raise ValueError('Wrong meeting service')
        for key, maximum in (('session', 64), ('segment', 100), ('speaker', 200), ('text', 12000)):
            if not isinstance(message.get(key), str) or not 0 < len(message[key].strip()) <= maximum:
                raise ValueError('Invalid caption')
        if not re.fullmatch(r'[a-zA-Z0-9-]+', message['session']):
            raise ValueError('Invalid session')
        payload = {k: message[k] for k in ('service', 'session', 'segment', 'speaker', 'text')}
        payload['received'] = time.time()
        path = directory / ('captions-' + token + '.jsonl')
        if path.exists() and path.stat().st_size > 64 * 1024 * 1024:
            raise ValueError('Caption buffer is full')
        with path.open('a', encoding='utf-8') as f:
            f.write(json.dumps(payload, ensure_ascii=False) + '\n')
        os.chmod(path, 0o600)
        return {'ok': True, 'status': 'Capturing speaker-labelled captions into your notes.'}
    except (OSError, ValueError, TypeError, KeyError):
        return {'ok': False, 'status': 'No active compatible recording, or caption rejected.'}


def main():
    header = sys.stdin.buffer.read(4)
    if len(header) != 4:
        return
    size = struct.unpack('<I', header)[0]
    if size > 65536:
        return
    try:
        message = json.loads(sys.stdin.buffer.read(size))
        result = accept(message, data_dir()) if isinstance(message, dict) else {'ok': False}
    except (ValueError, OSError):
        result = {'ok': False}
    output = json.dumps(result).encode()
    sys.stdout.buffer.write(struct.pack('<I', len(output)) + output)
    sys.stdout.buffer.flush()


if __name__ == '__main__':
    main()
