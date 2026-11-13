#!/usr/bin/env python3
"""Just Say It Debian preview — Stefano Roman Gunness · MIT License.

GTK/WebKit for desktop and CollectivIQ; PulseAudio/PipeWire compatibility for audio;
faster-whisper and optional Ollama for local speech and writing. Nothing uses a cloud ASR.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import uuid

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('WebKit2', '4.1')
from gi.repository import Gtk, GLib, WebKit2, Gdk
from core import VERSION, REPO, combined, merge_caption, parse_transcript, unique_note, version_parts, release_asset, route

ROOT = Path(__file__).resolve().parent
DATA = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'JustSayIt'
DATA.mkdir(parents=True, exist_ok=True)
NOTES = Path.home() / 'Documents/Just Say It Notes'
NOTES.mkdir(parents=True, exist_ok=True)


def atomic(path, text):
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(text); tmp.chmod(0o600); tmp.replace(path)


def request(url, data=None):
    req = urllib.request.Request(url, data=data, headers={'User-Agent': 'JustSayIt/' + VERSION, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='com.stefano.justsayit')
        self.prefs = {'captions': False, 'auto_update': True, 'ciq': False, 'languages': ['en', 'es'], 'model': 'small', 'ollama_model': 'qwen2.5:1.5b', 'system_audio': True, 'autostart': True}
        try:
            self.prefs.update(json.loads((DATA / 'prefs.json').read_text()))
        except (OSError, ValueError):
            pass
        self.recording = False; self.busy = False; self.installing = False
        self.finishing = False
        self.note_lock = threading.RLock()
        self.processes = []; self.captions = []; self.session = None; self.caption_offset = 0
        self.queue = []; self.route_ready = False; self.js_busy = False; self.loading = False
        self.last_check = 0; self.last_install = 0; self.idle_since = time.time(); self.pending_update = None
        self.hotkey_at = 0
        self.connect('activate', self.activate_app)

    def save(self):
        atomic(DATA / 'prefs.json', json.dumps(self.prefs, indent=2))

    def status(self, text):
        GLib.idle_add(lambda: self.status_label.set_text(text))

    def worker(self, fn):
        def work():
            try:
                fn()
            except Exception as error:
                self.status(str(error))
            finally:
                if not self.finishing: self.busy = False
        threading.Thread(target=work, daemon=True).start()

    def activate_app(self, *_):
        if hasattr(self, 'window'):
            self.window.present(); return
        self.window = Gtk.ApplicationWindow(application=self, title='Just Say It')
        self.window.set_default_size(960, 680)
        self.window.connect('delete-event', self.close_requested)
        self.window.connect('key-press-event', self.key)
        css = Gtk.CssProvider()
        css.load_from_data(b'window {background:#f6f7fb;color:#242735} .title {font-size:30px;font-weight:700} .subtitle {color:#5e6475} .card {background:white;border-radius:12px;padding:20px} button {padding:8px 14px} .primary {background:#5642b9;color:white} textview {font-family:monospace;font-size:14px} notebook tab {padding:12px}')
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=24)
        self.window.add(outer)
        title = Gtk.Label(label='Just Say It', xalign=0); title.get_style_context().add_class('title'); outer.pack_start(title, False, False, 0)
        subtitle = Gtk.Label(label='Voice typing and meeting notes · Debian preview', xalign=0); subtitle.get_style_context().add_class('subtitle'); outer.pack_start(subtitle, False, False, 0)
        self.status_label = Gtk.Label(label='Ready · captions need the optional browser connector', xalign=0, wrap=True); outer.pack_start(self.status_label, False, False, 0)
        tabs = Gtk.Notebook(); outer.pack_start(tabs, True, True, 0)
        notes = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=16)
        row = Gtk.Box(spacing=8); notes.pack_start(row, False, False, 0)
        self.record_button = self.button(row, 'Start Note Taker', lambda *_: self.toggle_recording())
        self.button(row, 'Dictate', lambda *_: self.toggle_recording('dictation'))
        self.button(row, 'Scribe', lambda *_: self.toggle_recording('scribe'))
        self.button(row, 'Import transcript', lambda *_: self.import_transcript())
        self.buffer = Gtk.TextBuffer(); view = Gtk.TextView(buffer=self.buffer, editable=True, wrap_mode=Gtk.WrapMode.WORD_CHAR)
        scroll = Gtk.ScrolledWindow(); scroll.add(view); notes.pack_start(scroll, True, True, 0)
        actions = Gtk.Box(spacing=8); notes.pack_start(actions, False, False, 0)
        self.button(actions, 'Copy', lambda *_: self.copy())
        self.button(actions, 'Notes folder', lambda *_: subprocess.Popen(['xdg-open', str(NOTES)]))
        tabs.append_page(notes, Gtk.Label(label='Note Taker'))
        settings = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=20)
        self.check(settings, 'Add Teams / Meet captions with speaker names', 'captions')
        self.label(settings, 'Turn on visible captions in Teams web or Meet, then start capture from the browser extension. Local audio stays as a separate backup.')
        self.button(settings, 'Set up caption connector', lambda *_: subprocess.Popen(['xdg-open', str(ROOT / 'captions')]))
        self.check(settings, 'Record computer audio (PulseAudio / PipeWire monitor)', 'system_audio')
        self.check(settings, 'Send finished meeting notes to CollectivIQ', 'ciq')
        self.label(settings, 'Notetaker DDR → raw. Other DDR → AI version. No DDR → CIQ Chat with Gemini + Nemotron.')
        self.check(settings, 'Check daily and install verified releases when idle', 'auto_update')
        self.label(settings, 'Updates never interrupt a recording. Debian package installation may require your system password. A checksum is verified before opening the installer.')
        self.check(settings, 'Start with my desktop session', 'autostart', self.autostart)
        for name, key, choices in [('Speech model', 'model', ['base', 'small', 'large-v3-turbo'])]:
            box = Gtk.Box(spacing=16); self.label(box, name)
            combo = Gtk.ComboBoxText()
            for value in choices: combo.append_text(value)
            combo.set_active(choices.index(self.prefs[key]) if self.prefs[key] in choices else 0)
            combo.connect('changed', lambda c, k=key: self.set_pref(k, c.get_active_text()))
            box.pack_start(combo, False, False, 0); settings.pack_start(box, False, False, 0)
        language = Gtk.Entry(text=','.join(self.prefs.get('languages', ['en', 'es'])))
        language.set_placeholder_text('en,es,pt,it (up to four)')
        language.connect('activate', lambda e: self.set_pref('languages', list(dict.fromkeys(x.strip() for x in e.get_text().split(',') if x.strip().isalpha()))[:4] or ['en']))
        self.label(settings, 'Languages you speak (codes, comma-separated; press Enter to save)'); settings.pack_start(language, False, False, 0)
        self.label(settings, 'Local speech setup: run /usr/share/just-say-it/setup-speech.sh once (downloads faster-whisper into your user folder). Optional AI: install Ollama and the qwen2.5:1.5b model. No cloud speech service is used.')
        self.label(settings, 'Ctrl+Alt+Space toggles notes while this window is focused. For a global desktop shortcut, assign “just-say-it --toggle” in your desktop settings. X11 supports paste via xdotool; Wayland uses Copy.')
        sc = Gtk.ScrolledWindow(); sc.add(settings); tabs.append_page(sc, Gtk.Label(label='Settings'))
        manager = WebKit2.WebsiteDataManager(base_data_directory=str(DATA / 'webkit'), base_cache_directory=str(DATA / 'webkit-cache'))
        context = WebKit2.WebContext.new_with_website_data_manager(manager)
        self.web = WebKit2.WebView.new_with_context(context)
        self.web.connect('load-changed', self.loaded)
        self.web.load_uri('https://collectiviq.ai/chat')
        tabs.append_page(self.web, Gtk.Label(label='CollectivIQ'))
        self.tabs = tabs
        self.window.show_all(); self.autostart(); self.hold()
        self.tray = Gtk.StatusIcon.new_from_icon_name('audio-input-microphone')
        self.tray.set_tooltip_text('Just Say It · Ready'); self.tray.connect('activate', lambda *_: self.window.present())
        self.tray.connect('popup-menu', self.menu)
        GLib.timeout_add_seconds(1, self.tick)
        GLib.timeout_add_seconds(60, self.updates)
        self.updates()

    def set_pref(self, key, value):
        self.prefs[key] = value; self.save()

    def check(self, box, text, key, changed=None):
        widget = Gtk.CheckButton(label=text); widget.set_active(bool(self.prefs.get(key)))
        widget.connect('toggled', lambda w: (self.set_pref(key, w.get_active()), changed() if changed else None))
        box.pack_start(widget, False, False, 0)

    def label(self, box, text):
        widget = Gtk.Label(label=text, xalign=0, wrap=True); widget.set_max_width_chars(90); box.pack_start(widget, False, False, 0)

    def button(self, box, text, callback):
        widget = Gtk.Button(label=text); widget.connect('clicked', callback); box.pack_start(widget, False, False, 0); return widget

    def key(self, _, event):
        if event.keyval == Gdk.KEY_space and event.state & Gdk.ModifierType.CONTROL_MASK and event.state & Gdk.ModifierType.MOD1_MASK:
            self.toggle_recording(); return True
        return False

    def menu(self, _, button, timestamp):
        menu = Gtk.Menu()
        for label, action in [('Open Just Say It', self.window.present), ('End Note Taker' if self.recording else 'Start Note Taker', self.toggle_recording), ('Quit', self.quit_safely)]:
            item = Gtk.MenuItem(label=label); item.connect('activate', lambda _, a=action: a()); menu.append(item)
        captions = Gtk.CheckMenuItem(label='Add Teams / Meet captions'); captions.set_active(self.prefs['captions'])
        captions.connect('toggled', lambda w: self.set_pref('captions', w.get_active())); menu.append(captions)
        menu.show_all(); menu.popup(None, None, None, None, button, timestamp)

    def autostart(self):
        path = Path.home() / '.config/autostart/just-say-it.desktop'
        if self.prefs['autostart']:
            path.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(ROOT / 'just-say-it.desktop', path)
        else:
            path.unlink(missing_ok=True)

    def toggle_recording(self, mode='notes'):
        if self.recording:
            self.end_recording(); return
        if self.busy or self.installing or self.finishing:
            self.status('Finishing the previous task. Please wait.'); return
        self.mode = mode; self.work = Path(tempfile.mkdtemp(prefix='recording-', dir=DATA)); self.local = []; self.captions = []; self.session = None
        if hasattr(self, 'offsets'): del self.offsets
        self.started = time.time(); self.caption_offset = 0; self.caption_pending = ''; self.token = uuid.uuid4().hex
        self.target_window = None
        if os.environ.get('XDG_SESSION_TYPE') == 'x11':
            try: self.target_window = subprocess.check_output(['xdotool', 'getactivewindow'], text=True).strip()
            except (OSError, subprocess.SubprocessError): pass
        self.path = unique_note(NOTES, datetime.datetime.now().strftime('%Y-%m-%d %H.%M.%S') + ' Note')
        self.processes = []
        try:
            for speaker, device in [('Me', None), ('Others', '@DEFAULT_MONITOR@')]:
                if speaker == 'Others' and not self.prefs['system_audio']: continue
                file = self.work / (speaker + '.wav')
                command = ['parec', '--file-format=wav', '--rate=16000', '--channels=1']
                if device: command += ['--device=' + device]
                command += [str(file)]
                proc = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.processes.append((speaker, file, proc))
        except OSError as error:
            for _, _, proc in self.processes: proc.terminate()
            shutil.rmtree(self.work); self.status('Audio could not start: ' + str(error)); return
        self.recording = True; self.stop_worker = threading.Event(); self.record_button.set_label('End Note Taker & send')
        self.status('Recording · local speech backup active'); self.buffer.set_text('')
        self.worker(self.audio_loop)

    def transcribe(self, file):
        venv = DATA / 'speech/bin/python'
        if not venv.exists(): raise RuntimeError('Run setup-speech.sh first to enable local speech recognition. Audio is retained if transcription fails.')
        result = subprocess.run([str(venv), str(ROOT / 'transcribe.py'), str(file), self.prefs['model'], ','.join(self.prefs['languages'])], capture_output=True, text=True, timeout=900)
        if result.returncode: raise RuntimeError(result.stderr[-1000:])
        return result.stdout.strip()

    def audio_loop(self):
        offsets = {speaker: 0 for speaker, _, _ in self.processes}
        try:
            while not self.stop_worker.wait(12):
                for speaker, file, _ in self.processes:
                    if self.stop_worker.is_set(): break
                    chunk = self.work / (speaker + '-chunk.wav')
                    start = offsets[speaker]
                    result = subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-y', '-ss', str(start), '-i', str(file), '-t', '12', str(chunk)], capture_output=True, timeout=30)
                    if result.returncode == 0 and chunk.exists() and chunk.stat().st_size > 1000:
                        text = self.transcribe(chunk)
                        offsets[speaker] += 12
                        if text: self.local.append(f'[{int(start)//60:02}:{int(start)%60:02}] {speaker}: {text}'); self.write_note()
                        GLib.idle_add(self.render)
        except Exception as error:
            self.status(str(error))
        self.offsets = offsets

    def end_recording(self):
        if not self.recording: return
        self.finishing = True
        self.recording = False; self.busy = True; self.stop_worker.set(); self.status('Saving transcript…')
        for _, _, proc in self.processes:
            if proc.poll() is None: proc.send_signal(signal.SIGINT)
        self.record_button.set_label('Finishing…')
        def finish():
            try:
                # Let the existing chunk worker finish; it owns offsets and its current recogniser.
                while not hasattr(self, 'offsets'): time.sleep(0.1)
                for speaker, file, proc in self.processes:
                    try: proc.wait(timeout=10)
                    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
                    chunk = self.work / (speaker + '-last.wav')
                    start = self.offsets.get(speaker, 0)
                    subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-y', '-ss', str(start), '-i', str(file), str(chunk)], capture_output=True, timeout=60)
                    if chunk.exists() and chunk.stat().st_size > 1000:
                        text = self.transcribe(chunk)
                        if text: self.local.append(f'[{int(start)//60:02}:{int(start)%60:02}] {speaker}: {text}')
                self.write_note()
                text = combined('\n'.join(self.local), self.captions)
                if not text.strip():
                    self.status('No speech was transcribed. Audio retained at ' + str(self.work)); return
                smart = self.polish(text, self.mode)
                atomic(self.path.with_name(self.path.stem + ' - Smart.txt'), smart)
                GLib.idle_add(lambda: self.buffer.set_text(smart if self.mode != 'notes' else text))
                if self.mode == 'notes' and self.prefs['ciq'] and text.strip():
                    prompt = (ROOT / 'ciq/prompt.txt').read_text()
                    GLib.idle_add(self.enqueue, 'RAW TRANSCRIPT (exactly as heard)\n\n' + text, prompt + '\n\n' + smart)
                self.status('Saved to ' + str(self.path))
                shutil.rmtree(self.work)
            except Exception as error:
                self.write_note(); self.status('Notes saved; audio retained at ' + str(self.work) + ' · ' + str(error))
            finally:
                self.busy = False; GLib.idle_add(lambda: self.record_button.set_label('Start Note Taker'))
                (DATA / 'caption-state.json').unlink(missing_ok=True)
                (DATA / ('captions-' + self.token + '.jsonl')).unlink(missing_ok=True)
        # audio_loop clears busy when exiting; finishing still blocks new recordings via finish flag.
        self.finishing = True
        def run():
            try: finish()
            finally: self.finishing = False
        threading.Thread(target=run, daemon=True).start()

    def polish(self, text, mode):
        instruction = 'Clean this transcript without dropping details or changing speaker names. Preserve the spoken languages. Do not invent facts.'
        if mode == 'scribe': instruction = 'Write the complete formal message the user asked for. Include every spoken point, name and number. Output only the message.'
        if mode == 'dictation': instruction = 'Fix grammar, punctuation and recognition errors. Preserve the spoken languages. Output only the dictated text, never answer it.'
        try:
            return request('http://127.0.0.1:11434/api/generate', json.dumps({'model': self.prefs['ollama_model'], 'system': instruction, 'prompt': text, 'stream': False}).encode()).get('response', '').strip() or text
        except (OSError, ValueError): return text

    def write_note(self):
        with self.note_lock:
            text = combined('\n'.join(self.local), list(self.captions))
            atomic(self.path, 'Just Say It · ' + datetime.datetime.fromtimestamp(self.started).isoformat() + '\n\n' + text)
            atomic(self.path.with_name(self.path.stem + ' - Raw.txt'), text)

    def render(self):
        if self.recording: self.buffer.set_text(combined('\n'.join(self.local), self.captions))
        return False

    def import_transcript(self):
        if not self.recording: self.status('Start a note before importing a meeting transcript.'); return
        dialog = Gtk.FileChooserDialog(title='Import VTT, SRT or TXT transcript', parent=self.window, action=Gtk.FileChooserAction.OPEN)
        dialog.add_buttons('Cancel', Gtk.ResponseType.CANCEL, 'Import', Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            try:
                file = Path(dialog.get_filename())
                if file.stat().st_size > 10_000_000: raise ValueError('Transcript is larger than 10 MB')
                self.captions.extend(parse_transcript(file.read_text())); self.write_note(); self.render()
            except (OSError, ValueError) as error: self.status(str(error))
        dialog.destroy()

    def copy(self):
        text = self.buffer.get_text(self.buffer.get_start_iter(), self.buffer.get_end_iter(), False)
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
        self.status('Copied · paste into your target app')

    def tick(self):
        # Surface callback failures instead of silently losing the recurring timer.
        try:
            return self.tick_inner()
        except (OSError, ValueError, KeyError) as error:
            self.status('Background task: ' + str(error)); return True

    def tick_inner(self):
        command = DATA / 'toggle'
        if command.exists(): command.unlink(); self.toggle_recording()
        if self.recording:
            atomic(DATA / 'caption-state.json', json.dumps({'token': self.token, 'enabled': self.prefs['captions'], 'service': '', 'updated': time.time()}))
            file = DATA / ('captions-' + self.token + '.jsonl')
            if file.exists() and self.prefs['captions']:
                with file.open(encoding='utf-8') as f:
                    f.seek(self.caption_offset); self.caption_pending += f.read(); self.caption_offset = f.tell()
                while '\n' in self.caption_pending:
                    line, self.caption_pending = self.caption_pending.split('\n', 1)
                    try: self.session = merge_caption(self.captions, json.loads(line), self.session)
                    except ValueError: pass
                self.write_note(); self.render()
            if any(proc.poll() is not None for _, _, proc in self.processes): self.status('Audio capture stopped unexpectedly; finishing the note.'); self.end_recording()
        if self.queue and not self.js_busy and not self.loading: self.send_step()
        return True

    def loaded(self, _, event):
        self.loading = event != WebKit2.LoadEvent.FINISHED
        if not self.loading:
            self.web.run_javascript("window.__jsi=undefined;window.__jsiddr=undefined;window.__jsiroute=undefined", None, None, None)

    def enqueue(self, raw, ai):
        self.queue.append({'raw': raw, 'ai': ai, 'destination': 'auto', 'text': ai, 'started': time.time()})
        if len(self.queue) == 1: self.loading = True; self.web.load_uri('https://collectiviq.ai/chat')
        return False

    def send_step(self):
        item = self.queue[0]
        if time.time() - item['started'] > 900:
            self.status('CollectivIQ timed out; notes remain saved locally.'); self.queue.pop(0); return
        if item['destination'] == 'auto': js = '(' + (ROOT / 'ciq/route.js').read_text() + ')("Notetaker")'
        elif item['destination'] is None: js = '(' + (ROOT / 'ciq/chat.js').read_text() + ')(' + json.dumps(item['text']) + ',["Gemini","Nemotron"])'
        else: js = '(' + (ROOT / 'ciq/ddr.js').read_text() + ')(' + json.dumps(item['text']) + ',' + json.dumps(item['destination']) + ')'
        self.js_busy = True
        def result(web, async_result, _):
            self.js_busy = False
            try:
                value = web.run_javascript_finish(async_result).get_js_value().to_string()
                if not self.queue or self.queue[0] is not item: return
                if value.startswith('route:'):
                    item['destination'], item['text'] = route(value, item['raw'], item['ai']); self.loading = True; web.load_uri('https://collectiviq.ai/chat')
                elif value == 'sent':
                    self.queue.pop(0); self.status('Sent to CollectivIQ')
                    if self.queue: self.loading = True; web.load_uri('https://collectiviq.ai/chat')
                elif value == 'ddr:missing': item['destination'] = None; item['text'] = item['ai']; self.loading = True; web.load_uri('https://collectiviq.ai/chat')
                elif value == 'login': self.tabs.set_current_page(2); self.window.present(); self.status('Sign in to CollectivIQ to finish sending.')
            except GLib.Error as error: self.status('CollectivIQ page unavailable: ' + str(error))
        self.web.run_javascript(js, None, result, None)

    def updates(self):
        if not self.prefs['auto_update']: return True
        if time.time() - self.last_check > 86400:
            self.last_check = time.time()
            def check():
                try:
                    release = request('https://api.github.com/repos/' + REPO + '/releases/latest')
                    if version_parts(release['tag_name']) > version_parts(VERSION): self.pending_update = release_asset(release)
                except (OSError, ValueError, KeyError) as error: self.status('Update check failed: ' + str(error))
            threading.Thread(target=check, daemon=True).start()
        if self.recording or self.busy or getattr(self, 'finishing', False) or self.queue or self.window.is_active():
            self.idle_since = time.time(); return True
        if self.pending_update and not self.installing and time.time() - self.idle_since > 60 and time.time() - self.last_install > 3600:
            self.installing = True; self.last_install = time.time(); asset = self.pending_update
            def install():
                try:
                    directory = DATA / 'updates'; directory.mkdir(exist_ok=True)
                    path = directory / asset['name']
                    with urllib.request.urlopen(asset['browser_download_url'], timeout=120) as response, path.open('wb') as output: shutil.copyfileobj(response, output)
                    if 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest() != asset['digest']: path.unlink(); raise ValueError('Update checksum mismatch')
                    # Debian owns /usr/share: use the desktop's privilege prompt, never write a sudo password.
                    if not shutil.which('pkexec'): raise RuntimeError('Install the downloaded .deb with your package manager: ' + str(path))
                    subprocess.run(['pkexec', '/usr/bin/dpkg', '-i', str(path)], check=True)
                    self.status('Update installed. Restarting…'); self.pending_update = None
                    subprocess.Popen(['/bin/sh', '-c', 'sleep 2; exec just-say-it'])
                    GLib.idle_add(self.quit)
                except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error: self.status('Update not installed: ' + str(error))
                finally: self.installing = False
            threading.Thread(target=install, daemon=True).start()
        return True

    def close_requested(self, *_):
        if self.recording or self.busy or getattr(self, 'finishing', False) or self.queue:
            self.window.hide(); self.status('Running in the background; finish the note before quitting.'); return True
        self.quit(); return False

    def quit_safely(self):
        if self.recording: self.end_recording(); self.status('Finishing your notes; quit again after saving.'); return
        if self.busy or getattr(self, 'finishing', False) or self.queue: self.status('Wait for notes and CollectivIQ delivery before quitting.'); return
        self.quit()


if __name__ == '__main__':
    if '--toggle' in sys.argv:
        (DATA / 'toggle').touch()
    else:
        App().run(sys.argv)
