"""离线回归：失败路径、当日缓存、证据引用与报告产物。不会读写用户数据。"""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
import generate as g

NOW = datetime(2026, 10, 28, 10, 0, tzinfo=timezone(timedelta(hours=8)))
TODAY = "2026-10-28"
POLICY = copy.deepcopy(next(c for c in g.CATEGORIES if c["id"] == "policy"))
AI = copy.deepcopy(next(c for c in g.CATEGORIES if c["id"] == "ai"))


def item(iid="one", title="团队发布开源开发工具", **kwargs):
    return {"id": iid, "title": title, "summary": title + "，已提供公开文档。",
            "source": "公开信源", "url": f"https://example.org/{iid}", "score": 30,
            "time": "1 小时前", "takeaway": "具体使用效果仍需验证。", "interpretation": "已知事实如上。", **kwargs}


def category(definition=AI, items=None):
    return {**{k: definition[k] for k in ("id", "name", "icon", "color")},
            "brief": "本期信息。", "items": items if items is not None else [item()]}


class PolicyTests(unittest.TestCase):
    def test_empty_source_keeps_disclaimer(self):
        result = g.enrich_category(POLICY, [])
        self.assertIn(g.POLICY_DISCLAIMER, result["brief"])
        self.assertEqual([], result["items"])

    def test_normalizes_cached_audience_and_brief(self):
        c = category(POLICY, [item(audience="银行与非银金融从业者")])
        result = g.normalize_category(POLICY, c)
        self.assertIn(g.POLICY_DISCLAIMER, result["brief"])
        self.assertEqual("投资者", result["items"][0]["audience"])
        self.assertEqual("普通人、创业者", g.normalize_audience("公众、企业负责人"))

    def test_date_does_not_leak_from_next_row(self):
        html = ('<li><a href="/first">第一份政策公告标题</a></li>'
                '<li><a href="/second">第二份政策公告标题</a><span>2026-10-28</span></li>')
        matches = list(g.HTML_ANCHOR_RE.finditer(html))
        self.assertEqual("", g.policy_date_tail(html, matches[0].end()))
        self.assertEqual("2026-10-28", g.policy_date_tail(html, matches[1].end()))
        source = {"name": "测试官方源", "url": "https://www.gov.cn/list/"}
        result = subprocess.CompletedProcess([], 0, stdout=html.encode(), stderr=b"")
        with patch.object(g.subprocess, "run", return_value=result), patch.object(g, "now_local", return_value=NOW):
            rows = g.fetch_html_list(source)
        self.assertEqual(["第二份政策公告标题"], [r["title"] for r in rows])

    def test_future_policy_rejected(self):
        raw = {"title": "明日政策公开通知", "description": "政策通知", "published": NOW + timedelta(days=1),
               "source": "政府网", "url": "https://www.gov.cn/future", "source_weight": 10}
        with patch.object(g, "now_local", return_value=NOW):
            self.assertEqual([], g.dedupe_and_filter([raw], "policy", 168))


class OpportunityTests(unittest.TestCase):
    def test_ai_off_still_has_actionable_opportunities(self):
        categories = [category(), category(POLICY, [item("p", "部门发布小企业试点政策")])]
        with patch.dict(os.environ, {"DIGEST_AI": "0"}):
            brief = g.build_brief(categories)
        self.assertTrue(1 <= len(brief["opportunities"]) <= 3)
        self.assertTrue(all(op["item_id"] in {"one", "p"} for op in brief["opportunities"]))
        self.assertTrue(all(op["why"] and op["how"] for op in brief["opportunities"]))
        self.assertNotIn("债市流动性", brief["summary"])

    def test_lawsuit_and_ipo_do_not_get_demo_instructions(self):
        pairs = [(AI, item("lawsuit", "AI 医疗模型误诊引发诉讼")),
                 (AI, item("ipo", "AI 公司拟 IPO 上市"))]
        ops = g.fallback_opportunities(pairs)
        self.assertEqual(2, len(ops))
        for op in ops:
            self.assertIn("待验证", op["title"])
            self.assertNotIn("试用", op["how"])
            self.assertNotIn("demo", op["how"].lower())
        self.assertIn("责任边界", ops[0]["how"])
        self.assertIn("招股书", ops[1]["how"])

    def test_capital_news_is_not_treated_as_tool_release(self):
        economy = {**AI, "id": "economy", "name": "经济"}
        headline = "公司启动算力融资，同时模型厂商发布新版产品"
        op = g.fallback_opportunities([(economy, item("funding", headline))])[0]
        self.assertNotIn("试用", op["how"])
        self.assertIn("企业披露", op["how"])

    def test_ai_unknown_references_are_rejected(self):
        cats = [category(items=[item("a"), item("b"), item("c")])]
        model = {"headline": "测试深读", "summary": "基于材料的导语。",
                 "deep_stories": [{"item_id": iid, "title": "可追溯标题", "lead": "可追溯正文"} for iid in ("a", "b", "c")],
                 "points": [{"item_id": "a", "text": "团队发布公开工具。"}, {"item_id": "unknown", "text": "虚构消息"}],
                 "opportunities": [{"item_id": "unknown", "why": "虚构机会", "how": "投资"}]}
        with patch.dict(os.environ, {"DIGEST_AI": "1"}), patch.object(g, "call_ai", return_value=json.dumps(model)):
            brief = g.build_brief(cats)
        self.assertEqual(["a"], [p["item_id"] for p in brief["points"]])
        self.assertTrue(brief["opportunities"])
        self.assertTrue(all(op["item_id"] in {"a", "b", "c"} for op in brief["opportunities"]))
        self.assertNotIn("虚构机会", json.dumps(brief, ensure_ascii=False))

    def test_same_count_changed_content_changes_fingerprint(self):
        old = [category()]
        new = copy.deepcopy(old)
        new[0]["items"][0]["summary"] = "同一个条目出现了新信息。"
        self.assertNotEqual(g.categories_fingerprint(old), g.categories_fingerprint(new))
        new = copy.deepcopy(old)
        new[0]["items"][0]["score"] = 999
        new[0]["items"][0]["time"] = "刚刚"
        self.assertEqual(g.categories_fingerprint(old), g.categories_fingerprint(new))

    def test_malformed_ai_arrays_degrade_instead_of_stopping_generation(self):
        cats = [category(items=[item("a"), item("b"), item("c")])]
        model = {"deep_stories": [{"item_id": iid, "sources": 7} for iid in ("a", "b", "c")],
                 "points": {"wrong": "shape"}, "opportunities": {"wrong": "shape"}}
        with patch.dict(os.environ, {"DIGEST_AI": "1"}), patch.object(g, "call_ai", return_value=json.dumps(model)):
            brief = g.build_brief(cats)
        self.assertTrue(brief["points"])
        self.assertTrue(brief["opportunities"])


class GenerationTests(unittest.TestCase):
    def run_main(self, previous=None, fail=False, fresh=None, rolling=True):
        with tempfile.TemporaryDirectory(prefix="digest-regressions-") as folder, ExitStack() as stack:
            root = Path(folder)
            for name in ("data", "reports", "cache", "logs", "exports"):
                (root / name).mkdir()
            if previous:
                (root / "data" / "latest.json").write_text(json.dumps(previous), encoding="utf-8")
                if previous["date"] == TODAY:
                    (root / "data" / f"{TODAY}.json").write_text(json.dumps(previous), encoding="utf-8")
            stack.enter_context(patch.multiple(g, DATA_DIR=root / "data", REPORT_DIR=root / "reports", CACHE_DIR=root / "cache",
                                               LOG_DIR=root / "logs", EXPORT_DIR=root / "exports", CATEGORIES=[AI, POLICY]))
            stack.enter_context(patch.object(g, "now_local", return_value=NOW))
            stack.enter_context(patch.dict(os.environ, {"DIGEST_AI": "0", "DIGEST_ONLY": "", "DIGEST_ROLLING": "1" if rolling else "0"}))
            fake_tts = types.SimpleNamespace(generate_from_digest=lambda *a, **k: {})
            stack.enter_context(patch.dict(sys.modules, {"tts_brief": fake_tts}))
            if fail:
                stack.enter_context(patch.object(g, "build_category", side_effect=RuntimeError("source unavailable")))
            else:
                def generate(definition, existing=None):
                    return category(definition, fresh if definition["id"] == "ai" else [])
                stack.enter_context(patch.object(g, "build_category", side_effect=generate))
            spy = stack.enter_context(patch.object(g, "build_brief", wraps=g.build_brief))
            self.assertEqual(0, g.main())
            data = json.loads((root / "data" / f"{TODAY}.json").read_text())
            reports = {p.name: p.read_text() for p in (root / "reports").glob("*.md")}
            return data, reports, spy.call_count

    def test_failed_sources_keep_policy_and_disclaimer(self):
        data, _, _ = self.run_main(fail=True)
        policy = next(c for c in data["categories"] if c["id"] == "policy")
        self.assertIn(g.POLICY_DISCLAIMER, policy["brief"])
        self.assertEqual([], policy["items"])

    def test_yesterday_latest_is_not_relabelled_today(self):
        old = {"date": "2026-10-27", "categories": [category(items=[item("yesterday", "昨日独有消息")])],
               "brief": {"summary": "昨日深读", "deep_stories": [{"title": "昨日深读"}]}, "topic": {"title": "昨日专题"}}
        data, _, _ = self.run_main(previous=old, fail=True)
        self.assertNotIn("昨日", json.dumps(data, ensure_ascii=False))
        self.assertEqual(TODAY, data["date"])

    def test_reports_and_missing_topic_are_restored(self):
        data, reports, _ = self.run_main(fresh=[item()])
        self.assertTrue(data["topic"]["item_ids"])
        self.assertIn(f"brief-{TODAY}.md", reports)
        self.assertIn(f"{TODAY}.md", reports)
        self.assertIn("机会信号", reports[f"brief-{TODAY}.md"])
        self.assertIn("今日专题", reports[f"{TODAY}.md"])

    def test_unchanged_rolling_preserves_high_quality_brief(self):
        cats = [category(AI, [item()]), category(POLICY, [])]
        previous = {"date": TODAY, "categories": cats,
                    "brief": {"headline": "保留高质量标题", "summary": "当日深度导语", "deep_stories": [{"title": "深读"}], "opportunities": []}}
        data, _, calls = self.run_main(previous=previous, fresh=[item()])
        self.assertEqual(0, calls)
        self.assertEqual("保留高质量标题", data["brief"]["headline"])
        self.assertTrue(data["brief"]["opportunities"])

    def test_same_count_update_rebuilds_brief(self):
        old = item()
        cats = [category(AI, [old]), category(POLICY, [])]
        previous = {"date": TODAY, "categories": cats,
                    "brief": {"summary": "旧导语", "deep_stories": [{"title": "旧深读"}]}}
        fresh = item(summary="条目正文已更新。")
        data, _, calls = self.run_main(previous=previous, fresh=[fresh])
        self.assertEqual(1, calls)
        self.assertIn("条目正文已更新", data["brief"]["summary"])


if __name__ == "__main__":
    unittest.main()
