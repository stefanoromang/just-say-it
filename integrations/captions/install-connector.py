#!/usr/bin/env python3
"""Register the unpacked extension's native host for the current user, without admin rights."""
import json
import os
from pathlib import Path
import re
import shutil
import sys


def install(extension_id):
    if not re.fullmatch('[a-p]{32}', extension_id):
        raise ValueError('Paste the 32-letter extension ID from your browser extensions page.')
    source = Path(__file__).resolve().parent
    if sys.platform == 'win32':
        import winreg
        exe = Path(os.environ['LOCALAPPDATA']) / 'Programs/JustSayIt/JustSayIt.exe'
        if not exe.exists():
            raise ValueError('Install Just Say It for Windows first (portable installs require the installed app for this connector).')
        folders = [Path(os.environ['LOCALAPPDATA']) / 'JustSayIt/captions']
        host = str(exe)
    else:
        base = Path.home() / ('Library/Application Support/JustSayIt/captions-host' if sys.platform == 'darwin' else '.local/share/JustSayIt/captions-host')
        base.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / 'native_host.py', base / 'native_host.py')
        launcher = base / 'host'
        launcher.write_text('#!/bin/sh\nexec ' + __import__('shlex').quote(sys.executable) + ' ' + __import__('shlex').quote(str(base / 'native_host.py')) + '\n')
        launcher.chmod(0o700)
        host = str(launcher)
        roots = ['Library/Application Support/Google/Chrome', 'Library/Application Support/Microsoft Edge', 'Library/Application Support/BraveSoftware/Brave-Browser'] if sys.platform == 'darwin' else ['.config/google-chrome', '.config/chromium', '.config/microsoft-edge', '.config/BraveSoftware/Brave-Browser']
        folders = [Path.home() / r / 'NativeMessagingHosts' for r in roots]
    manifest = dict(name='com.stefano.justsayit.captions', description='Just Say It meeting captions', path=host, type='stdio', allowed_origins=['chrome-extension://' + extension_id + '/'])
    for folder in folders:
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / 'com.stefano.justsayit.captions.json'
        path.write_text(json.dumps(manifest, indent=2))
    if sys.platform == 'win32':
        for browser in ['Google\\Chrome', 'Microsoft\\Edge', 'BraveSoftware\\Brave-Browser']:
            with winreg.CreateKey(winreg.HKEY_CURRENT_USER, 'Software\\' + browser + '\\NativeMessagingHosts\\com.stefano.justsayit.captions') as key:
                winreg.SetValueEx(key, '', 0, winreg.REG_SZ, str(path))
    print('Connector installed for this user. Start a Note Taker recording, enable meeting captions in its menu, and start capture from the browser extension.')


if __name__ == '__main__':
    try:
        install(sys.argv[1] if len(sys.argv) > 1 else input('Extension ID: ').strip())
    except (ValueError, OSError) as error:
        sys.exit(str(error))
