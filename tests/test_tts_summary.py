"""播报总结逻辑回归：编号播报、热榜一句话总结、AI 字数窗口与本地素材兜底。纯离线。"""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
import tts_brief as t

TODAY = "2026-10-29"


def digest_with(items_count=6, hotlists=None):
    def category(cid, name, n):
        return {
            "id": cid, "name": name, "icon": "i", "color": "#fff",
            "brief": f"{name}导语。",
            "items": [
                {"id": f"{cid}-{i}", "title": f"{name}条目{i}：某公司发布新产品并公开关键数据",
                 "summary": f"{name}条目{i}的事实摘要，交代了谁做了什么，关键影响仍在核实。",
                 "takeaway": f"{name}条目{i}的核心看点是供应链出现新变量。",
                 "interpretation": f"{name}条目{i}的解读：短期看执行，长期看标准。",
                 "perspective": "国内从业者关注落地节奏。",
                 "source": "公开信源", "url": "https://example.org/x", "score": 30 - i,
                 "audience": "开发者"}
                for i in range(n)
            ],
        }
    data = {
        "date": TODAY, "generated_at": "x",
        "categories": [
            category("wire", "环球通讯社", items_count),
            category("policy", "政策解读", items_count),
            category("ai", "AI", items_count),
            category("economy", "经济", items_count),
        ],
        "brief": {
            "headline": "全球 AI 与政策同日出现关键节点",
            "summary": "今天的重点在 AI 与政策的交汇处。",
            "points": [
                {"category": "AI", "category_id": "ai", "item_id": f"ai-{i}",
                 "text": f"人工智能条目{i}：某机构公布新的评测结果并开放数据集。"}
                for i in range(4)
            ],
            "opportunities": [
                {"title": "开源评测工具的跟进窗口", "category": "AI", "category_id": "ai",
                 "item_id": "ai-0", "why": "评测口径刚公开，工具生态还没定型。",
                 "how": "先读官方文档，再在隔离环境试验。", "audience": "开发者"}
            ],
        },
        "topic": {"title": "评测与标准的竞争", "summary": "多来源指向同一主题。",
                  "points": ["AI：评测口径成为竞争焦点。"], "tags": ["评测"], "item_ids": ["ai-0"]},
    }
    if hotlists is not None:
        data["hotlists"] = hotlists
    return data


BOARD = {
    "updated_at": "x",
    "sources": [
        {"id": "weibo", "name": "微博热搜", "updated_at": "x", "items": [
            {"title": "孙颖莎等10人记大功", "url": "u", "heat": "93万", "label": "新"},
            {"title": "以旧换新惠民生促消费", "url": "u", "heat": "63万", "label": ""},
        ]},
        {"id": "zhihu", "name": "知乎热榜", "updated_at": "x", "items": [
            {"title": "如何理解梁文锋「在颠覆性的技术面前，闭源形成的护城河是短暂的」这一判断？",
             "url": "u", "heat": "784 万热度", "label": ""},
        ]},
    ],
}


class HeadlineTests(unittest.TestCase):
    def setUp(self):
        # 离线：天气用固定句，周回顾指向空目录
        weather = patch.object(t, "fetch_weather_sentence", return_value="北京今天晴朗，气温约10到20摄氏度。")
        weekly_dir = patch.object(t, "DATA_DIR", Path(tempfile.mkdtemp()))
        weather.start()
        weekly_dir.start()
        self.addCleanup(weather.stop)
        self.addCleanup(weekly_dir.stop)
        self.chapters = t.build_ten_chapters(TODAY, digest_with(hotlists=BOARD))
        self.headline = self.chapters[1]["text"]

    def test_points_are_numbered_when_three_or_more(self):
        self.assertIn("第一条，", self.headline)
        self.assertIn("第二条，", self.headline)
        self.assertIn("第三条，", self.headline)

    def test_hot_topics_sentence_present(self):
        self.assertIn("微博热搜上", self.headline)
        self.assertIn("孙颖莎等10人记大功", self.headline)
        self.assertIn("知乎热榜上", self.headline)
        self.assertIn("热榜页", self.headline)

    def test_zhihu_long_question_is_clipped(self):
        # 完整知乎问句 40+ 字，应截到首个语义片段而不是整句照念
        self.assertNotIn("闭源形成的护城河", self.headline)

    def test_no_hotlists_leaves_no_placeholder(self):
        chapters = t.build_ten_chapters(TODAY, digest_with(hotlists=None))
        self.assertNotIn("热榜", chapters[1]["text"])
        self.assertNotIn("None", chapters[1]["text"])

    def test_top5_uses_numbered_markers(self):
        top = self.chapters[2]["text"]
        self.assertIn("先看第一条。", top)
        self.assertIn("最后是第五条。", top)

    def test_chapter_count_and_titles_unchanged(self):
        self.assertEqual(10, len(self.chapters))
        self.assertEqual("开场", self.chapters[0]["title"])
        self.assertEqual("收尾", self.chapters[9]["title"])

    def test_has_complete_nonempty_sections(self):
        self.assertTrue(all(ch["text"] for ch in self.chapters))


class AITests(unittest.TestCase):
    def _fake_opencode(self, text):
        def run(*args, **kwargs):
            class R:
                returncode = 0
                stdout = json.dumps({"type": "text", "part": {"text": text}})
            return R()
        return run

    def _ai_chapters_of_total(self, total, fallback, cover=True):
        opening = 60
        headline = min(500, max(total // 6, 2))
        rest = max((total - opening - headline) // (len(fallback) - 2), 2)
        sizes = [opening, headline] + [rest] * (len(fallback) - 2)
        chapters = [{"title": ch["title"], "text": "好。" * (size // 2), "item_ids": []}
                    for ch, size in zip(fallback, sizes)]
        if cover:
            chapters[1]["item_ids"] = [item["id"] for category in digest_with(hotlists=BOARD)["categories"] for item in category.get("items", [])]
        with patch.object(t.subprocess, "run", self._fake_opencode(json.dumps(chapters))):
            return t.ai_chapters(TODAY, digest_with(hotlists=BOARD), fallback)

    def test_ai_accepts_complete_program_at_any_length(self):
        fallback = t.build_ten_chapters(TODAY, digest_with(hotlists=BOARD))
        for total in (2700, 3200, 4000):
            result = self._ai_chapters_of_total(total, fallback)
            self.assertEqual([ch["title"] for ch in fallback], [ch["title"] for ch in result])
            self.assertEqual(result[-1]["text"], fallback[-1]["text"])

    def test_ai_missing_coverage_falls_back(self):
        fallback = t.build_ten_chapters(TODAY, digest_with(hotlists=BOARD))
        self.assertEqual([], self._ai_chapters_of_total(3000, fallback, cover=False))


class HotPhraseTests(unittest.TestCase):
    def test_short_title_kept_whole(self):
        self.assertEqual("孙颖莎等10人记大功", t._hot_topic_phrase("孙颖莎等10人记大功", 26))

    def test_long_question_clipped_to_first_clause(self):
        phrase = t._hot_topic_phrase("如何理解梁文锋「在颠覆性的技术面前，闭源形成的护城河是短暂的」这一判断？", 30)
        self.assertLessEqual(len(phrase), 30)
        self.assertNotIn("闭源形成的护城河", phrase)

    def test_hot_topics_sentence_empty_without_sources(self):
        self.assertEqual("", t._hot_topics_sentence(None))
        self.assertEqual("", t._hot_topics_sentence({"sources": []}))


if __name__ == "__main__":
    unittest.main()
