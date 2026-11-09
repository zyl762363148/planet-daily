import fcntl
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
import tts_brief

class VoiceRaceTests(unittest.TestCase):
    def test_explicit_missing_date_does_not_fall_back(self):
        with tempfile.TemporaryDirectory() as path, patch.object(tts_brief, 'DATA_DIR', Path(path)):
            (Path(path) / '2026-10-29.json').write_text('{}')
            self.assertEqual(tts_brief.load_digest('2026-10-28'), (None, None))
            self.assertEqual(tts_brief.load_digest('../etc/passwd'), (None, None))

    def test_parallel_render_is_refused_without_touching_prior_audio(self):
        with tempfile.TemporaryDirectory() as path, patch.object(tts_brief, 'TTS_DIR', Path(path)):
            audio = Path(path) / 'brief-2026-10-29.aiff'
            audio.write_bytes(b'prior audio')
            with (Path(path) / '.render-2026-10-29.lock').open('a+b') as held:
                fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = tts_brief.render_audio([], '2026-10-29', {})
                self.assertIn('正在生成', result['error'])
                self.assertEqual(audio.read_bytes(), b'prior audio')
