#!/usr/bin/env python3
"""只收有官方证据、正在进行的词元赠送活动；拒绝长期免费层和注册礼。"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen
import hashlib
import re

BEIJING = timezone(timedelta(hours=8))
MAX_VERIFY_AGE = timedelta(hours=24)
CATEGORY = {'id': 'tokens', 'name': '限时赠送', 'icon': 'gift', 'color': '#426B78',
            'limit': 8, 'kind': 'tokens', 'feeds': [],
            'brief_note': '仅收仍在活动期的官方词元赠送；不收长期免费套餐、注册礼和充值奖励。',
            'takeaway': '逐项核验发放时间、截止时间、使用范围和门槛。'}
SOURCES = {
    'qiniu': 'https://www.qiniu.com/ai/free-models/conatus-2026',
    'autoclaw_cn': 'https://autoclaw.zhipuai.cn/blog/news/',
}

class Page(HTMLParser):
    def __init__(self, raw):
        super().__init__(); self.parts = []; self.links = []; self.skip = 0
        self.feed(raw)
    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style', 'noscript'): self.skip += 1
        if tag == 'a':
            self.links.extend(v for k, v in attrs if k == 'href' and v)
    def handle_endtag(self, tag):
        if tag in ('script', 'style', 'noscript'): self.skip = max(0, self.skip - 1)
    def handle_data(self, data):
        if not self.skip: self.parts.append(data)
    @property
    def text(self): return re.sub(r'\s+', ' ', ' '.join(self.parts)).strip()


def _get(url, opener=None):
    request = Request(url, headers={'User-Agent': 'Mozilla/5.0 (DailyDigest)',
                                   'Cache-Control': 'no-cache', 'Pragma': 'no-cache'})
    with (opener or urlopen)(request, timeout=15) as response:
        final = response.geturl() if hasattr(response, 'geturl') else url
        if urlparse(final).scheme != 'https' or urlparse(final).netloc != urlparse(url).netloc:
            raise ValueError('活动页重定向到了其他站点')
        raw = response.read(2_000_001)
        if len(raw) > 2_000_000: raise ValueError('活动页超出大小限制')
        return raw.decode('utf-8', 'replace')


def _date(year, month, day, hour=0, minute=0):
    return datetime(int(year), int(month), int(day), int(hour), int(minute), tzinfo=BEIJING)


def is_current(item, now):
    """旧版免费层、未知时区、未来/过期活动和超过24小时的核验全部拒绝。"""
    p = item.get('promotion') or {}
    try:
        checked, start, end = [datetime.fromisoformat(p[k]) for k in ('checked_at', 'starts_at', 'expires_at')]
        return (p.get('verified') is True and p.get('kind') in ('limited_grant', 'daily_event')
                and all(x.tzinfo is not None for x in (checked, start, end, now))
                and timedelta(0) <= now - checked < MAX_VERIFY_AGE
                and start <= checked < end and start <= now < end)
    except (ValueError, TypeError, KeyError): return False


def _item(key, title, summary, url, checked, start, end, kind, timing, eligibility, scope, evidence, raw, score=90):
    if not start <= checked < end: return None
    p = {'verified': True, 'kind': kind, 'checked_at': checked.isoformat(timespec='seconds'),
         'starts_at': start.isoformat(timespec='seconds'), 'expires_at': end.isoformat(timespec='seconds'),
         'timing': timing, 'eligibility': eligibility, 'scope': scope,
         'source_url': url, 'source_sha256': hashlib.sha256(raw.encode()).hexdigest(), 'evidence': evidence}
    return {'id': hashlib.sha256((key + start.isoformat()).encode()).hexdigest()[:16],
            'title': title, 'original_title': title, 'source': '七牛云官方' if key == 'qiniu' else '智谱官方',
            'url': url, 'time': checked.astimezone(BEIJING).strftime('%m月%d日 %H:%M 核验'),
            'heat': '', 'score': score, 'summary': summary, 'takeaway': timing,
            'interpretation': eligibility + '。' + scope, 'perspective': '', 'audience': '开发者',
            'tags': ['官方活动', '每日发放' if kind == 'daily_event' else '限时领取'], 'promotion': p}


def parse_source(key, raw, checked_at, url=None):
    if checked_at.tzinfo is None: raise ValueError('核验时间需要时区')
    text = Page(raw).text; url = url or SOURCES.get(key, '')
    if re.search(r'本期活动已结束|本活动已结束|活动提前结束|活动已取消|活动已终止|暂停领取|停止发放|本期已领完', text): return []
    item = None
    if key == 'qiniu':
        required = ('Conatus', '活动进行中', '已认证', '每日 1 亿 Token', '实名认证',
                    '每日 00:00 重置', '未使用额度不结转', '不支持超额按量计费')
        if not all(x in text for x in required): return []
        match = re.search(r'(20\d{2})\s*年\s*(\d+)\s*月\s*(\d+)\s*日\s*(\d+):(\d+)\s*至\s*(20\d{2})\s*年\s*(\d+)\s*月\s*(\d+)\s*日\s*(\d+):(\d+)', text)
        if not match: return []
        g = match.groups(); start = _date(*g[:5]); end = _date(*g[5:]) + timedelta(minutes=1)
        item = _item(key, '七牛云限时活动：每天赠送一亿词元',
            '活动期间，完成实名认证的用户每天可使用一亿词元；输入、输出与缓存输入合计。同一账号的所有密钥共享额度，用完即停，不自动扣费。',
            url, checked_at, start, end, 'daily_event',
            f'北京时间每日零点重置，不结转；活动至{end - timedelta(minutes=1):%Y年%m月%d日 %H:%M}。',
            '面向已登录、已实名且未受风控限制的用户；这一亿档不要求充值，排除充值提升档',
            '仅限七牛云本次融合模型接口，不是可转移的通用余额。',
            ['已认证 每日 1 亿 Token', match.group(0), '每日 00:00 重置'], raw, 95)
    elif key == 'autoclaw_cn':
        # 只解析官方每周发放公告正文；导航里的“免费注册”不构成赠送证据。
        match = re.search(r'活动时间\s*(\d+)\s*月\s*(\d+)\s*日.*?00:00\s*[—–-]+\s*(\d+)\s*月\s*(\d+)\s*日.*?23:59\s*[（(]北京时间[）)]', text)
        year = re.search(r'作者.*?(20\d{2})年\d+月\d+日', text)
        quota = re.search(r'活动规则[：:]\s*登录\s*AutoClaw[，,]\s*即可领取\s*(\d+)\s*M\s*Tokens.*?每个账号限领一次', text, re.I)
        if not (match and year and quota): return []
        if re.search(r'活动规则.{0,160}(?:新用户专享|仅限新用户|首次注册|付费会员专享|需充值)', text): return []
        month, day, emonth, eday = match.groups(); y = int(year[1])
        start = _date(y, month, day); end = _date(y + (int(emonth) < int(month)), emonth, eday, 23, 59) + timedelta(minutes=1)
        expiry = re.search(r'奖励将在\s*(\d+)\s*月\s*(\d+)\s*日\s*23:59\s*失效', text)
        if not expiry or tuple(map(int, expiry.groups())) != (int(emonth), int(eday)): return []
        millions = int(quota[1]); amount = str(millions * 100) + '万'
        item = _item(key, f'智谱澳龙本周赠送{amount}词元',
            f'本周登录国内版澳龙，可领取{amount}词元，每个账号限一次。',
            url, checked_at, start, end, 'limited_grant',
            f'北京时间{start:%m月%d日 %H:%M}开始，{end - timedelta(minutes=1):%m月%d日 %H:%M}领取与使用同时截止。',
            '本期登录用户可参与，每个账号限领一次；公告未要求购买会员或充值',
            '通过澳龙客户端领取与使用，词元按官方积分换算；公告未说明可转入通用接口。',
            [match[0], quota[0], expiry[0]], raw, 100)
    return [item] if item else []


def empty_category(category=None):
    c = category or CATEGORY
    return {**{k: c[k] for k in ('id', 'name', 'icon', 'color')}, 'items': [],
            'brief': '本次未核实到仍在进行的词元赠送活动；无法访问、规则不明或已到期的活动均不展示，不沿用旧权益。'}


def revalidate_category(category, now=None):
    now = now or datetime.now(BEIJING)
    result = {**category, 'items': [i for i in category.get('items', []) if is_current(i, now)]}
    if not result['items']: result['brief'] = empty_category()['brief']
    return result


def build_tokens(category=None, now=None, opener=None):
    checked = now or datetime.now(BEIJING)
    if checked.tzinfo is None: raise ValueError('核验时间需要时区')
    result = empty_category(category); audits = []
    def load(pair):
        key, source = pair; items = []; records = []
        try:
            raw = _get(source, opener)
            urls = [source]
            if key == 'autoclaw_cn':
                urls = list(dict.fromkeys(urljoin(source, link) for link in Page(raw).links
                               if re.fullmatch(r'/blog/news/M\d{1,2}W\d{1,2}/', link)))[:8]
            for url in urls:
                page = raw if url == source else _get(url, opener)
                parsed = parse_source(key, page, checked, url)
                items.extend(parsed)
                records.append({'source_url': url, 'status': 'verified' if parsed else 'excluded',
                                'reason': '官方规则、日期与赠送条件匹配' if parsed else '非当前有效的赠送活动或规则证据不足',
                                'source_sha256': hashlib.sha256(page.encode()).hexdigest()})
        except Exception as exc:
            print(f'限时赠送来源 {key} 核验失败：{type(exc).__name__}，不复用旧条目。', flush=True)
            records.append({'source_url': source, 'status': 'unavailable', 'reason': type(exc).__name__})
        return items, records
    with ThreadPoolExecutor(max_workers=3) as pool:
        for batch, records in pool.map(load, SOURCES.items()):
            result['items'].extend(batch); audits.extend(records)
    result['items'] = sorted((i for i in result['items'] if is_current(i, checked)), key=lambda i: -i['score'])[:(category or CATEGORY).get('limit', 8)]
    result['verification'] = {'checked_at': checked.isoformat(timespec='seconds'), 'sources': audits}
    if result['items']:
        result['brief'] = f'本次官方核验通过{len(result["items"])}项活动。只收限时赠送与活动期内的每日发放，展示北京时间、使用范围及参与门槛；不收新人礼、长期免费层或充值奖励。'
    return result
