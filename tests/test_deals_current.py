import sys, unittest
from unittest.mock import patch
from pathlib import Path
from datetime import datetime, timedelta, timezone
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
import deals

NOW = datetime(2026, 11, 3, 10, 0, tzinfo=timezone(timedelta(hours=8)))

def fixture(title='领取优惠券', detail='领取后立减十元', published=NOW, url='https://www.smzdm.com/p/1234/'):
    return f'''<li class="feed-row-wide" timesort="{int(published.timestamp())}">
      <h5 class="feed-block-title"><a href="{url}">{title}</a></h5>
      <div class="feed-block-descripe">{detail}</div></li>'''

class DealsTests(unittest.TestCase):
    def test_expired_and_referral_not_published(self):
        self.assertEqual([], deals.parse_deals(fixture(detail='活动截止2026年11月02日'), NOW))
        self.assertEqual([], deals.parse_deals(fixture(title='邀请好友领取优惠券'), NOW))
        self.assertEqual([], deals.parse_deals(fixture(published=NOW-timedelta(hours=13)), NOW))
    def test_missing_and_explicit_deadline_are_labelled(self):
        offers=deals.parse_deals(fixture(), NOW)
        self.assertEqual(1,len(offers)); self.assertIn('有效期未注明',offers[0]['summary'])
        timed=deals.parse_deals(fixture(detail='截止2026年11月04日 18:30'),NOW)
        self.assertIn('18:30',timed[0]['validity'])
        date_only=deals.parse_deals(fixture(detail='截止2026年11月04日'),NOW)
        self.assertNotIn('23:59',date_only[0]['validity'])
    def test_invalid_and_untrusted_links_are_omitted(self):
        self.assertEqual([], deals.parse_deals(fixture(url='https://example.com/p/1234/'),NOW))
    def test_official_free_game_needs_valid_dates_and_chinese_title(self):
        game = {'title': 'Sorry We’re Closed', 'catalogNs': {'mappings': [{'pageType':'productHome', 'pageSlug':'sorry-were-closed-724c86'}]},
                'price': {'totalPrice': {'discountPrice': 0, 'originalPrice': 7800, 'currencyCode': 'CNY'}},
                'promotions': {'promotionalOffers':[{'promotionalOffers':[{'startDate':'2026-10-29T15:00:00Z', 'endDate':'2026-11-05T16:00:00Z', 'discountSetting':{'discountPercentage':0}}]}]}}
        payload={'data':{'Catalog':{'searchStore':{'elements':[game]}}}}
        result=deals.parse_epic(payload, NOW)
        self.assertEqual(1,len(result)); self.assertIn('抱歉我们打烊了',result[0]['title']); self.assertIn('2026年11月06日 00:00',result[0]['validity'])
        self.assertEqual([],deals.parse_epic(payload, datetime(2026,11,6,0,0,tzinfo=NOW.tzinfo)))
        game['title']='Some Unknown Game'; self.assertEqual([],deals.parse_epic(payload,NOW))

    def test_official_source_still_works_if_aggregator_fails(self):
        def offline(*args,**kwargs): raise OSError('offline')
        with patch.object(deals, 'fetch_epic', return_value=[{'title':'免费游戏'}]):
            result=deals.build_deals(now=NOW, opener=offline)
        self.assertEqual('免费游戏',result['items'][0]['title'])

    def test_network_failure_returns_clear_empty_category(self):
        def offline(*args,**kwargs): raise OSError('offline')
        result=deals.build_deals(now=NOW,opener=offline)
        self.assertEqual([],result['items']);self.assertIn('获取失败',result['brief'])

if __name__=='__main__':unittest.main()
