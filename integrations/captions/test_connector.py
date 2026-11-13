import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location('native_host', Path(__file__).with_name('native_host.py'))
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)


class ConnectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.state = {'enabled': True, 'updated': time.time(), 'token': 'a' * 32, 'service': 'meet'}
        self.message = dict(url='https://meet.google.com/abc-defg-hij', service='meet', session='session-1', segment='1', speaker='María Rossi', text='Please send the budget.')
        self.write_state()

    def tearDown(self):
        self.temp.cleanup()

    def write_state(self):
        (self.directory / 'caption-state.json').write_text(json.dumps(self.state))

    def test_accepts_caption(self):
        self.assertTrue(host.accept(self.message, self.directory)['ok'])
        row = json.loads((self.directory / ('captions-' + 'a' * 32 + '.jsonl')).read_text())
        self.assertEqual(row['speaker'], 'María Rossi')
        self.assertNotIn('url', row)

    def test_disabled(self):
        self.state['enabled'] = False; self.write_state()
        self.assertFalse(host.accept(self.message, self.directory)['ok'])

    def test_stale_recording(self):
        self.state['updated'] -= 20; self.write_state()
        self.assertFalse(host.accept(self.message, self.directory)['ok'])

    def test_wrong_service(self):
        self.message['url'] = 'https://teams.microsoft.com/v2/'; self.message['service'] = 'teams'
        self.assertFalse(host.accept(self.message, self.directory)['ok'])

    def test_unknown_host(self):
        self.message['url'] = 'https://meet.google.com.attacker.invalid/'
        self.assertFalse(host.accept(self.message, self.directory)['ok'])

    def test_requires_https(self):
        self.message['url'] = 'http://meet.google.com/test'
        self.assertFalse(host.accept(self.message, self.directory)['ok'])

    def test_rejects_traversal(self):
        self.state['token'] = '../../escape'; self.write_state()
        self.assertFalse(host.accept(self.message, self.directory)['ok'])

    def test_rejects_oversized_caption(self):
        self.message['text'] = 'x' * 12001
        self.assertFalse(host.accept(self.message, self.directory)['ok'])

    def test_rejects_missing_speaker(self):
        self.message['speaker'] = ''
        self.assertFalse(host.accept(self.message, self.directory)['ok'])


if __name__ == '__main__':
    unittest.main()
