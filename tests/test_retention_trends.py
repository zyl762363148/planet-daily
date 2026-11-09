"""保留策略与热榜趋势的离线回归。不访问网络、不碰用户数据。"""
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
import generate as g
import hotlists as h

NOW = datetime(2026, 10, 30, 9, 0, tzinfo=timezone(timedelta(hours=8)))


def make_dir_tree(root: Path, *, old_json: bool, old_audio: bool, old_cache: bool):
    data = root / "data"
    tts = data / "tts"
    cache = root / "cache"
    reports = root / "reports"
    for directory in (data, tts, cache, reports):
        directory.mkdir(parents=True, exist_ok=True)
    old_date = "2026-06-01"
    new_date = "2026-10-29"
    (data / f"{new_date}.json").write_text("{}", encoding="utf-8")
    (data / "latest.json").write_text("{}", encoding="utf-8")
    (data / "favorites.json").write_text("[]", encoding="utf-8")
    (tts / f"brief-{new_date}.aiff").write_bytes(b"x")
    if old_json:
        (data / f"{old_date}.json").write_text("{}", encoding="utf-8")
        (reports / f"{old_date}.md").write_text("x", encoding="utf-8")
        (reports / f"brief-{old_date}.md").write_text("x", encoding="utf-8")
        (reports / f"email-{old_date}.html").write_text("x", encoding="utf-8")
    if old_audio:
        (tts / f"brief-{old_date}.aiff").write_bytes(b"x")
        (tts / f"brief-{old_date}.txt").write_text("x", encoding="utf-8")
        (tts / f"brief-{old_date}.chapters.json").write_text("[]", encoding="utf-8")
    if old_cache:
        stale = cache / "weather-stale.json"
        stale.write_text("{}", encoding="utf-8")
        stale_time = (NOW - timedelta(days=40)).timestamp()
        import os
        os.utime(stale, (stale_time, stale_time))
        (cache / "weather-fresh.json").write_text("{}", encoding="utf-8")


class RetentionTests(unittest.TestCase):
    def test_old_files_removed_new_kept(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_dir_tree(root, old_json=True, old_audio=True, old_cache=True)
            removed = g.cleanup_expired(
                now=NOW,
                retention={"audio_days": 30, "json_days": 90, "cache_days": 14},
                data_dir=root / "data",
                cache_dir=root / "cache",
                report_dir=root / "reports",
            )
            self.assertEqual(removed["audio"], 3)
            self.assertEqual(removed["json"], 1)
            self.assertEqual(removed["report"], 3)
            self.assertEqual(removed["cache"], 1)
            data = root / "data"
            self.assertFalse((data / "2026-06-01.json").exists())
            self.assertFalse((data / "tts" / "brief-2026-06-01.aiff").exists())
            self.assertTrue((data / "2026-10-29.json").exists())
            self.assertTrue((data / "latest.json").exists())
            self.assertTrue((data / "favorites.json").exists())
            self.assertTrue((data / "tts" / "brief-2026-10-29.aiff").exists())
            self.assertFalse((root / "cache" / "weather-stale.json").exists())
            self.assertTrue((root / "cache" / "weather-fresh.json").exists())

    def test_zero_keeps_everything(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_dir_tree(root, old_json=True, old_audio=True, old_cache=True)
            g.cleanup_expired(
                now=NOW,
                retention={"audio_days": 0, "json_days": 0, "cache_days": 0},
                data_dir=root / "data",
                cache_dir=root / "cache",
                report_dir=root / "reports",
            )
            self.assertTrue((root / "data" / "2026-06-01.json").exists())
            self.assertTrue((root / "data" / "tts" / "brief-2026-06-01.aiff").exists())
            self.assertTrue((root / "cache" / "weather-stale.json").exists())

    def test_default_retention_read_from_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "config.json").write_text(
                json.dumps({"retention": {"audio_days": 7}}), encoding="utf-8"
            )
            with patch.object(g, "BASE_DATA_ROOT", root):
                retention = g.load_retention()
            self.assertEqual(retention["audio_days"], 7)
            self.assertEqual(retention["json_days"], g.DEFAULT_RETENTION["json_days"])


def source(items):
    return {"id": "weibo", "name": "微博热搜", "updated_at": "x",
            "items": [{"title": t, "url": "u", "heat": "", "label": ""} for t in items]}


class TrendTests(unittest.TestCase):
    def test_prev_rank_annotated_from_previous_day(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            prev_day = data / "2026-10-29.json"
            prev_day.write_text(json.dumps({
                "date": "2026-10-29",
                "hotlists": {"updated_at": "x", "sources": [source(["旧一", "旧二", "旧三"])]},
            }, ensure_ascii=False), encoding="utf-8")
            board = {"updated_at": "t", "sources": [source(["旧二", "新一", "旧一"])]}
            result = h.annotate_trends(board, "2026-10-30", data_dir=data)
            items = result["sources"][0]["items"]
            self.assertEqual(items[0]["prev_rank"], 2)   # 旧二：昨天第 2
            self.assertNotIn("prev_rank", items[1])      # 新一：昨天未上榜
            self.assertEqual(items[2]["prev_rank"], 1)   # 旧一：昨天第 1

    def test_no_previous_snapshot_is_noop(self):
        with tempfile.TemporaryDirectory() as tmp:
            board = {"updated_at": "t", "sources": [source(["甲", "乙"])]}
            result = h.annotate_trends(board, "2026-10-30", data_dir=Path(tmp))
            self.assertEqual(result["sources"][0]["items"][0], board["sources"][0]["items"][0])

    def test_looks_back_past_gaps(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            # 10-28 有快照，10-29 缺失：应回看到 10-28
            (data / "2026-10-28.json").write_text(json.dumps({
                "date": "2026-10-28",
                "hotlists": {"updated_at": "x", "sources": [source(["旧甲"])]},
            }, ensure_ascii=False), encoding="utf-8")
            board = {"updated_at": "t", "sources": [source(["旧甲", "乙"])]}
            result = h.annotate_trends(board, "2026-10-30", data_dir=data)
            self.assertEqual(result["sources"][0]["items"][0]["prev_rank"], 1)

    def test_unknown_source_id_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            (data / "2026-10-29.json").write_text(json.dumps({
                "date": "2026-10-29",
                "hotlists": {"updated_at": "x", "sources": [source(["甲"])]},
            }, ensure_ascii=False), encoding="utf-8")
            zhihu_board = {"updated_at": "t", "sources": [
                {"id": "zhihu", "name": "知乎热榜", "updated_at": "x",
                 "items": [{"title": "甲", "url": "u", "heat": "", "label": ""}]}]}
            result = h.annotate_trends(zhihu_board, "2026-10-30", data_dir=data)
            self.assertNotIn("prev_rank", result["sources"][0]["items"][0])


if __name__ == "__main__":
    unittest.main()
