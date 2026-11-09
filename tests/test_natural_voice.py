"""离线验证自然音色的配置、帧计时和失败保护，不调用在线语音服务。"""
import importlib.util
import json
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "natural_voice_under_test", Path(__file__).resolve().parents[1] / "backend" / "tts_brief.py"
)
tts = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tts)


class NaturalVoiceTests(unittest.TestCase):
    date = "2026-10-28"
    config = {"engine": "edge", "voice": "zh-CN-YunyangNeural", "rate": 200, "natural_rate": "+0%"}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.target = Path(self.tmp.name)
        self.python = self.target / ".venv-tts" / "bin" / "python"
        self.python.parent.mkdir(parents=True)
        self.python.touch()
        self.calls = []
        self.chapters = [{"title": str(i), "text": "同样长度的新闻正文。"} for i in range(10)]
        self.patchers = [patch.object(tts, "TTS_DIR", self.target), patch.object(tts, "TTS_PYTHON", self.python)]
        for patcher in self.patchers:
            patcher.start()
            self.addCleanup(patcher.stop)

    def write_previous_bundle(self):
        paths = [self.target / ("brief-" + self.date + extension)
                 for extension in (".aiff", ".txt", ".json", ".chapters.json")]
        for path in paths:
            path.write_bytes(b"previous complete bundle")
        return paths

    def mock_run(self, cmd, **kwargs):
        self.calls.append(cmd)
        if cmd[0] == str(self.python):
            self.assertEqual(cmd[1], str(tts.EDGE_SYNTHESIZER))
            Path(cmd[cmd.index("--output") + 1]).write_bytes(b"MP3 placeholder")
        elif cmd[0] == "/usr/bin/afconvert" and cmd[cmd.index("-f") + 1] == "WAVE":
            self.assertEqual(cmd[cmd.index("-d") + 1], "LEI16@24000")
            self.assertEqual(cmd[cmd.index("-c") + 1], "1")
            # Deliberately different frame lengths for identical text lengths.
            index = int(Path(cmd[-2]).stem)
            with wave.open(cmd[-1], "wb") as writer:
                writer.setnchannels(1)
                writer.setsampwidth(2)
                writer.setframerate(24000)
                writer.writeframes(b"\0\0" * ((60 + index) * 24000 + index * 120))
        elif cmd[0] == "/usr/bin/afconvert" and cmd[cmd.index("-f") + 1] == "AIFF":
            with wave.open(cmd[-2], "rb") as reader:
                decoded = [call for call in self.calls if call[0] == "/usr/bin/afconvert" and "WAVE" in call]
                expected_frames = sum((60 + i) * 24000 + i * 120 for i in range(len(decoded)))
                self.assertEqual(reader.getnframes(), expected_frames)
            Path(cmd[-1]).write_bytes(b"FORM\x00\x00\x00\x04AIFF")
        else:
            self.fail("Unexpected renderer subprocess: " + str(cmd))
        return subprocess.CompletedProcess(cmd, 0, "", "")

    def test_edge_records_actual_voice_rate_and_precise_frame_marks(self):
        with patch.object(tts.subprocess, "run", side_effect=self.mock_run), patch.object(
            tts, "audio_duration", return_value=645.225
        ):
            result = tts.render_audio(self.chapters, self.date, self.config)
        self.assertNotIn("error", result)
        self.assertEqual(result["duration"], 645.225)
        self.assertEqual(result["sample_frames"], 645 * 24000 + 45 * 120)
        self.assertEqual(result["sample_rate"], 24000)
        self.assertEqual(result["engine"], "edge")
        self.assertEqual(result["voice"], "zh-CN-YunyangNeural")
        self.assertEqual(result["rate"], "+0%")
        self.assertEqual(result["natural_rate"], "+0%")
        expected = [round(sum(60 + j + j * 0.005 for j in range(i)), 3) for i in range(10)]
        marks = json.loads((self.target / f"brief-{self.date}.chapters.json").read_text())
        self.assertEqual([chapter["start"] for chapter in marks], expected)
        synth_calls = [call for call in self.calls if call[0] == str(self.python)]
        self.assertEqual(len(synth_calls), 10)
        for call in synth_calls:
            self.assertEqual(call[call.index("--voice") + 1], "zh-CN-YunyangNeural")
            self.assertIn("--rate=+0%", call)
        self.assertFalse(any(call[0] == "/usr/bin/say" for call in self.calls))

    def test_online_failure_preserves_previous_bundle_without_local_fallback(self):
        old_paths = self.write_previous_bundle()
        error = subprocess.CalledProcessError(1, [str(self.python)], stderr="在线语音服务返回 HTTP 403")
        with patch.object(tts.subprocess, "run", side_effect=error) as run:
            result = tts.render_audio(self.chapters, self.date, self.config)
        self.assertIn("HTTP 403", result["error"])
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][0], str(self.python))
        for path in old_paths:
            self.assertEqual(path.read_bytes(), b"previous complete bundle")

    def test_missing_venv_is_actionable_and_never_uses_say(self):
        old_paths = self.write_previous_bundle()
        self.python.unlink()
        with patch.object(tts.subprocess, "run") as run:
            result = tts.render_audio(self.chapters, self.date, self.config)
        self.assertIn("setup_tts.sh", result["error"])
        run.assert_not_called()
        for path in old_paths:
            self.assertEqual(path.read_bytes(), b"previous complete bundle")

    def test_short_natural_program_keeps_natural_rate_and_publishes(self):
        self.write_previous_bundle()
        with patch.object(tts.subprocess, "run", side_effect=self.mock_run), patch.object(
            tts, "audio_duration", return_value=60.0
        ):
            result = tts.render_audio(self.chapters[:1], self.date, self.config)
        self.assertEqual(result["duration"], 60.0)
        self.assertEqual(len([call for call in self.calls if call[0] == str(self.python)]), 1)
        self.assertFalse(any(call[0] == "/usr/bin/say" for call in self.calls))
        self.assertTrue(Path(result["audio_path"]).is_file())

    def test_publication_failure_rolls_back_all_previous_files(self):
        old_paths = self.write_previous_bundle()
        original_replace = Path.replace

        def replace(source, destination):
            if source.name == f"brief-{self.date}.chapters.json":
                raise OSError("publication failed")
            return original_replace(source, destination)

        with patch.object(tts.subprocess, "run", side_effect=self.mock_run), patch.object(
            tts, "audio_duration", return_value=645.225
        ), patch.object(Path, "replace", new=replace):
            result = tts.render_audio(self.chapters, self.date, self.config)
        self.assertIn("publication failed", result["error"])
        for path in old_paths:
            self.assertEqual(path.read_bytes(), b"previous complete bundle")

    def test_configured_small_rate_adjustment_is_passed_to_service(self):
        with patch.object(tts.subprocess, "run", side_effect=self.mock_run), patch.object(
            tts, "audio_duration", return_value=645.225
        ):
            result = tts.render_audio(self.chapters, self.date, dict(self.config, natural_rate="+5%"))
        self.assertEqual(result["rate"], "+5%")
        self.assertEqual(result["natural_rate"], "+5%")
        for call in self.calls:
            if call[0] == str(self.python):
                self.assertIn("--rate=+5%", call)

    def test_invalid_natural_rate_rejected_before_network(self):
        for value in ("-11%", "+16%", "slow", None):
            with self.subTest(value=value), patch.object(tts.subprocess, "run") as run:
                result = tts.render_audio(self.chapters, self.date, dict(self.config, natural_rate=value))
                self.assertIn("natural_rate", result["error"])
                run.assert_not_called()
        self.assertEqual(tts._natural_rate("-10%"), "-10%")
        self.assertEqual(tts._natural_rate("+15%"), "+15%")
        self.assertEqual(tts._natural_rate("0%"), "+0%")

    def test_config_loads_explicit_edge_voice_and_rate_and_legacy_defaults(self):
        path = self.target / "config.json"
        with patch.object(tts, "CONFIG_PATH", path):
            path.write_text(json.dumps({"tts": self.config}))
            self.assertEqual(tts.load_tts_config()["voice"], "zh-CN-YunyangNeural")
            self.assertEqual(tts.load_tts_config()["natural_rate"], "+0%")
            path.write_text(json.dumps({"tts": {"engine": "edge"}}))
            self.assertEqual(tts.load_tts_config()["voice"], "zh-CN-YunyangNeural")
            path.write_text(json.dumps({"tts": {"voice": "Tingting", "rate": 200}}))
            self.assertEqual(tts.load_tts_config()["engine"], "say")
            self.assertEqual(tts.load_tts_config()["voice"], "Tingting")


if __name__ == "__main__":
    unittest.main()
