import importlib.util, json, tempfile, unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

p=Path(__file__).resolve().parents[1] / 'backend' / 'tts_brief.py'
spec=importlib.util.spec_from_file_location('weather_tts_test',p); t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)

class WeatherLocationTests(unittest.TestCase):
    def test_stale_other_city_cache_is_never_relabelled(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'cache').mkdir();day='2026-10-30'
            (root/'cache'/f'weather-{day}.json').write_text(json.dumps({'daily':{'time':[day],'weather_code':[0],'temperature_2m_min':[-20],'temperature_2m_max':[-10]}}))
            (root/'config.json').write_text(json.dumps({'city':'杭州富阳','latitude':30.05,'longitude':119.95},ensure_ascii=False))
            with patch.object(t,'BASE_DATA_ROOT',root),patch.object(t,'CONFIG_PATH',root/'config.json'),patch.object(t.urllib.request,'urlopen',side_effect=OSError('offline')):
                result=t.fetch_weather_sentence(day)
            self.assertIn('杭州富阳',result);self.assertNotIn('-20',result);self.assertIn('没有取到',result)

    def test_temperature_and_location_use_current_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);day=datetime.now().strftime('%Y-%m-%d')
            (root/'config.json').write_text(json.dumps({'city':'杭州富阳','latitude':30.05,'longitude':119.95},ensure_ascii=False))
            payload={'current':{'time':day+'T08:00','temperature_2m':19.0},'daily':{'time':[day],'weather_code':[1],'temperature_2m_min':[16.0],'temperature_2m_max':[25.0]}}
            class Response:
                def __enter__(self):return self
                def __exit__(self,*args):pass
                def read(self,*args):return json.dumps(payload).encode()
            with patch.object(t,'BASE_DATA_ROOT',root),patch.object(t,'CONFIG_PATH',root/'config.json'),patch.object(t.urllib.request,'urlopen',return_value=Response()):
                result=t.fetch_weather_sentence(day)
            self.assertIn('杭州富阳',result);self.assertIn('8点00分气温约19度',result);self.assertIn('最低16度',result);self.assertIn('最高25摄氏度',result)

if __name__=='__main__':unittest.main()
