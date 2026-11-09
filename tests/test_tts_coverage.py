"""十段本地文稿覆盖回归；离线，不调用 AI、天气网络或语音服务。"""
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "tts_coverage_under_test", Path(__file__).resolve().parents[1] / "backend" / "tts_brief.py"
)
tts = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tts)
TITLES = ["开场", "头条简报", "今日热点", "环球瞭望", "政策风向",
          "财经与科技", "生活与健康", "一周回顾", "机会信号", "收尾"]


def formatted_script(chapters):
    return "\n\n".join(f"【{index:02d} {chapter['title']}】\n{chapter['text']}"
                       for index, chapter in enumerate(chapters, 1)) + "\n"


class TTSCoverageTests(unittest.TestCase):
    def build(self, digest, date="2026-10-28"):
        with mock.patch.object(tts, "fetch_weather_sentence", return_value="天气数据暂不可用，请留意当地预报。"), mock.patch.object(
            tts, "load_weekly_highlights", return_value=["10月26日，某企业发布了新的模型评测结果，研究者正在复核数据。"]
        ):
            return tts.build_ten_chapters(date, digest)

    def test_all_referenced_items_survive_long_chapters(self):
        categories = []
        labels = {"wire":"国际", "policy":"政策", "economy":"经济", "ai":"人工智能", "infogap":"信息差", "opensource":"开源", "media":"新媒体", "health":"健康", "design":"设计"}
        for cid in ("wire", "policy", "economy", "ai", "infogap", "opensource", "media", "health", "design"):
            categories.append({"id": cid, "name": labels[cid], "items": [
                {"id": f"{cid}-{i}", "title": f"{labels[cid]}独特事件{i}发布新规则，参与者正在核实适用范围。",
                 "summary": f"{labels[cid]}背景{i}已经公开，详情保留在日报原文中。",
                 "takeaway": f"{labels[cid]}看点{i}值得跟进。", "score": 10-i, "audience": "创业者"}
                for i in range(3)
            ]})
        digest = {"categories": categories, "brief": {
            # 常态虽然是5至8条，已有10条时也不能静默丢掉最后两条。
            "points": [{"text": f"【独特简报事件{i}】企业发布了完整公告，公布了对应的办理条件。"} for i in range(10)],
            "deep_stories": [{"title": f"独特热点事件{i}正式发布。", "lead": f"独特背景{i}解释了这次调整的原因。"} for i in range(5)],
            "opportunities": [{"title": f"机会{i}", "why": f"独特机会原因{i}正在形成新的需求。",
                               "how": f"独特跟进行动{i}先核实原文，再用小样本测试，最后复核成本与适用条件。"} for i in range(3)]}}
        chapters = self.build(digest)
        self.assertEqual([chapter["title"] for chapter in chapters], TITLES)
        self.assertEqual(chapters[1]["text"].count("独特简报事件"), 10)
        for i in range(5):
            self.assertIn(f"独特热点事件{i}", chapters[2]["text"])
            self.assertIn(f"独特背景{i}", chapters[2]["text"])
        for i in range(3):
            self.assertIn(f"国际独特事件{i}", chapters[3]["text"])
            self.assertIn(f"政策独特事件{i}", chapters[4]["text"])
        self.assertEqual(chapters[4]["text"].count("这与创业者有关"), 3)
        self.assertIn("仅为信息梳理，不构成官方解读", chapters[4]["text"])
        for cid in ("economy", "ai", "infogap", "opensource"):
            for i in range(2):
                self.assertIn(tts._spoken_material(f"{labels[cid]}独特事件{i}"), chapters[5]["text"])
        for cid in ("media", "health", "design"):
            self.assertIn(f"{labels[cid]}独特事件0", chapters[6]["text"])
        for opportunity in digest["brief"]["opportunities"]:
            self.assertIn(tts._spoken_material(opportunity["why"]), chapters[8]["text"])
            self.assertIn(tts._spoken_material(opportunity["how"]), chapters[8]["text"])
        self.assertNotRegex(formatted_script(chapters), r"第\d+(?:条|个)")

    def test_conditional_and_introductory_clauses_keep_their_action(self):
        for text, required in (
            ("结合模型能力与已有客户反馈，针对海外商户搭建预约工作流。", "搭建预约工作流"),
            ("出海企业在推进海外并购前，需核查最新备案要求，并复核适用条件。", "需核查最新备案要求"),
            ("10月26日，企业公布了完整的评测结果和适用范围。", "公布了完整"),
            ("事业单位登记从部门层面的操作事项，转为由行政法规设定规则。", "转为由行政法规设定规则"),
            ("贷款投向报告把总量宽松拆成各部门的贷款结构，信贷究竟流向居民、企业还是特定领域，决定了宽松能否转化为实体需求。", "决定了宽松能否转化为实体需求"),
            ("推理栈与权重捆绑会否形成新的供应商锁定；训练数据转向私下并购后，用户授权范围由谁举证。", "用户授权范围由谁举证"),
        ):
            with self.subTest(text=text):
                self.assertIn(required, tts.clip_chapter_text(text, 45 if "究竟" in text or "训练数据" in text else 20))

    def test_upstream_ellipsis_never_becomes_a_complete_claim(self):
        self.assertEqual(tts.clip_chapter_text("第一项结果已经公布。另一项仍在临床验证结…", 100), "第一项结果已经公布。")
        self.assertEqual(tts.clip_chapter_text("仍在临床验证结…", 100), "")

    def test_fallback_opportunity_recovers_original_summary_and_keeps_how(self):
        summary = "研究团队公布了完整报告，临床验证结果仍待独立复核。"
        how = "先核对完整报告与验证方法，再确认适用范围。"
        digest = {"categories": [{"id": "health", "items": [
            {"id": "clinical", "title": "研究团队公布验证报告", "summary": summary, "score": 1}]}],
            "brief": {"opportunities": [{"item_id": "clinical", "title": "验证线索",
                "why": "研究团队公布了完整报告，临床验证结。这是一条待验证的需求线索，尚不能据此判断收益。", "how": how}]}}
        chapters = self.build(digest)
        self.assertIn(summary, chapters[8]["text"])
        self.assertIn(how, chapters[8]["text"])
        self.assertNotIn("临床验证结。", chapters[8]["text"])
        self.assertNotIn("尚不能据此判断收益", chapters[8]["text"])

    def test_headline_subject_and_chinese_adjacent_english_names_are_kept(self):
        spoken = tts._spoken_material("【Google发布Gemini 4 Carbon】OpenAI与ServiceNow接入Codex，DeepSeek开源DeepInfer推理框架。")
        self.assertIn("谷歌发布双子座四代碳模型。", spoken)
        self.assertIn("开放人工智能公司与企业服务平台接入编程助手", spoken)
        self.assertNotRegex(spoken, r"Google|Gemini|OpenAI|ServiceNow|Codex|DeepSeek|DeepInfer|框架推理框架")

    def test_normalization_never_removes_last_item_or_how(self):
        text = "项目一已经公布。" * 400 + "最后一个项目仍保留。怎么跟进？完整行动建议仍保留。"
        result = tts.normalize_chapters([{"title": "测试", "text": text}], {})
        self.assertIn("最后一个项目仍保留", result[0]["text"])
        self.assertIn("完整行动建议仍保留", result[0]["text"])

    def test_sparse_material_stays_honestly_short_and_has_ten_sections(self):
        chapters = self.build({"categories": [], "brief": {}})
        self.assertEqual(len(chapters), 10)
        self.assertTrue(all(chapter["text"] for chapter in chapters))
        self.assertLess(sum(len(chapter["text"]) for chapter in chapters), 2200)
        self.assertIn("暂未取得可核实", chapters[3]["text"])
        self.assertIn("还没有足够证据", chapters[8]["text"])

    def test_monday_reads_previous_week_and_other_days_read_current_week(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for date, label in (("2026-10-25", "上周事件"), ("2026-10-26", "周一事件"), ("2026-10-27", "周二事件")):
                (root / f"{date}.json").write_text(json.dumps({"brief": {"points": [{"text": label + "已经完成。"}]}}, ensure_ascii=False))
            with mock.patch.object(tts, "DATA_DIR", root):
                monday = "".join(tts.load_weekly_highlights("2026-10-26"))
                tuesday = "".join(tts.load_weekly_highlights("2026-10-27"))
            self.assertIn("上周事件", monday)
            self.assertNotIn("周一事件", monday)
            self.assertNotIn("上周事件", tuesday)
            self.assertIn("周一事件", tuesday)
            self.assertIn("周二事件", tuesday)
        monday_chapters = self.build({"topic": {"points": ["今天的专题不能充当上周回顾。"]}}, "2026-10-26")
        self.assertIn("上一完整周", monday_chapters[7]["text"])
        self.assertNotIn("今天的专题", monday_chapters[7]["text"])

    def test_real_handover_material_is_not_mutated(self):
        data_dir = Path("/tmp/DailyDigestData/data")
        paths = [data_dir / f"{date}.json" for date in ("2026-10-28", "2026-10-29")]
        if not all(path.is_file() for path in paths):
            self.skipTest("交接实数样本不在此机器")
        for path in paths:
            with self.subTest(date=path.stem):
                digest = json.loads(path.read_text())
                before = json.dumps(digest, ensure_ascii=False, sort_keys=True)
                with mock.patch.object(tts, "DATA_DIR", data_dir), mock.patch.object(
                    tts, "fetch_weather_sentence", return_value="天气数据暂不可用，请留意当地预报。"
                ):
                    chapters = tts.build_ten_chapters(path.stem, digest)
                self.assertEqual(json.dumps(digest, ensure_ascii=False, sort_keys=True), before)
                self.assertEqual([chapter["title"] for chapter in chapters], TITLES)
                self.assertTrue(all(chapter["text"] for chapter in chapters))
                self.assertNotRegex("".join(chapter["text"] for chapter in chapters), r"https?://|[A-Za-z]")
                self.assertIn("今天的行星日报已经为您播放完毕", chapters[-1]["text"])


if __name__ == "__main__":
    unittest.main()
