"""中文质量门槛：不接在线翻译，未中文化的条目安全暂缓，不损坏原始数据。"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
import generate as g


def news(title='苹果推出新产品', summary='苹果公布产品更新。'):
    return {'id': 'test', 'title': title, 'summary': summary, 'source': 'Example', 'url': 'https://example.com/1'}


class QualityGateTests(unittest.TestCase):
    def test_mixed_english_sentence_and_non_sentence_product_names(self):
        self.assertFalse(g.is_chinese_prose('最新进展：the company will expand in Europe。'))
        self.assertFalse(g.is_chinese_prose('产品消息：Apple releases open source model'))
        self.assertFalse(g.is_chinese_prose('行业动态：President Trump fires CDC chief'))
        self.assertFalse(g.is_chinese_prose('消息：company layoffs grow'))
        self.assertTrue(g.is_chinese_prose('Xbox Game Pass Ultimate 推出新游戏。'))
        self.assertTrue(g.is_chinese_prose('DeepSeek 完成新一轮融资。'))
        self.assertTrue(g.is_chinese_prose('英伟达发布 RTX 5090 显卡。'))

    def test_english_summary_never_triggers_an_ai_call(self):
        """用户明确要求不接智谱 / 在线翻译：英文摘要只能等待本地缓存或暂缓。"""
        item = news(summary='消息：The company will expand in Europe.')
        original = dict(item)
        with tempfile.TemporaryDirectory() as tmp, patch.object(g, 'CACHE_DIR', Path(tmp)), \
             patch.dict(os.environ, {'DIGEST_AI': '1'}), \
             patch.object(g, 'call_ai_json', return_value={'items': []}) as ai, \
             patch.object(g, 'call_opencode', return_value='') as cli:
            result = g.translate_to_chinese([item])
        self.assertEqual(ai.call_count, 0)
        self.assertEqual(cli.call_count, 0)
        self.assertEqual(result[0], original)

    def test_untranslated_item_is_dropped_not_published(self):
        item = news(summary='消息：The company will expand in Europe.')
        with tempfile.TemporaryDirectory() as tmp, patch.object(g, 'CACHE_DIR', Path(tmp)), \
             patch.object(g, 'call_ai_json', return_value=None) as ai:
            kept, dropped = g.drop_untranslated([{'id': 'wire', 'items': [item]}], try_translate=True)
        self.assertEqual(ai.call_count, 0)
        self.assertEqual(kept[0]['items'], [])
        self.assertEqual(len(dropped), 1)
        self.assertFalse((Path(tmp) / 'translation-cache.json').exists())

    def test_local_cache_hit_is_applied_offline(self):
        import hashlib
        item = news(title='A news update about products', summary='The company will expand in Europe.')
        key = hashlib.md5((item['title'] + '\x00' + item['source']).encode('utf-8')).hexdigest()
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp)
            (cache_dir / 'translation-cache.json').write_text(json.dumps({
                key: {'title': '苹果公布产品更新', 'summary': '该公司将在欧洲扩张。',
                      'input_summary': item['summary']}
            }, ensure_ascii=False), encoding='utf-8')
            with patch.object(g, 'CACHE_DIR', cache_dir), \
                 patch.object(g, 'call_ai_json', return_value=None) as ai:
                g.translate_to_chinese([item])
            self.assertEqual(ai.call_count, 0)
            self.assertEqual(item['title'], '苹果公布产品更新')
            self.assertEqual(item['summary'], '该公司将在欧洲扩张。')

    def test_changed_summary_does_not_get_stale_translation(self):
        import hashlib
        item = news(title='A news update about products', summary='The company will expand in Asia.')
        key = hashlib.md5((item['title'] + '\x00' + item['source']).encode('utf-8')).hexdigest()
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp)
            (cache_dir / 'translation-cache.json').write_text(json.dumps({
                key: {'title': '苹果公布产品更新', 'summary': '最初消息：将在欧洲扩张。',
                      'input_summary': 'The company will expand in Europe.'}
            }, ensure_ascii=False), encoding='utf-8')
            with patch.object(g, 'CACHE_DIR', cache_dir):
                g.translate_to_chinese([item])
            self.assertEqual(item['title'], 'A news update about products')
            self.assertIn('Asia', item['summary'])

    def test_optional_retry_masks_ancillary_fields_for_chinese_items(self):
        candidate = news(summary='该公司公布了新的产品更新。')
        candidate['takeaway'] = '观点：this update will launch next month.'
        original = dict(candidate)
        with tempfile.TemporaryDirectory() as tmp, patch.object(g, 'CACHE_DIR', Path(tmp)), \
             patch.object(g, 'call_ai_json', return_value=None) as ai:
            kept, dropped = g.drop_untranslated([{'id': 'wire', 'items': [candidate]}], try_translate=True)
        self.assertEqual(ai.call_count, 0)
        self.assertEqual(candidate, original)
        self.assertEqual(dropped, [])
        self.assertEqual(kept[0]['items'][0]['takeaway'], '相关解读暂待翻译。')


if __name__ == '__main__':
    unittest.main()
