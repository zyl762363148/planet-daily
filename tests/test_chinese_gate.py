"""全中文硬门槛与永久译文缓存的离线回归（零在线 AI 契约）。"""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
import generate as g


def cat(name, items):
    return {"id": "wire", "name": name, "items": items}


def item(title, summary):
    return {"id": title[:6], "title": title, "summary": summary, "url": "u", "source": "s"}


class GateTests(unittest.TestCase):
    def test_drops_items_without_chinese(self):
        categories = [cat("环球通讯社", [
            item("央行宣布新工具", "央行发布公告，明确实施细节。"),
            item("FedEx Freight delivers a much-needed beat", "Shares have struggled since June."),
        ])]
        kept, dropped = g.drop_untranslated(categories)
        self.assertEqual(len(kept[0]["items"]), 1)
        self.assertEqual(kept[0]["items"][0]["title"], "央行宣布新工具")
        self.assertEqual(len(dropped), 1)
        self.assertIn("FedEx", dropped[0][1])

    def test_drops_chinese_title_with_english_summary(self):
        categories = [cat("环球通讯社", [
            item("某公司发布新产品", "The company said it will expand in Europe."),
        ])]
        kept, dropped = g.drop_untranslated(categories)
        self.assertEqual(kept[0]["items"], [])
        self.assertEqual(len(dropped), 1)

    def test_english_with_proper_noun_kept(self):
        categories = [cat("人工智能", [
            item("DeepSeek 千亿融资曝光：估值达 6155 亿元", "DeepSeek 完成新一轮融资，估值 6155 亿元。"),
        ])]
        kept, _ = g.drop_untranslated(categories)
        self.assertEqual(len(kept[0]["items"]), 1)

    def test_ancillary_english_sentence_is_masked(self):
        entry = item("某公司发布新产品", "该公司公布了新的产品更新。")
        entry["takeaway"] = "观点：this update will launch next month."
        kept, _ = g.drop_untranslated([cat("信息差", [entry])])
        self.assertEqual(kept[0]["items"][0]["takeaway"], "相关解读暂待翻译。")


class PersistentCacheTests(unittest.TestCase):
    """翻译只复用本机永久缓存，永远不发起网络调用。"""

    def _write_cache(self, cache_dir, title, source, summary, chinese_title, chinese_summary):
        key = hashlib.md5((title + "\x00" + source).encode("utf-8")).hexdigest()
        (cache_dir / "translation-cache.json").write_text(json.dumps({
            key: {"title": chinese_title, "summary": chinese_summary, "input_summary": summary}
        }, ensure_ascii=False), encoding="utf-8")
        return key

    def test_cache_hit_translates_without_any_ai_call(self):
        title = "FedEx Freight delivers a much-needed quarterly beat"
        summary = "Shares have struggled since their June debut."
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp)
            self._write_cache(cache_dir, title, "CNBC", summary,
                              "联邦快递货运业务超预期", "股价自六月上市以来表现挣扎。")
            items = [{"id": "x", "title": title, "summary": summary, "source": "CNBC"}]
            with patch.object(g, "CACHE_DIR", cache_dir), \
                 patch.object(g, "call_ai_json", return_value=None) as ai, \
                 patch.object(g, "call_opencode", return_value="") as cli:
                g.translate_to_chinese(items)
            self.assertEqual(ai.call_count, 0)
            self.assertEqual(cli.call_count, 0)
            self.assertEqual(items[0]["title"], "联邦快递货运业务超预期")
            self.assertEqual(items[0]["summary"], "股价自六月上市以来表现挣扎。")

    def test_stale_cache_is_not_applied(self):
        title = "A news update about products"
        summary = "The company will expand in Asia."
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp)
            self._write_cache(cache_dir, title, "Example", "The company will expand in Europe.",
                              "苹果公布产品更新", "最初消息：将在欧洲扩张。")
            items = [{"id": "x", "title": title, "summary": summary, "source": "Example"}]
            with patch.object(g, "CACHE_DIR", cache_dir), \
                 patch.object(g, "call_ai_json", return_value=None) as ai:
                g.translate_to_chinese(items)
            self.assertEqual(ai.call_count, 0)
            self.assertEqual(items[0]["title"], title)

    def test_uncached_english_item_is_held_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            items = [{"id": "x", "title": "English only title",
                      "summary": "English summary.", "source": "s"}]
            with patch.object(g, "CACHE_DIR", Path(tmp)), \
                 patch.object(g, "call_ai_json", return_value=None) as ai:
                g.translate_to_chinese(items)
                kept, dropped = g.drop_untranslated([cat("环球通讯社", items)], try_translate=True)
            self.assertEqual(ai.call_count, 0)
            self.assertEqual(items[0]["title"], "English only title")
            self.assertEqual(kept[0]["items"], [])
            self.assertEqual(len(dropped), 1)


class NoOnlineAITests(unittest.TestCase):
    def test_call_ai_is_disabled_by_default(self):
        with patch.object(g, "USE_ONLINE_AI", False), \
             patch.object(g, "call_opencode", return_value="不该被调用") as cli:
            self.assertEqual(g.call_ai("任意提示词"), "")
            self.assertEqual(cli.call_count, 0)

    def test_all_registered_feeds_are_chinese_sources(self):
        for group, sources in g.FEEDS.items():
            for source in sources:
                self.assertTrue(g.contains_cjk(source["name"]),
                                f"{group} 里仍有英文源名：{source['name']}")

    def test_no_promotion_categories(self):
        self.assertNotIn("tokens", [c["id"] for c in g.CATEGORIES])
        self.assertNotIn("deals", [c["id"] for c in g.CATEGORIES])


if __name__ == "__main__":
    unittest.main()
