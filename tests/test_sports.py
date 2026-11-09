"""NBA 赛事数据的离线回归：ESPN 解析、状态中文化、分类排序。不访问网络。"""
import json
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
import sports as sp

NOW = datetime(2026, 10, 31, 9, 0, tzinfo=timezone(timedelta(hours=8)))

def event(eid, away, home, away_score, home_score, state, detail, utc):
    return {
        "id": eid, "date": utc,
        "competitions": [{
            "competitors": [
                {"homeAway": "away", "score": str(away_score), "team": {"displayName": away}},
                {"homeAway": "home", "score": str(home_score), "team": {"displayName": home}},
            ],
            "status": {"type": {"state": state, "shortDetail": detail}},
        }],
    }

class BuildGamesTests(unittest.TestCase):
    def test_parse_maps_names_status_and_order(self):
        events = [
            event("1", "Boston Celtics", "Chicago Bulls", 52, 32, "in", "10:18 - 2nd", "2026-10-30T23:30:00Z"),
            event("2", "Washington Wizards", "Charlotte Hornets", 51, 46, "in", "Halftime", "2026-10-30T23:00:00Z"),
            event("3", "Los Angeles Lakers", "Golden State Warriors", 112, 108, "post", "Final", "2026-10-30T02:30:00Z"),
            event("4", "New York Knicks", "Toronto Raptors", None, None, "pre", "", "2026-10-31T23:30:00Z"),
        ]
        games = sp.build_games(events, NOW)
        self.assertEqual([g["state"] for g in games], ["in", "in", "post", "pre"])
        first = games[0]
        self.assertEqual(first["away"], "凯尔特人")
        self.assertEqual(first["home"], "公牛")
        self.assertEqual(first["detail"], "第2节 10:18")
        self.assertEqual(games[1]["detail"], "中场休息")
        final = games[2]
        self.assertEqual(final["home"], "勇士")
        self.assertEqual(final["away"], "湖人")
        self.assertEqual(final["home_score"], 108)
        self.assertEqual(final["start_text"], "10月30日 10:30")
        pre = games[3]
        self.assertIsNone(pre["away_score"])
        self.assertEqual(pre["home"], "猛龙")

    def test_final_ordering_newest_first(self):
        events = [
            event("a", "Los Angeles Lakers", "Boston Celtics", 100, 99, "post", "Final", "2026-10-30T02:00:00Z"),
            event("b", "Miami Heat", "New York Knicks", 88, 102, "post", "Final", "2026-10-30T00:00:00Z"),
        ]
        games = sp.build_games(events, NOW)
        self.assertEqual(games[0]["away"], "湖人")
        self.assertEqual(games[1]["away"], "热火")

    def test_collect_sports_failure_returns_empty(self):
        with patch.object(sp, "fetch_nba", side_effect=ValueError("down")):
            self.assertEqual(sp.collect_sports(), {})

    def test_collect_sports_success_shape(self):
        with patch.object(sp, "fetch_nba", return_value={"updated_at": "t", "games": []}):
            result = sp.collect_sports()
        self.assertEqual(result["nba"]["games"], [])

class TtsNbaLineTests(unittest.TestCase):
    def test_nba_brief_line(self):
        import tts_brief as t
        sports = {"nba": {"games": [
            {"state": "post", "home": "凯尔特人", "away": "篮网", "home_score": 95, "away_score": 88},
            {"state": "post", "home": "奇才", "away": "黄蜂", "home_score": 51, "away_score": 103},
            {"state": "in", "home": "湖人", "away": "快船", "home_score": 10, "away_score": 8},
        ]}}
        line = t._nba_brief_line(sports)
        self.assertIn("凯尔特人95比88击败篮网", line)
        self.assertIn("黄蜂103比51击败奇才", line)
        self.assertNotIn("湖人", line)
        self.assertTrue(line.startswith("昨晚NBA战报："))

    def test_nba_brief_line_empty_without_finals(self):
        import tts_brief as t
        self.assertEqual(t._nba_brief_line({"nba": {"games": [{"state": "in"}]}}), "")
        self.assertEqual(t._nba_brief_line(None), "")

if __name__ == "__main__":
    unittest.main()
