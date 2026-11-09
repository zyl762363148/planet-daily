"""抓取、真实日期、误删和同日滚动保留的离线回归。"""
import sys,json,unittest,copy,subprocess
from pathlib import Path
from datetime import datetime,timedelta,timezone
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
import generate as g,source_pages as pages
NOW=datetime(2026,11,6,1,tzinfo=timezone(timedelta(hours=8)))
SOURCE={'name':'测试中文源','url':'https://example.org/feed','weight':10}
RSS=b'''<rss><channel><item><title>Chinese</title><link>https://example.org/1</link><pubDate>Thu, 05 Nov 2026 12:00:00 GMT</pubDate></item></channel></rss>'''
class SourceTests(unittest.TestCase):
 def setUp(self):g._PAYLOAD_CACHE.clear();g._FETCH_INFO.clear();g._SOURCE_STATUS.clear();g._CATEGORY_FETCH_STATUS.clear()
 def test_rdf_namespace_fields_are_not_lost(self):
  raw='''<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"><item><title>德国公布新的产业政策</title><link>https://example.org/1</link><description>政府公布具体安排。</description><dc:date>2026-11-05T12:00:00Z</dc:date></item></rdf:RDF>'''.encode()
  with patch.object(g,'_source_payload',return_value=(raw,[])):
   rows=g.fetch_feed(SOURCE)
  self.assertEqual(1,len(rows));self.assertEqual('德国公布新的产业政策',rows[0]['title']);self.assertEqual('https://example.org/1',rows[0]['url'])
  self.assertEqual(20,rows[0]['published'].astimezone(NOW.tzinfo).hour)
 def test_atom_prefers_article_alternate_link(self):
  raw='''<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>某机构公布研究成果</title><link rel="self" href="https://example.org/api/1"/><link rel="alternate" href="https://example.org/article/1"/><updated>2026-11-05T12:00:00Z</updated></entry></feed>'''.encode()
  with patch.object(g,'_source_payload',return_value=(raw,[])):rows=g.fetch_feed(SOURCE)
  self.assertEqual('https://example.org/article/1',rows[0]['url'])
 def test_feed_reads_beyond_first_thirty(self):
  raw=('<rss><channel>'+''.join(f'<item><title>新闻事件第{i}条</title><link>https://example.org/{i}</link><pubDate>Thu, 05 Nov 2026 12:00:00 GMT</pubDate></item>' for i in range(60))+'</channel></rss>').encode()
  with patch.object(g,'_source_payload',return_value=(raw,[])):rows=g.fetch_feed(SOURCE)
  self.assertEqual(60,len(rows))
 def test_http_failure_and_html_are_not_counted_as_success(self):
  bad=subprocess.CompletedProcess([],0,b'<html>not found</html>\n__DAILYDIGEST_HTTP__404',b'')
  with patch.object(g.subprocess,'run',return_value=bad),patch.object(g,'resolve_proxy',return_value=''):
   rows=g.fetch_feed(SOURCE)
  self.assertEqual([],rows);self.assertNotEqual('ok',g._SOURCE_STATUS[SOURCE['url']]['status'])
 def test_shared_source_is_downloaded_once_per_run(self):
  result=subprocess.CompletedProcess([],0,RSS+b'\n__DAILYDIGEST_HTTP__200',b'')
  with patch.object(g.subprocess,'run',return_value=result) as run:
   g._curl_feed(SOURCE['url'],SOURCE,'direct');g._curl_feed(SOURCE['url'],SOURCE,'direct')
  self.assertEqual(1,run.call_count)
 def test_normal_news_is_not_censored_as_promotion(self):
  for title in ('美国一邮局发生枪击事件，多人受伤','企业公布广告业务收入增长','某部门发布促进就业的新政策'):
   self.assertFalse(g.is_negative(title,'广告推广相关报道'))
  self.assertTrue(g.is_negative('【广告】购买指定产品赠送礼品',''))
 def test_future_news_rejected_for_all_sections(self):
  row={'title':'未来发布的新闻事件','description':'尚未发布','url':'u','source':'s','published':NOW+timedelta(days=1)}
  with patch.object(g,'now_local',return_value=NOW):self.assertEqual([],g.dedupe_and_filter([row],'ai',48))
 def test_yicai_uses_real_full_date_not_yesterday_label(self):
  row={'NewsTitle':'某公司公布季度财报','NewsNotes':'营收已公开。','url':'/news/12345678.html','CreateDate':'2026-11-05T21:48:36','pubDate':'昨天 21:48'}
  items=pages.yicai(('var firstlist = '+json.dumps([row],ensure_ascii=False)+';').encode())
  self.assertEqual(1,len(items));self.assertEqual('2026-11-05T21:48:36+08:00',items[0]['published'].isoformat())
  row.pop('CreateDate');self.assertEqual([],pages.yicai(('var firstlist = '+json.dumps([row])+';').encode()))
 def test_javascript_is_not_executed_and_non_article_urls_excluded(self):
  row={'NewsTitle':'市场行业专题','url':'https://evil.example/news/1.html','CreateDate':'2026-11-05T10:00:00'}
  self.assertEqual([],pages.yicai(('var firstlist = '+json.dumps([row])+'; malicious();').encode()))
  self.assertEqual([],pages.yicai(b'var firstlist = fetch("/api");'))
 def test_list_time_belongs_to_same_article(self):
  epoch=int(NOW.timestamp())
  raw=f'<div data-time="{epoch}"><h4><a href="/article/123.html">公司公布产品更新</a></h4><div class="summary">公开了产品细节。</div></div><div><a href="/article/124.html">这一条没有日期</a></div>'.encode()
  rows=pages.jiemian(raw);self.assertEqual(1,len(rows));self.assertEqual(NOW,rows[0]['published']);self.assertIn('123.html',rows[0]['url'])

 def test_proxy_selection_does_not_depend_on_one_news_domain(self):
  import os
  with patch.object(g,'_PROXY_CACHE',None),patch.dict(os.environ,{'DIGEST_PROXY':'http://127.0.0.1:7890'}),patch.object(g,'_proxy_alive',return_value=True),patch.object(g.subprocess,'run') as curl:
   self.assertEqual('http://127.0.0.1:7890',g.resolve_proxy());self.assertEqual(0,curl.call_count)
 def test_bad_feed_does_not_discard_good_feed(self):
  category={'id':'wire','kind':'feeds','feeds':[{'name':'正常来源','url':'https://example.org/good'},{'name':'异常来源','url':'https://example.org/bad'}]}
  def fetch(source):
   if source['name']=='异常来源':raise ValueError('malformed')
   return [{'title':'已核实的重要消息'}]
  with patch.object(g,'fetch_feed',side_effect=fetch):rows=g.fetch_category_raw(category)
  self.assertEqual(1,len(rows));self.assertEqual('source_exception',g._SOURCE_STATUS['https://example.org/bad']['status'])
 def test_professional_section_rejects_unrelated_general_news(self):
  rows=[{'title':'新手机发售','description':'数码产品更新'},{'title':'某公司发布人工智能模型','description':'公开了评测结果'}]
  self.assertEqual(1,len(g.source_relevant(rows,'ai',{'name':'综合新闻'})))
  self.assertEqual([],g.source_relevant(rows,'health',{'name':'中新网社会'}))


 def test_economy_does_not_take_unrelated_social_flash(self):
  rows=[{'title':'美国一邮局发生枪击事件，多人受伤','description':'警方已逮捕嫌疑人。'}, {'title':'现货白银日内跌幅扩大','description':'市场公布最新交易价格。'}]
  result=g.source_relevant(rows,'economy',{'name':'界面新闻'})
  self.assertEqual(1,len(result));self.assertIn('白银',result[0]['title'])

 def test_published_summary_is_used_when_checking_existing_news(self):
  row={'title':'区域合作行动计划发布','summary':'亚太经合组织经济体共同参与。'}
  self.assertEqual([row],g.source_relevant([row],'economy',{'name':'中新网国内'}))

class RollingTests(unittest.TestCase):
 def test_daily_items_survive_later_updates(self):
  category=copy.deepcopy(next(c for c in g.CATEGORIES if c['id']=='ai'))
  old=[{'id':f'old-{i}','title':f'当天早些时候新闻{i}','url':f'https://example.org/old/{i}','summary':'已发布内容。','source':'中文媒体'} for i in range(30)]
  raw=[{'title':f'新模型发布新闻{i}','url':f'https://example.org/new/{i}','description':'研发机构公布产品细节。','published':NOW-timedelta(hours=1),'source':f'来源{i%3}','source_weight':10} for i in range(12)]
  with patch.object(g,'now_local',return_value=NOW),patch.object(g,'fetch_category_raw',return_value=raw),patch.object(g,'collection_limits',return_value=(12,60)),patch.object(g,'USE_ONLINE_AI',False):
   result=g.build_category(category,{'items':old,'brief':'当日内容'})
  self.assertEqual(42,len(result['items']));self.assertTrue(all(i['id'] in {r['id'] for r in result['items']} for i in old))
 def test_source_outage_preserves_same_day_items_with_failure_status(self):
  cat=copy.deepcopy(g.CATEGORIES[0]);old={'id':'one','title':'当天已发布的重要新闻','url':'https://example.org/old','summary':'已核实事实。','source':'中文媒体'}
  with patch.object(g,'fetch_category_raw',return_value=[]),patch.object(g,'USE_ONLINE_AI',False):r=g.build_category(cat,{'items':[old],'brief':'旧摘要'})
  self.assertEqual([old],r['items']);self.assertEqual(0,r['coverage']['available']);self.assertIn('保留当天',r['brief'])
if __name__=='__main__':unittest.main()
