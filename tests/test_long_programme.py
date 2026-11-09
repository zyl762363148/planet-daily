import aifc
import importlib.util
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import wave
from unittest import mock

root=Path(__file__).resolve().parents[1]
def load(name, file):
    spec=importlib.util.spec_from_file_location(name,root/'backend'/file)
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

tts=load('long_tts','tts_brief.py')
speak=load('long_speak','speak_brief.py')

class LongProgrammeTests(unittest.TestCase):
    def test_full_coverage_new_chapters_closing_and_no_english_sentences(self):
        names={'wire':'国际','policy':'政策','economy':'财经','ai':'科技','infogap':'信息','opensource':'开源','media':'媒体','health':'健康','design':'设计','games':'游戏','deals':'福利'}
        cats=[]
        for ident,name in names.items():
            items=[{'id':ident+str(i),'title':name+'第'+str(i)+'条独特事项正式公布',
                    'summary':'官方公布具体情况和安排。','source':'官方平台','score':99-i} for i in range(5)]
            if ident=='deals':
                items[0].update(validity='十一月九日截止',conditions='新用户可领取')
            cats.append({'id':ident,'name':name,'items':items})
        digest={'categories':cats,'brief':{'points':[{'text':'今天有重要新闻。'}], 'deep_stories':[]}}
        with mock.patch.object(tts,'fetch_weather_sentence',return_value='杭州富阳今天多云，最高二十度。'), mock.patch.object(tts,'load_weekly_highlights',return_value=[]):
            chapters=tts.build_ten_chapters('2026-11-03',digest)
        titles=[x['title'] for x in chapters]
        self.assertIn('游戏资讯',titles); self.assertIn('每日羊毛',titles)
        alltext=''.join(x['text'] for x in chapters)
        for name in names.values():
            for index in range(5): self.assertIn(name+'第'+str(index)+'条独特事项',alltext)
        deals=chapters[titles.index('每日羊毛')]['text']
        self.assertIn('十一月九日截止',deals);self.assertIn('新用户可领取',deals);self.assertIn('官方平台',deals)
        self.assertIn('有效期未注明',deals)
        self.assertIn('好的，今天的行星日报已经为您播放完毕，祝您生活愉快，咱们明天再见。',chapters[-1]['text'])
        self.assertGreater(len(alltext),1000)
        self.assertFalse(re.search('[A-Za-z]',alltext))

    def test_english_sentence_not_spoken_but_mixed_chinese_names_are_spelled(self):
        self.assertEqual(tts.readable_chinese_speech('The company has announced a product.'),'')
        mixed=tts.readable_chinese_speech('公司发布新版本，产品名称为 RSX。')
        self.assertIn('公司发布新版本',mixed);self.assertNotRegex(mixed,'[A-Za-z]')
        self.assertEqual(tts.readable_chinese_speech('公司说 the company has announced it will close。'),'')

    def test_long_audio_is_accepted_and_timed_from_real_frames(self):
        with tempfile.TemporaryDirectory() as td:
            td=Path(td)
            def run(cmd,**kwargs):
                if cmd[0]=='/usr/bin/say':
                    index=int(Path(cmd[cmd.index('-f')+1]).stem)
                    with wave.open(cmd[cmd.index('-o')+1],'wb') as f:
                        f.setnchannels(1);f.setsampwidth(2);f.setframerate(1);f.writeframes(bytes([0, 0])*(100+index))
                elif cmd[0]=='/usr/bin/afconvert': Path(cmd[-1]).write_bytes(b'FORM')
                return subprocess.CompletedProcess(cmd,0,'','')
            ch=[{'title':str(i),'text':'完整新闻。'} for i in range(12)]
            duration=sum(100+i for i in range(12))
            with mock.patch.object(tts,'TTS_DIR',td), mock.patch.object(tts.subprocess,'run',side_effect=run), mock.patch.object(tts,'audio_duration',return_value=duration):
                result=tts.render_audio(ch,'2026-11-03',{'voice':'Tingting','rate':200})
            self.assertGreater(result['duration'],960)
            self.assertEqual(result['duration'],duration)
            self.assertEqual(result['chapter_marks'][-1]['start'],sum(100+i for i in range(11)))

    def test_automatic_playback_timeout_accounts_for_long_audio(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'long.aiff'
            with aifc.open(str(p),'wb') as f:
                f.setnchannels(1);f.setsampwidth(2);f.setframerate(1);f.writeframes(bytes([0, 0])*1800)
            self.assertEqual(speak.playback_timeout(p),1920)
            p.write_bytes(b'not-audio')
            self.assertEqual(speak.playback_timeout(p),1200)

if __name__=='__main__':unittest.main()
