"""定时、跨进程互斥与失败重试；不发声、不读取或写入真实用户配置。"""

import importlib.util
import json
from datetime import datetime
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "speak_brief_under_test", Path(__file__).resolve().parents[1] / "backend" / "speak_brief.py"
)
speak = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(speak)


class SchedulerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.tts = self.root / "data" / "tts"
        self.config = self.root / "config.json"
        self.now = datetime(2026, 10, 28, 9, 10)
        for name, value in (
            ("TTS_DIR", self.tts), ("CONFIG_PATH", self.config),
            ("LOG_DIR", self.root / "logs"), ("LOG_PATH", self.root / "logs" / "speak.log"),
        ):
            patcher = mock.patch.object(speak, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def make_audio(self):
        self.tts.mkdir(parents=True, exist_ok=True)
        path = self.tts / "brief-2026-10-28.aiff"
        path.write_bytes(b"audio fixture, never played")
        return path

    def write_config(self, **tts):
        self.config.write_text(json.dumps({"tts": tts}))

    def snapshot(self):
        return {str(path.relative_to(self.root)): path.read_bytes()
                for path in self.root.rglob("*") if path.is_file()}

    def test_missing_config_uses_requested_defaults(self):
        self.assertEqual(speak.load_tts_config(), {
            "enabled": True, "time": "09:10", "rate": 200, "voice": "Tingting"
        })

    def test_malformed_config_fails_closed(self):
        self.config.write_text('{"tts":')
        self.assertEqual(speak.run(now=self.now), 1)
        self.assertFalse(self.tts.exists())

    def test_invalid_values_are_rejected(self):
        for values in ({"enabled": "false"}, {"time": "08:99"}, {"time": "09:-1"},
                       {"time": "9:10"}, {"rate": True}, {"rate": 0}, {"voice": ""}):
            with self.subTest(values=values):
                self.write_config(**values)
                with self.assertRaises(ValueError):
                    speak.load_tts_config()

    def test_schedule_window_boundaries(self):
        for clock, expected in (("09:09:59", False), ("09:10:00", True),
                                ("09:39:59", True), ("09:40:00", False)):
            with self.subTest(clock=clock):
                now = datetime.strptime("2026-10-28 " + clock, "%Y-%m-%d %H:%M:%S")
                self.assertEqual(speak.is_due(now, "09:10"), expected)

    def test_marker_is_per_date_and_configured_time(self):
        self.make_audio()
        speak.mark_played("2026-10-28", "09:10")
        self.assertTrue(speak.already_played("2026-10-28", "09:10"))
        self.assertFalse(speak.already_played("2026-10-28", "09:12"))
        speak.clear_played("2026-10-28", "09:12")
        self.assertTrue(speak.already_played("2026-10-28", "09:10"))
        speak.clear_played("2026-10-28", "09:10")
        self.assertFalse(speak.marker_path("2026-10-28").exists())

    def test_old_marker_format_does_not_block_new_schedule(self):
        self.make_audio()
        speak.marker_path("2026-10-28").write_text("2026-10-28T09:10:00")
        self.assertFalse(speak.already_played("2026-10-28", "09:10"))

    def test_lock_is_exclusive_and_released_on_close(self):
        first = speak.acquire_playback_lock()
        self.assertIsNotNone(first)
        try:
            self.assertIsNone(speak.acquire_playback_lock())
        finally:
            first.close()
        second = speak.acquire_playback_lock()
        self.assertIsNotNone(second)
        second.close()

    def test_process_detection_distinguishes_missing_from_error(self):
        for code, expected in ((0, True), (1, False), (3, None)):
            with self.subTest(code=code), mock.patch.object(
                speak.subprocess, "run", return_value=mock.Mock(returncode=code)
            ) as run:
                self.assertIs(speak.app_running(read_only=True), expected)
                self.assertEqual(run.call_args.args[0], ["/usr/bin/pgrep", "-x", "DailyDigest"])

    def test_dry_run_is_strictly_read_only(self):
        self.make_audio()
        self.write_config(time="09:10")
        before = self.snapshot()
        with mock.patch.object(speak, "app_running", return_value=False), mock.patch.object(
            speak.subprocess, "Popen"
        ) as popen:
            self.assertEqual(speak.run(now=self.now, dry_run=True), 0)
            popen.assert_not_called()
        self.assertEqual(self.snapshot(), before)
        self.assertFalse((self.tts / ".playback.lock").exists())
        self.assertFalse((self.root / "logs").exists())

    def test_dry_run_missing_audio_does_not_generate_or_create_directories(self):
        self.assertEqual(speak.run(now=self.now, dry_run=True), 0)
        self.assertEqual(self.snapshot(), {})
        self.assertFalse(self.tts.exists())

    def test_force_still_obeys_lock(self):
        self.make_audio()
        first = speak.acquire_playback_lock()
        try:
            with mock.patch.object(speak.subprocess, "Popen") as popen:
                self.assertEqual(speak.run(now=self.now, force=True), 0)
                popen.assert_not_called()
        finally:
            first.close()

    def test_app_running_delegates_without_marking_played(self):
        self.make_audio()
        with mock.patch.object(speak, "app_running", return_value=True), mock.patch.object(
            speak.subprocess, "Popen"
        ) as popen:
            self.assertEqual(speak.run(now=self.now), 0)
            popen.assert_not_called()
        self.assertFalse(speak.marker_path("2026-10-28").exists())

    def test_unknown_process_state_does_not_play(self):
        self.make_audio()
        with mock.patch.object(speak, "app_running", return_value=None), mock.patch.object(
            speak.subprocess, "Popen"
        ) as popen:
            self.assertEqual(speak.run(now=self.now), 1)
            popen.assert_not_called()

    def test_successful_start_marks_and_inherits_lock(self):
        audio = self.make_audio()
        process = mock.Mock()
        process.wait.side_effect = [subprocess.TimeoutExpired("afplay", 0.25), 0]
        with speak.acquire_playback_lock() as lock, mock.patch.object(
            speak.subprocess, "Popen", return_value=process
        ) as popen:
            self.assertEqual(speak.play_audio(audio, "2026-10-28", "09:10", lock), 0)
            self.assertEqual(popen.call_args.kwargs["pass_fds"], (lock.fileno(),))
        self.assertTrue(speak.already_played("2026-10-28", "09:10"))
        self.assertEqual(process.wait.call_args.kwargs["timeout"], 1200)

    def test_startup_failure_does_not_mark(self):
        audio = self.make_audio()
        process = mock.Mock()
        process.wait.return_value = 1
        with speak.acquire_playback_lock() as lock, mock.patch.object(
            speak.subprocess, "Popen", return_value=process
        ):
            self.assertEqual(speak.play_audio(audio, "2026-10-28", "09:10", lock), 1)
        self.assertFalse(speak.marker_path("2026-10-28").exists())

    def test_runtime_failure_removes_own_marker(self):
        audio = self.make_audio()
        process = mock.Mock()
        process.wait.side_effect = [subprocess.TimeoutExpired("afplay", 0.25), 1]
        with speak.acquire_playback_lock() as lock, mock.patch.object(
            speak.subprocess, "Popen", return_value=process
        ):
            self.assertEqual(speak.play_audio(audio, "2026-10-28", "09:10", lock), 1)
        self.assertFalse(speak.marker_path("2026-10-28").exists())

    def test_timeout_stops_audio_and_allows_retry(self):
        audio = self.make_audio()
        process = mock.Mock()
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired("afplay", 0.25),
                                    subprocess.TimeoutExpired("afplay", 1200), 0]
        with speak.acquire_playback_lock() as lock, mock.patch.object(
            speak.subprocess, "Popen", return_value=process
        ):
            self.assertEqual(speak.play_audio(audio, "2026-10-28", "09:10", lock), 1)
        process.terminate.assert_called_once()
        self.assertFalse(speak.marker_path("2026-10-28").exists())

    def test_disabled_configuration_never_starts_player(self):
        self.make_audio()
        self.write_config(enabled=False)
        with mock.patch.object(speak.subprocess, "Popen") as popen:
            self.assertEqual(speak.run(now=self.now), 0)
            popen.assert_not_called()

    def test_changed_time_can_play_again_same_day(self):
        self.make_audio()
        speak.mark_played("2026-10-28", "09:08")
        with mock.patch.object(speak, "app_running", return_value=False), mock.patch.object(
            speak, "play_audio", return_value=0
        ) as play:
            self.assertEqual(speak.run(now=self.now), 0)
            play.assert_called_once()


if __name__ == "__main__":
    unittest.main()
