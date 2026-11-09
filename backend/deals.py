#!/usr/bin/env python3
"""公开好价线索：只收集来源明示、可追溯且近期发布的优惠。

仅从公开的什么值得买好价页面读取，不请求登录、不访问账户；不替用户领券。
没有明确截止时间的线索只显示“未注明”，不会被认定为有效到某个时间。
"""
from datetime import datetime, timedelta, timezone
from html import unescape
from html.parser import HTMLParser
import hashlib
import re
import urllib.error
import urllib.request

SOURCE_URL = 'https://www.smzdm.com/jingxuan/'
SOURCE_NAME = '什么值得买'
CATEGORY = {
    'id': 'deals', 'name': '每日羊毛', 'icon': 'gift', 'color': '#A75B3C', 'limit': 6,
    'kind': 'deals', 'feeds': [],
    'brief_note': '公开优惠线索；数量、地区、门槛和有效期以原页面为准。',
    'takeaway': '仅梳理公开优惠，请先核对适用条件、价格和有效时间。',
}
_RELEVANT = re.compile(r'优惠券|领券|红包|消费券|免单|免费领|免费领取|免费试用|优惠活动|补贴|立减|满\s*\d+\s*减|券后')
_UNWANTED = re.compile(r'拉新|邀请好友|助力|拉人|代领|刷单|兼职|返现任务|赌博|理财|实名认证|验证码')
_EXPIRED = re.compile(r'已过期|已结束|已失效|活动结束|抢光了|领完了|抢完了|优惠结束')
_DEADLINE = re.compile(r'(?:截止(?:时间)?|截至|有效期至|领取(?:截止|结束)(?:时间)?|活动(?:截至|截止|结束)(?:时间)?)\s*[：:]?\s*(20\d{2})[年./-](\d{1,2})[月./-](\d{1,2})日?(?:\s*(\d{1,2})[:：](\d{2}))?')
_HTML = re.compile(r'<[^>]+>')
_CN = re.compile(r'[\u4e00-\u9fff]')


def _text(text):
    return re.sub(r'\s+', ' ', unescape(text)).strip()


class _ListingParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.item_depth = None
        self.field_depth = None
        self.field = None
        self.item = None
        self.items = []

    def handle_starttag(self, tag, attrs):
        if tag in {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}:
            return
        self.depth += 1
        attrs = dict(attrs)
        classes = set(attrs.get('class', '').split())
        if self.item is None and tag == 'li' and 'feed-row-wide' in classes:
            self.item = {'timesort': attrs.get('timesort', ''), 'title': [], 'description': [], 'price': [], 'url': '', 'all': []}
            self.item_depth = self.depth
        if self.item is None:
            return
        if (tag == 'h5' and 'feed-block-title' in classes):
            self.field, self.field_depth = 'title', self.depth
        elif tag == 'div' and 'feed-block-descripe' in classes:
            self.field, self.field_depth = 'description', self.depth
        elif tag == 'a' and 'z-highlight' in classes:
            self.field, self.field_depth = 'price', self.depth
        if tag == 'a' and self.field == 'title':
            href = attrs.get('href', '')
            if re.fullmatch(r'https://www\.smzdm\.com/p/\d+/?', href):
                self.item['url'] = href

    def handle_startendtag(self, tag, attrs):
        if tag not in {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}:
            self.handle_starttag(tag, attrs)
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if self.item is not None:
            if self.field_depth == self.depth:
                self.field, self.field_depth = None, None
            if self.item_depth == self.depth:
                self.items.append(self.item)
                self.item = None
                self.item_depth = None
                self.field = None
        self.depth = max(0, self.depth - 1)

    def handle_data(self, text):
        if self.item is not None:
            self.item['all'].append(text)
            if self.field:
                self.item[self.field].append(text)


def _deadline(text, now):
    match = _DEADLINE.search(text)
    if not match:
        return None
    try:
        y, m, d = (int(match.group(i)) for i in (1, 2, 3))
        hour = int(match.group(4)) if match.group(4) else 23
        minute = int(match.group(5)) if match.group(5) else 59
        return datetime(y, m, d, hour, minute, tzinfo=now.tzinfo)
    except ValueError:
        return None


def parse_deals(markup, now=None, limit=6):
    now = now or datetime.now().astimezone()
    if now.tzinfo is None:
        raise ValueError('需要带时区的当前时间')
    parser = _ListingParser()
    parser.feed(markup)
    offers, seen = [], set()
    for raw in parser.items:
        title, description, price = (_text(''.join(raw[key])) for key in ('title', 'description', 'price'))
        description = re.sub(r'阅读全文\s*$', '', description).strip()
        full = _text(' '.join((title, description, price)))
        all_text = _text(''.join(raw['all']))
        if not title or not raw['url'] or raw['url'] in seen or not _RELEVANT.search(full):
            continue
        if _UNWANTED.search(full) or _EXPIRED.search(all_text):
            continue
        try:
            published = datetime.fromtimestamp(int(raw['timesort']), tz=timezone.utc).astimezone(now.tzinfo)
        except (ValueError, TypeError, OSError, OverflowError):
            continue
        # 无截止时间不代表永久有效：只保留近 12 小时公开线索，不对未来条目提前发布。
        if published > now + timedelta(minutes=5) or now - published > timedelta(hours=12):
            continue
        deadline = _deadline(full, now)
        if deadline is not None and deadline < now:
            continue
        match = _DEADLINE.search(full)
        if deadline and match and match.group(4):
            validity = f"截至{deadline.strftime('%Y年%m月%d日 %H:%M')}，具体以原页面为准。"
        elif deadline:
            validity = f"截至{deadline.strftime('%Y年%m月%d日')}，具体结束时间以原页面为准。"
        else:
            validity = '有效期未注明，领取前请核对原页面。'
        summary = '；'.join(part for part in (description, price) if part) or title
        summary = f'{summary} {validity}'
        # 临时不收未经翻译的英文正文，避免违背中文阅读偏好。
        if not _CN.search(title) or re.search(r'[A-Za-z]', title + summary):
            continue
        seen.add(raw['url'])
        offers.append({
            'id': hashlib.sha256(raw['url'].encode()).hexdigest()[:16],
            'title': title, 'original_title': title, 'source': SOURCE_NAME, 'url': raw['url'],
            'time': published.strftime('%m-%d %H:%M'), 'published_at': published.isoformat(),
            'heat': '', 'score': round(max(1.0, 100.0 - (now - published).total_seconds()/3600), 2),
            'summary': summary, 'takeaway': '领取前核对平台规则、价格、地区及有效期。',
            'interpretation': '', 'perspective': '', 'tags': [], 'audience': '',
            'validity': validity, 'expires_at': deadline.isoformat() if deadline else None,
        })
        if len(offers) >= limit:
            break
    return offers


def build_deals(category=None, now=None, opener=None):
    category = category or CATEGORY
    result = {key: category[key] for key in ('id', 'name', 'icon', 'color')}
    source_failed = False
    try:
        req = urllib.request.Request(SOURCE_URL, headers={'User-Agent': 'Mozilla/5.0 (compatible; DailyDigest/1.0)', 'Accept': 'text/html'})
        with (opener or urllib.request.urlopen)(req, timeout=15) as response:
            data = response.read(2_000_000).decode('utf-8', errors='replace')
        items = parse_deals(data, now=now, limit=category.get('limit', 6))
    except (OSError, ValueError, urllib.error.URLError) as exc:
        print(f'每日羊毛信源暂不可用：{type(exc).__name__}', flush=True)
        source_failed = True
        items = []
    items = (fetch_epic(now=now, opener=opener) + items)[:category.get('limit', 6)]
    if not items:
        result.update(brief=('优惠线索暂时获取失败或没有可展示的信息，请稍后重试。' if source_failed else '目前没有核对到可展示的近期中文优惠线索，请稍后再查看。'), items=[])
    else:
        result.update(brief='公开优惠线索，金额、地区、条件和有效期均以原页面为准。', items=items)
    return result

# 官方游戏商城的公开限免接口；未知外文名称暂缓，等待可信中文翻译。
EPIC_URL = 'https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=zh-CN&country=CN&allowCountries=CN'
_EPIC_CHINESE_TITLES = {"sorry we're closed": '抱歉我们打烊了'}

def parse_epic(payload, now=None):
    now = now or datetime.now().astimezone()
    if now.tzinfo is None:
        raise ValueError('需要带时区的当前时间')
    offers = []
    data = payload.get('data') or {}
    elements = (((data.get('Catalog') or {}).get('searchStore') or {}).get('elements') or [])
    for game in elements:
        raw_title = str(game.get('title') or '').strip('《》 ')
        key = raw_title.lower().replace('’', "'")
        title = _EPIC_CHINESE_TITLES.get(key) or (raw_title if _CN.search(raw_title) and not re.search(r'[A-Za-z]',raw_title) else '')
        if not title:
            continue
        price = ((game.get('price') or {}).get('totalPrice') or {})
        if price.get('discountPrice') != 0 or not isinstance(price.get('originalPrice'), (int,float)) or price['originalPrice'] <= 0:
            continue
        mappings = ((game.get('catalogNs') or {}).get('mappings') or game.get('offerMappings') or [])
        slug = next((m.get('pageSlug') for m in mappings if isinstance(m,dict) and m.get('pageType') == 'productHome' and re.fullmatch(r'[a-z0-9-]+',str(m.get('pageSlug') or ''))), None)
        if not slug:
            continue
        groups = ((game.get('promotions') or {}).get('promotionalOffers') or [])
        for group in groups:
            for offer in group.get('promotionalOffers') or []:
                if (offer.get('discountSetting') or {}).get('discountPercentage') != 0:
                    continue
                try:
                    start = datetime.fromisoformat(offer['startDate'].replace('Z','+00:00')).astimezone(now.tzinfo)
                    end = datetime.fromisoformat(offer['endDate'].replace('Z','+00:00')).astimezone(now.tzinfo)
                except (KeyError, ValueError, TypeError):
                    continue
                if not (start <= now < end):
                    continue
                url = 'https://store.epicgames.com/zh-CN/p/' + slug
                validity = f"截至{end.strftime('%Y年%m月%d日 %H:%M')}，以商店页面为准。"
                original = price.get('fmtPrice',{}).get('originalPrice','')
                old_price = ''
                if price.get('currencyCode') == 'CNY':
                    old_price = f"原价{price['originalPrice']/100:g}元，"
                summary = f"{old_price}限时免费领取，需使用商城账户；地区与资格以商店页面为准。{validity}"
                offers.append({'id':hashlib.sha256(url.encode()).hexdigest()[:16],
                    'title':f'游戏商城限时免费领取《{title}》','original_title':raw_title,
                    'source':'艾匹克游戏商城','url':url,'time':'活动进行中','published_at':start.isoformat(),
                    'heat':'','score':100.0,'summary':summary,'takeaway':'领取前核对商店的地区与账户条件。',
                    'interpretation':'','perspective':'','tags':[],'audience':'',
                    'conditions':'需商城账户，地区与资格以商店页面为准。','validity':validity,'expires_at':end.isoformat()})
                break
    return offers

def fetch_epic(now=None, opener=None):
    import json
    req = urllib.request.Request(EPIC_URL, headers={'User-Agent':'Mozilla/5.0 (compatible; DailyDigest/1.0)', 'Accept':'application/json'})
    try:
        with (opener or urllib.request.urlopen)(req,timeout=15) as response:
            payload=json.loads(response.read(2_000_000))
        return parse_epic(payload, now)
    except (OSError,ValueError,TypeError,urllib.error.URLError) as exc:
        print(f'官方游戏限免源暂不可用：{type(exc).__name__}',flush=True)
        return []
