行星日报 · Windows 离线版
========================================

打开方式
  双击 Launch.bat（推荐）。它会启动一个只监听 127.0.0.1 的本地小服务并用默认浏览器打开；
  如果电脑没装 Python，会自动直接打开 PlanetDaily.html，多数功能仍可使用。
  建议用 Microsoft Edge 或 Chrome。

文件内容
  PlanetDaily.html   完整客户端，数据已内嵌，可离线阅读
  Launch.bat         双击启动
  Refresh.bat        换数据后重新生成页面
  build_windows.py   生成器（Refresh.bat 会调用）
  data/latest.json   当天的日报数据快照
  data/config.json   栏目、皮肤、城市等偏好
  data/meta.json     期号
  data/tts/          播报章节时间点
  audio/brief.mp3    当天中文语音播报（若有；也可能是 brief.m4a）
  template.html      页面模板（普通使用不需要动）

更新内容
  方式一（推荐）：在 Mac 版行星日报里点「文件 → 导出 Windows 版…」，把整个 windows
                  文件夹拷贝过来覆盖即可，数据与语音一起更新。
  方式二：把新的 latest.json 放进 data 文件夹，双击 Refresh.bat。

界面功能
  左侧选栏目、换 5 套皮肤、切换明暗；右上角搜索全部栏目；
  电台卡可播放内置中文语音、点章节跳转，没有音频时点「朗读提要」用浏览器语音；
  今日栏目卡片点进去看该栏目全文，条目可点「阅读原文」跳转官网。

关于独立 exe
  这套是免安装版，不需要管理员权限、不写注册表、不联网。
  如果要打包成单个 .exe，需要在 Windows 电脑上用 Electron 或 PyInstaller 打包本目录；
  macOS 无法直接生成可在 Windows 运行的原生 exe。

全部内容为中文，数据来自本机日报快照；不接在线翻译，不接任何大模型服务。
