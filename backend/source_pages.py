"""官方新闻列表的无执行解析；只使用页面真实给出的标题、链接与发布时间。"""
from datetime import datetime, timezone, timedelta
from html.parser import HTMLParser
from urllib.parse import urljoin,urlparse
import json,re

CN_TZ=timezone(timedelta(hours=8))
def _text(value):return re.sub(r'\s+',' ',re.sub(r'<[^>]*>',' ',value or '')).strip()
def _valid(url,host):
 p=urlparse(url);return p.scheme in ('https','http') and (p.hostname==host or (p.hostname or '').endswith('.'+host))

def yicai(raw):
 text=raw.decode('utf-8','replace');marker=re.search(r'\bvar\s+firstlist\s*=\s*',text)
 if not marker:return []
 try:rows,_=json.JSONDecoder().raw_decode(text[marker.end():])
 except (ValueError,TypeError):return []
 if not isinstance(rows,list):return []
 out=[]
 for row in rows:
  if not isinstance(row,dict):continue
  url=urljoin('https://www.yicai.com/',str(row.get('url') or ''))
  if not _valid(url,'yicai.com') or not re.fullmatch(r'/news/\d+\.html',urlparse(url).path):continue
  date=row.get('CreateDate') or row.get('pubDate')
  try:
   published=datetime.fromisoformat(date)
   if published.tzinfo is None:published=published.replace(tzinfo=CN_TZ)
  except (ValueError,TypeError):continue
  title=_text(row.get('NewsTitle'))
  if not title:continue
  out.append({'title':title,'url':url,'description':_text(row.get('NewsNotes')) or title,'published':published})
 return out

class JiemianParser(HTMLParser):
 def __init__(self):
  super().__init__(convert_charrefs=True);self.depth=0;self.current=None;self.start=0;self.capture=None;self.capture_depth=0;self.records=[]
 def handle_starttag(self,tag,attrs):
  a=dict(attrs);self.depth+=1
  if 'data-time' in a and self.current is None:
   try:pub=datetime.fromtimestamp(int(a['data-time']),CN_TZ)
   except (ValueError,OverflowError,OSError):pub=None
   if pub:self.current={'published':pub,'title':'','description':'','url':''};self.start=self.depth
  if self.current:
   if tag=='a' and re.search(r'/article/\d+\.html',a.get('href','')):
    self.current['url']=urljoin('https://www.jiemian.com/',a['href']);self.capture='title';self.capture_depth=self.depth
   if 'summary' in a.get('class',''):
    self.capture='description';self.capture_depth=self.depth
  if tag in ('img','br','hr','input','meta','link','source'):self.depth-=1
 def handle_endtag(self,tag):
  if self.current and self.depth==self.start:
   if self.current['title'] and _valid(self.current['url'],'jiemian.com'):self.records.append(self.current)
   self.current=None;self.capture=None
  if self.capture and self.depth==self.capture_depth:self.capture=None
  if tag not in ('img','br','hr','input','meta','link','source'):self.depth=max(0,self.depth-1)
 def handle_data(self,value):
  if self.current and self.capture:self.current[self.capture]+=value

def jiemian(raw):
 p=JiemianParser();p.feed(raw.decode('utf-8','replace'))
 for row in p.records:
  row['title']=_text(row['title']);row['description']=_text(row['description']) or row['title']
 return p.records

def parse(parser,raw):return {'yicai':yicai,'jiemian':jiemian}[parser](raw)
