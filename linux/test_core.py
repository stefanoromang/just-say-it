from pathlib import Path
import tempfile
import unittest
from core import combined, merge_caption, parse_transcript, unique_note, version_parts, release_asset, route


class CoreTests(unittest.TestCase):
    def test_vtt_names(self):
        rows = parse_transcript('WEBVTT\n\n00:00:01.000 --> 00:00:03.000\n<v María Rossi>Hello &amp; welcome.</v>\n\n00:00:04.000 --> 00:00:05.000\n<v Stefano>Thank you.</v>')
        self.assertEqual(rows, [{'speaker': 'María Rossi', 'text': 'Hello & welcome.'}, {'speaker': 'Stefano', 'text': 'Thank you.'}])

    def test_srt(self):
        self.assertEqual(parse_transcript('1\n00:00:01,000 --> 00:00:02,000\nAna: Hola.')[0]['speaker'], 'Ana')

    def test_no_guessed_identity(self):
        self.assertEqual(parse_transcript('Unattributed speech.')[0]['speaker'], 'Speaker')

    def test_caption_revisions(self):
        lines = []; row = dict(service='meet', session='meeting-1', segment='1', speaker='Ana', text='Hello')
        session = merge_caption(lines, row, None)
        merge_caption(lines, dict(row, text='Hello everyone.'), session)
        self.assertEqual(len(lines), 1); self.assertEqual(lines[0]['text'], 'Hello everyone.')
        merge_caption(lines, dict(row, session='other'), session)
        self.assertEqual(len(lines), 1)

    def test_sources_separate(self):
        self.assertIn('LOCAL AUDIO BACKUP', combined('Me: hello', [dict(speaker='Ana', text='Hola')]))

    def test_never_overwrites(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = unique_note(tmp, 'Meeting'); path.write_text('Keep me')
            second = unique_note(tmp, 'Meeting')
            self.assertNotEqual(path, second); self.assertEqual(path.read_text(), 'Keep me')

    def test_version(self):
        self.assertGreater(version_parts('v2.10'), version_parts('2.9.0'))
        with self.assertRaises(ValueError): version_parts('2.7;execute')

    def test_update_source_and_hash(self):
        release = dict(tag_name='v2.8', assets=[dict(name='just-say-it_2.8.0_all.deb', digest='sha256:' + 'a' * 64, browser_download_url='https://github.com/stefanoromang/just-say-it/releases/download/v2.8/test.deb')])
        self.assertIsNotNone(release_asset(release))
        release['assets'][0]['browser_download_url'] = 'https://attacker.invalid/payload'
        with self.assertRaises(ValueError): release_asset(release)

    def test_collectiviq_rule(self):
        self.assertEqual(route('route:notetaker:Notetaker', 'RAW', 'AI'), ('Notetaker', 'RAW'))
        self.assertEqual(route('route:assistant:Ana', 'RAW', 'AI'), ('Ana', 'AI'))
        self.assertEqual(route('route:none', 'RAW', 'AI'), (None, 'AI'))


if __name__ == '__main__': unittest.main()
