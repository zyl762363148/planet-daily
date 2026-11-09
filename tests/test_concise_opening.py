import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
import generate
import tts_brief as tts

class ConciseOpeningTests(unittest.TestCase):
    def test_headlines_keep_all_titles_without_repeating_the_summaries(self):
        points = [{'text': f'第{i}则消息发布——这里是第{i}则消息发布后的重复长摘要。'} for i in range(1, 11)]
        digest = {'brief': {'points': points}, 'categories': []}
        with patch.object(tts, 'fetch_weather_sentence', return_value='北京晴。'), patch.object(tts, 'load_weekly_highlights', return_value=[]):
            chapters = tts.build_ten_chapters('2026-10-29', digest)
        self.assertIn('北京晴', chapters[0]['text'])
        self.assertLessEqual(len(chapters[0]['text']), 50)
        self.assertNotIn('接下来', chapters[0]['text'])
        for i in range(1, 11):
            self.assertEqual(chapters[1]['text'].count(f'第{i}则消息发布'), 1)
        self.assertNotIn('重复长摘要', chapters[1]['text'])

    def test_intro_keeps_complete_sentences_and_never_cuts_mid_sentence(self):
        self.assertEqual(generate.concise_brief_intro('第一句。第二句。第三句。'), '第一句。第二句。')
        self.assertEqual(generate.concise_brief_intro('长' * 130 + '。'), '以下是今日重点与值得跟进的线索。')
        self.assertNotIn('…', generate.concise_brief_intro('一条被截断的内容…。'))

if __name__ == '__main__':
    unittest.main()
