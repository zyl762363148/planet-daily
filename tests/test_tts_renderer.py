import importlib.util
import json
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('renderer_test_module', Path(__file__).parents[1] / 'backend/tts_brief.py')
tts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tts)

class RenderingTests(unittest.TestCase):
    def test_failure_preserves_previous_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            names = ['brief-2026-10-28' + ext for ext in ('.aiff', '.txt', '.json', '.chapters.json')]
            for name in names:
                (target / name).write_bytes(b'previous')
            with patch.object(tts, 'TTS_DIR', target), patch.object(tts.subprocess, 'run', side_effect=OSError('missing voice')):
                result = tts.render_audio([{'title':'开场','text':'今天的节目。'}], '2026-10-28', {'voice':'Tingting','rate':200})
            self.assertIn('error', result)
            for name in names:
                self.assertEqual((target / name).read_bytes(), b'previous')

    def test_chapters_use_measured_pcm_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            def run(cmd, **kwargs):
                if cmd[0] == '/usr/bin/say':
                    index = int(Path(cmd[cmd.index('-f') + 1]).stem)
                    # Every section deliberately has a different duration/character ratio.
                    frames = 60 + index
                    with wave.open(cmd[cmd.index('-o') + 1], 'wb') as writer:
                        writer.setnchannels(1); writer.setsampwidth(2); writer.setframerate(1)
                        writer.writeframes(b'\x00\x00' * frames)
                elif cmd[0] == '/usr/bin/afconvert':
                    Path(cmd[-1]).write_bytes(b'FORM-test-AIFF')
                return subprocess.CompletedProcess(cmd, 0, '', '')
            chapters = [{'title': str(i), 'text':'相同字数。'} for i in range(10)]
            with patch.object(tts, 'TTS_DIR', target), patch.object(tts.subprocess, 'run', side_effect=run), patch.object(tts, 'audio_duration', return_value=645.0):
                result = tts.render_audio(chapters, '2026-10-28', {'voice':'Tingting','rate':200})
            self.assertEqual(result['duration'], 645.0)
            marks = json.loads((target / 'brief-2026-10-28.chapters.json').read_text())
            self.assertEqual([x['start'] for x in marks], [sum(60+j for j in range(i)) for i in range(10)])
            self.assertEqual(result['chapter_timing'], 'pcm_frames')

if __name__ == '__main__': unittest.main()
