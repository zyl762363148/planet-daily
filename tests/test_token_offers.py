import io,json,sys,unittest
from datetime import datetime,timedelta
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
import token_offers as t
NOW=datetime(2026,11,4,16,tzinfo=t.BEIJING)
QINIU='''Conatus 活动进行中 2026 年 10 月 24 日 00:00 至 2026 年 11 月 30 日 23:59
已认证 每日 1 亿 Token 实名认证 每日 00:00 重置 未使用额度不结转 不支持超额按量计费'''
WEEK='''<article>作者：AutoClaw Team 2026年10月31日
活动时间 11 月 2 日（周一）00:00—11 月 8 日（周日）23:59（北京时间）
活动规则：登录 AutoClaw，即可领取 50M Tokens（相当于 5,000 积分），每个账号限领一次。
奖励将在 11 月 8 日 23:59 失效</article>'''
class Response(io.BytesIO):
    def __init__(self,raw,url):super().__init__(raw.encode());self.url=url
    def geturl(self):return self.url
class ActivityTests(unittest.TestCase):
    def test_only_actual_current_promotions(self):
        self.assertEqual('daily_event',t.parse_source('qiniu',QINIU,NOW)[0]['promotion']['kind'])
        self.assertEqual('limited_grant',t.parse_source('autoclaw_cn',WEEK,NOW)[0]['promotion']['kind'])
        for key in ('bailian','copilot','cloudflare','silicon','openrouter'):
            self.assertEqual([],t.parse_source(key,'新人免费额度 每天免费 调用零价格',NOW))
    def test_start_end_boundaries_beijing(self):
        self.assertFalse(t.parse_source('autoclaw_cn',WEEK,datetime(2026,11,1,23,59,tzinfo=t.BEIJING)))
        self.assertTrue(t.parse_source('autoclaw_cn',WEEK,datetime(2026,11,2,0,0,tzinfo=t.BEIJING)))
        self.assertTrue(t.parse_source('autoclaw_cn',WEEK,datetime(2026,11,8,23,59,59,tzinfo=t.BEIJING)))
        self.assertFalse(t.parse_source('autoclaw_cn',WEEK,datetime(2026,11,9,0,0,tzinfo=t.BEIJING)))
        self.assertFalse(t.parse_source('qiniu',QINIU,datetime(2026,12,1,tzinfo=t.BEIJING)))
    def test_no_claim_without_complete_rules(self):
        for text in (WEEK + '本期活动已结束',WEEK.replace('每个账号限领一次',''),WEEK.replace('11 月 8 日 23:59 失效','11 月 7 日 23:59 失效'),WEEK.replace('登录 AutoClaw','仅限新用户首次注册 AutoClaw')):
            self.assertEqual([],t.parse_source('autoclaw_cn',text,NOW))
        self.assertEqual([],t.parse_source('qiniu',QINIU.replace('活动进行中','活动已结束'),NOW))
    def test_daily_reset_is_not_repeated_weekly_claim(self):
        a=t.parse_source('autoclaw_cn',WEEK,NOW)[0]
        self.assertIn('每个账号限一次',a['summary']);self.assertEqual('limited_grant',a['promotion']['kind'])
        self.assertIn('领取与使用同时截止',a['takeaway'])
        b=t.parse_source('qiniu',QINIU,NOW)[0]
        self.assertIn('这一亿档不要求充值',b['interpretation'])
        self.assertNotIn('十亿',b['title'])
    def test_stale_legacy_and_future_verification_rejected(self):
        i=t.parse_source('qiniu',QINIU,NOW)[0]
        self.assertTrue(t.is_current(i,NOW+timedelta(hours=23)))
        self.assertFalse(t.is_current(i,NOW+timedelta(hours=25)))
        self.assertFalse(t.is_current(i,NOW-timedelta(seconds=1)))
        self.assertFalse(t.is_current({'title':'旧版免费套餐'},NOW))
        self.assertEqual([],t.revalidate_category({'id':'tokens','items':[i]},NOW+timedelta(days=1))['items'])
    def test_timezone_required(self):
        with self.assertRaises(ValueError):t.build_tokens(now=datetime(2026,11,4))
    def test_offline_does_not_resurrect_existing(self):
        def offline(*args,**kwargs):raise OSError('offline')
        r=t.build_tokens(now=NOW,opener=offline)
        self.assertEqual([],r['items']);self.assertIn('不沿用旧权益',r['brief'])
    def test_fetches_weekly_detail_not_index_snippet(self):
        index='<a href="/blog/news/M11W1/">每周福利</a><a href="https://evil.test/blog/news/M11W1/">外链</a>'
        def get(req,**kwargs):
            if req.full_url==t.SOURCES['qiniu']:return Response(QINIU,req.full_url)
            if req.full_url==t.SOURCES['autoclaw_cn']:return Response(index,req.full_url)
            if req.full_url=='https://autoclaw.zhipuai.cn/blog/news/M11W1/':return Response(WEEK,req.full_url)
            raise AssertionError('不应访问 '+req.full_url)
        r=t.build_tokens(now=NOW,opener=get)
        self.assertEqual(2,len(r['items']))
        self.assertTrue(all(i['promotion']['evidence'] and i['promotion']['source_sha256'] for i in r['items']))
    def test_redirect_to_other_site_is_not_official_evidence(self):
        with self.assertRaises(ValueError):t._get(t.SOURCES['qiniu'],lambda *a,**k:Response(QINIU,'https://evil.test/a'))
    def test_script_in_html_cannot_supply_evidence(self):
        self.assertEqual([],t.parse_source('qiniu','<script>'+QINIU+'</script>',NOW))

class ActivityIntegrationTests(unittest.TestCase):
    def run_generator(self, only='', fail_tokens=False):
        import generate as g
        import tempfile,types,copy,os,contextlib
        from contextlib import ExitStack
        ai=next(c for c in g.CATEGORIES if c['id']=='ai')
        offer=t.parse_source('qiniu',QINIU,NOW)[0]
        previous={'date':'2026-11-04','generated_at':NOW.isoformat(),'categories':[
            {**{k:ai[k] for k in ('id','name','icon','color')},'brief':'已核实新闻','items':[]},
            {**t.empty_category(),'items':[{'id':'legacy','title':'新人注册送额度','summary':'旧免费层'}]}]}
        cfg=copy.deepcopy(g.modules_config.DEFAULT_CONFIG)
        cfg['modules'].update(enabled=['ai','tokens'],show_hotlists=False,show_sports=False,show_opportunities=False)
        cfg['broadcast']['modules']=[]
        called=[]
        with tempfile.TemporaryDirectory() as folder,ExitStack() as stack:
            root=Path(folder)
            for d in ('data','reports','cache','logs','exports'):(root/d).mkdir()
            (root/'data/2026-11-04.json').write_text(json.dumps(previous))
            stack.enter_context(patch.multiple(g,DATA_DIR=root/'data',REPORT_DIR=root/'reports',CACHE_DIR=root/'cache',LOG_DIR=root/'logs',EXPORT_DIR=root/'exports',CATEGORIES=[ai,t.CATEGORY]))
            stack.enter_context(patch.object(g.modules_config,'load_config',return_value=cfg))
            stack.enter_context(patch.object(g,'now_local',return_value=NOW))
            stack.enter_context(patch.dict(os.environ,{'DIGEST_ONLY':only,'DIGEST_AI':'0','DIGEST_ROLLING':'1'}))
            stack.enter_context(patch.dict(sys.modules,{'tts_brief':types.SimpleNamespace(generate_from_digest=lambda *a,**k:{})}))
            def build(c,existing=None):
                called.append(c['id'])
                if c['id']=='tokens':
                    if fail_tokens:raise OSError('official source unavailable')
                    return {**t.empty_category(),'items':[offer]}
                return previous['categories'][0]
            stack.enter_context(patch.object(g,'build_category',side_effect=build))
            with contextlib.redirect_stdout(io.StringIO()):self.assertEqual(0,g.main())
            result=json.loads((root/'data/2026-11-04.json').read_text())
            return result,called
    def test_partial_update_still_rechecks_promotions(self):
        result,calls=self.run_generator(only='ai')
        self.assertIn('tokens',calls)
        items=next(c['items'] for c in result['categories'] if c['id']=='tokens')
        self.assertEqual(1,len(items));self.assertNotEqual('legacy',items[0]['id'])
    def test_exception_does_not_reuse_legacy_free_tier(self):
        result,_=self.run_generator(fail_tokens=True)
        cat=next(c for c in result['categories'] if c['id']=='tokens')
        self.assertEqual([],cat['items']);self.assertIn('不沿用旧权益',cat['brief'])
    def test_activity_recheck_does_not_rewrite_news_brief(self):
        import generate as g
        self.assertEqual(g.categories_fingerprint([]),g.categories_fingerprint([t.empty_category()]))
        self.assertEqual(g.categories_fingerprint([]),g.categories_fingerprint([{**t.empty_category(),'items':[t.parse_source('qiniu',QINIU,NOW)[0]]}]))
    def test_activities_are_not_inserted_into_headlines_or_default_audio(self):
        import generate as g,tts_brief as speech,copy
        offer=t.parse_source('qiniu',QINIU,NOW)[0]
        data={'categories':[{**t.empty_category(),'items':[offer]}]}
        cfg=copy.deepcopy(g.modules_config.DEFAULT_CONFIG)
        cfg['modules']['enabled']=['tokens'];cfg['broadcast']['modules']=[]
        with patch.object(speech.modules_config,'load_config',return_value=cfg),patch.object(speech,'fetch_weather_sentence',return_value=''):
            sections=speech.build_focused_chapters('2026-11-04',data)
        self.assertNotIn('一亿词元',''.join(s['text'] for s in sections))
        self.assertNotIn('限时赠送',[s['title'] for s in sections])

    def test_explicit_activity_audio_keeps_deadline_and_scope(self):
        import tts_brief as speech,copy
        offer=t.parse_source('autoclaw_cn',WEEK,NOW)[0]
        data={'categories':[{**t.empty_category(),'items':[offer]}]}
        cfg=copy.deepcopy(speech.modules_config.DEFAULT_CONFIG)
        cfg['modules']['enabled']=['tokens'];cfg['broadcast']['modules']=['tokens']
        original=t.revalidate_category
        with patch.object(speech.modules_config,'load_config',return_value=cfg),patch.object(speech,'fetch_weather_sentence',return_value=''),patch.object(t,'revalidate_category',side_effect=lambda c:original(c,NOW)):
            chapters=speech.build_focused_chapters('2026-11-04',data)
        activity=next(c for c in chapters if c['title']=='限时赠送')
        self.assertIn('截止',activity['text']);self.assertIn('客户端',activity['text'])
        self.assertNotIn('五千万词元',chapters[2]['text'])

if __name__=='__main__':unittest.main()
