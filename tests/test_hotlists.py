"""热榜模块离线回归：解析、失败兜底与 generate 主流程接线。不访问网络。"""
import copy
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
import hotlists as h

WEIBO_PAYLOAD = {
    "ok": 1,
    "data": {
        "realtime": [
            {"realpos": 1, "note": "大模型公司发布开源模型", "word": "大模型公司发布开源模型",
             "num": 1234567, "label_name": "爆", "word_scheme": "#大模型公司发布开源模型#", "topic_flag": 1},
            {"realpos": 2, "note": "央行宣布新工具", "word": "央行宣布新工具",
             "num": 98765, "icon_desc": "新", "topic_flag": 0},
            {"realpos": None, "note": "广告词条不该出现", "num": 100, "is_ad": 1},
            {"realpos": 3, "note": "大模型公司发布开源模型", "num": 50},
        ]
    },
}

ZHIHU_PAYLOAD = {
    "data": [
        {"target": {"title": "如何看懂新一轮产业政策的影响？", "url": "https://api.zhihu.com/questions/123456",
                    "answer_count": 42}, "detail_text": "784 万热度"},
        {"target": {"title": "设计师如何应对工具变化？", "url": "https://api.zhihu.com/questions/789",
                    "answer_count": 7}, "detail_text": ""},
    ]
}


class ParseTests(unittest.TestCase):
    def test_weibo_parse_drops_ads_and_duplicates(self):
        with patch.object(h, "_curl_json", return_value=WEIBO_PAYLOAD):
            result = h.fetch_weibo_hot()
        titles = [item["title"] for item in result["items"]]
        self.assertEqual(["大模型公司发布开源模型", "央行宣布新工具"], titles)
        self.assertEqual("爆", result["items"][0]["label"])
        self.assertEqual("新", result["items"][1]["label"])
        self.assertEqual("123.5万", result["items"][0]["heat"])
        self.assertTrue(result["items"][0]["url"].startswith("https://s.weibo.com/weibo?q="))
        self.assertTrue(result["updated_at"])

    def test_weibo_requires_items(self):
        with patch.object(h, "_curl_json", return_value={"ok": 1, "data": {"realtime": []}}):
            with self.assertRaises(ValueError):
                h.fetch_weibo_hot()

    def test_zhihu_parse(self):
        with patch.object(h, "_curl_json", return_value=ZHIHU_PAYLOAD):
            result = h.fetch_zhihu_hot()
        first = result["items"][0]
        self.assertEqual("如何看懂新一轮产业政策的影响？", first["title"])
        self.assertEqual("https://www.zhihu.com/question/123456", first["url"])
        self.assertEqual("784万", first["heat"])
        self.assertEqual("", first["label"])
        self.assertEqual("7 回答", result["items"][1]["heat"])

    def test_collect_keeps_snapshot_on_failure(self):
        stale = {"sources": [{"id": "weibo", "name": "微博热搜", "updated_at": "2026-10-29T09:00:00+08:00",
                              "items": [{"title": "旧词条", "url": "https://s.weibo.com/weibo?q=x",
                                         "heat": "10万", "label": ""}]}]}

        def broken():
            raise OSError("network")

        def working_zhihu():
            return {"id": "zhihu", "name": "知乎热榜", "updated_at": "x",
                    "items": [{"title": "t", "url": "u", "heat": "", "label": ""}]}

        with patch.dict(h.FETCHERS, {"weibo": broken, "zhihu": working_zhihu}, clear=True):
            result = h.collect_hotlists(existing=stale)
        ids = [source["id"] for source in result["sources"]]
        self.assertEqual(["weibo", "zhihu"], ids)
        self.assertEqual("旧词条", result["sources"][0]["items"][0]["title"])

    def test_collect_failure_without_snapshot_drops_source(self):
        def broken():
            raise OSError("down")

        with patch.dict(h.FETCHERS, {"weibo": broken, "zhihu": broken}, clear=True):
            result = h.collect_hotlists(existing=None)
        self.assertEqual([], result["sources"])

    def test_heat_format(self):
        self.assertEqual("1.2亿", h.format_heat(123_456_789))
        self.assertEqual("10.0万", h.format_heat(100_000))
        self.assertEqual("9999", h.format_heat(9999))
        self.assertEqual("", h.format_heat(None))


class WiringTests(unittest.TestCase):
    def test_generate_injects_hotlists_after_tts(self):
        import generate as g
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("data", "cache", "reports", "logs"):
                (root / name).mkdir()
            board = {"updated_at": "t", "sources": [{"id": "weibo", "name": "微博热搜", "updated_at": "t",
                                                     "items": [{"title": "词条", "url": "u", "heat": "1万", "label": "热"}]}]}
            with patch.object(g, "DATA_DIR", root / "data"), \
                 patch.object(g, "CACHE_DIR", root / "cache"), \
                 patch.object(g, "REPORT_DIR", root / "reports"), \
                 patch.object(g, "LOG_DIR", root / "logs"), \
                 patch.object(g, "EXPORT_DIR", root / "reports"), \
                 patch.object(g, "call_ai", return_value=""), \
                 patch("tts_brief.generate_from_digest", return_value={}), \
                 patch("hotlists.collect_hotlists", return_value=board) as collect:
                code = g.main()
            self.assertEqual(0, code)
            collect.assert_called_once()
            written = json.loads((root / "data" / "latest.json").read_text(encoding="utf-8"))
            self.assertEqual("词条", written["hotlists"]["sources"][0]["items"][0]["title"])
            self.assertEqual(["weibo"], [s["id"] for s in written["hotlists"]["sources"]])


if __name__ == "__main__":
    unittest.main()
