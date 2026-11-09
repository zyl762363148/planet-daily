"""综合语音：海外来源、各已启用栏目、正文去重与可读条目补足。纯离线。"""
import copy,json,re,sys,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
import generate as g,tts_brief as t,modules_config as m
IDS=['wire','global','policy','economy','ai','infogap','opensource','games','sport','life','health']
def fixture():
 cats=[]
 for cid in IDS:
  name=m.module_meta(cid)['name']
  items=[{'id':f'{cid}-{i}','url':f'https://example.org/{cid}/{i}','title':f'{name}独特事件{i}公布新的进展','summary':f'{name}公开了办理条件和具体数据，相关安排已经确认。','source':f'中文来源{i%3}','score':100-i if cid=='wire' else 70-i} for i in range(10)]
  if cid=='global':
   for i,item in enumerate(items):item['source']=['英国广播公司中文','德国之声中文','法广华语'][i%3]
  cats.append({'id':cid,'name':name,'items':items})
 return {'categories':cats,'brief':{'points':[{'text':'今天有多项国内外新闻。'}]}}
class GlobalBroadcastTests(unittest.TestCase):
 def build(self,data=None,ids=None,enabled=None):
  cfg=copy.deepcopy(m.DEFAULT_CONFIG);cfg['modules']['enabled']=enabled or IDS
  cfg['broadcast']['modules']=ids or IDS;cfg['broadcast']['max_items_per_module']=3
  with patch.object(m,'load_config',return_value=cfg),patch.object(t,'fetch_weather_sentence',return_value='杭州富阳今天多云，最高十九度。'):
   return t.build_focused_chapters('2026-11-06',data or fixture())
 def test_all_eleven_enabled_sections_have_real_spoken_news(self):
  ch=self.build();modules=[c for c in ch if c.get('module_id')]
  self.assertEqual(IDS,[c['module_id'] for c in modules]);self.assertTrue(all(len(c['item_ids'])==3 for c in modules))
  self.assertIn('海外新闻',[c['title'] for c in ch]);self.assertEqual('收尾',ch[-1]['title'])
  self.assertIn('祝您生活愉快，咱们明天再见',ch[-1]['text'])
 def test_bbc_has_a_clear_name_and_real_overseas_voice_attribution(self):
  self.assertEqual('英国广播公司中文',m.chinese_source('BBC中文'))
  global_feed=next(c for c in g.CATEGORIES if c['id']=='global')['feeds']
  self.assertTrue(any(s['url']=='https://feeds.bbci.co.uk/zhongwen/simp/rss.xml' for s in global_feed))
  overseas=next(c for c in self.build() if c['title']=='海外新闻')
  self.assertIn('英国广播公司中文报道',overseas['text']);self.assertEqual(3,len(set(overseas['sources'])))
 def test_unreadable_top_items_do_not_leave_section_short(self):
  data=fixture();ai=next(c for c in data['categories'] if c['id']=='ai')
  for item in ai['items'][:3]:item['title']='公司发布 UnknownLongProductName 产品'
  ch=self.build(data);section=next(c for c in ch if c.get('module_id')=='ai')
  self.assertEqual(3,len(section['item_ids']));self.assertTrue(all(i not in section['item_ids'] for i in ('ai-0','ai-1','ai-2')))
 def test_same_article_not_repeated_across_background_and_modules(self):
  data=fixture();wire=data['categories'][0]['items'];global_items=data['categories'][1]['items']
  global_items[0]=copy.deepcopy(wire[0]);global_items[0]['source']='英国广播公司中文'
  ch=self.build(data);ids=[i for c in ch for i in c.get('item_ids',[])]
  self.assertEqual(len(ids),len(set(ids)))
 def test_closed_section_is_not_spoken_even_if_old_json_still_has_it(self):
  ch=self.build(enabled=[i for i in IDS if i!='health'])
  self.assertNotIn('health',[c.get('module_id') for c in ch]);self.assertNotIn('健康生活独特事件',''.join(c['text'] for c in ch))
 def test_english_prose_and_urls_are_not_read(self):
  data=fixture();item=data['categories'][0]['items'][0];item['summary']='这是一条已经确认的新闻。https://example.com/read 链接见日报。'
  script=''.join(c['text'] for c in self.build(data))
  self.assertNotRegex(script,r'[A-Za-z]|https?://')
 def test_bbc_historical_display_label_is_normalized(self):
  cat=next(c for c in g.CATEGORIES if c['id']=='wire')
  row={'brief':'旧内容','items':[{'source':'英国广播公司','url':'https://www.bbc.com/zhongwen/articles/test/trad'}]}
  self.assertEqual('英国广播公司中文',g.normalize_category(cat,row)['items'][0]['source'])
if __name__=='__main__':unittest.main()
