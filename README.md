# 行星日报

一个本地 macOS 桌面应用：每天把各栏目的公开信息抓取下来，整理成 **一日简报 + 机会信号 + 今日热点 + 全网热榜 + 今日专题 + 干货 + 为什么值得看 + 解读**，支持按日期归档、一周回顾、每日语音播报和每日邮件推送。侧栏不再展示收藏入口，原有收藏数据保留。

- 应用：`~/Applications/行星日报.app`（桌面也有快捷方式）
- 源码：`~/Developer/DailyDigest`
- 数据：`~/Library/Application Support/DailyDigest/data/`（自动按保留策略清理，见下文）
- 滚动更新：`09:00` 全量 + `12/16/20` 增量，LaunchAgent `com.c.dailydigest.generate`
- 语音播报：每天 `09:10`，LaunchAgent `com.c.dailydigest.speak`
- 邮件推送：每天 `09:30`，LaunchAgent `com.c.dailydigest.email`

## 栏目

固定顺序（侧栏按「速览 / 环球 / 政策 / 洞见 / 生活」分组，速览组含今日速览、热榜、收藏）：

1. 环球通讯社（侧栏「环球」组第一个）
2. 政策解读（侧栏「政策」组）
3. 信息差
4. 经济
5. AI
6. 开源
7. 设计师
8. 新媒体
9. 健康

每个栏目每天 4–5 条（滚动更新时上限放宽到 7 条），卡片包含：

- 标题（15pt semibold），左侧 3pt 栏目色条
- 干货 / 为什么值得看 / 解读：各自一个带栏目色的小 chip
- 政策条目额外显示「与谁有关：普通人 / 创业者 / 开发者 / 投资者」
- 底部 metadata 行：序号、来源、时间、热度（数字等宽字体）、阅读原文
- 右上角星标收藏

经济栏目会标注“不构成投资建议”，健康栏目会标注“不构成医疗建议”，政策栏目会标注“仅为信息梳理，不构成官方解读”。

## 环球通讯社与外媒中文源

当前只收中文报道，不调用在线大模型或翻译服务。环球通讯社采用中新网国际/国内、英国广播公司中文、德国之声中文；外媒编译优先德国之声、法广、金融时报中文网、日经中文与纽约时报中文等官方中文源。网络不可达会明确记录缺失来源，使用可用中文来源继续更新。

2026-11-06 修复了德国之声的订阅地址与 RSS 1.0/RDF 命名空间解析。第一财经、界面新闻已改用官方列表页的真实发布时间；不使用抓取时间冒充新闻发布时间。无法读取、404 或返回网页而非订阅内容的旧地址已从活动源表撤下，避免把“连接成功但抓到零条”误算正常。

## 政策解读

侧栏「政策」组，色系使用沉稳绀青/深蓝 `#2C4A7C`。来源优先政府与部委的公开信息：

- 中国政府网「政策」列表页
- 新华网「政治」列表页
- 国家发改委「发展改革委令」
- 财政部「财政新闻」
- 中国人民银行「沟通交流」
- 教育部「工作动态」
- 住房和城乡建设部、人力资源和社会保障部（列表页可抓时自动收录）

这些站点大多没有稳定 RSS，脚本按公开列表页解析标题、链接和日期；某个源失败只记日志并跳过。政策栏目的时间窗口放宽到 7 天，避免只抓到当天发布会；标题会做政策相关性过滤和跨来源去重，同一份文件不会重复出现。

每条政策卡片会由 AI 补一个 `audience` 字段，标注「与谁有关」：普通人 / 创业者 / 开发者 / 投资者。栏目导语和页面顶部都会注明：

> 仅为信息梳理，不构成官方解读。具体执行口径、适用范围和申报条件，请以官方原文及主管部门答复为准。

## 全网热榜

参考「要知」的榜单样式，每天生成时同时抓取公开热榜快照，写入当日 JSON 的 `hotlists` 字段：

- 微博热搜：先访问 weibo.com 取得访客 Cookie，再请求 `weibo.com/ajax/side/hotSearch`；自动过滤广告词条，保留「爆 / 沸 / 热 / 新」标签与热度数值（`backend/hotlists.py`）。
- 知乎热榜：`api.zhihu.com/topstory/hot-list` 公开接口；链接转换为 `www.zhihu.com/question/<id>`。
- 抖音热点：`iesdouyin.com` 公开榜单接口，含热度值与平台标签；链接为抖音站内搜索页。
- 百度热搜：`top.baidu.com/api/board` 公开接口（该榜无热度值，仅词条与链接）。
- 四个来源各保留前 20 条，只含标题、链接、热度与平台标签，不做 AI 改写，避免编造。
- **位次趋势**：生成时自动与上一期归档快照（向前最多回看 7 天）按标题对名次，词条带 `prev_rank`；App 显示 ↑/↓/— 箭头。上期未上榜的词条无箭头。
- 榜单是实时快照：每次生成（含 12/16/20 滚动增量）都会重新抓取并覆盖；某个来源抓取失败时沿用当天旧快照并在日志里记录，快照自带更新时间。
- 展示位置：侧栏「速览 → 热榜」完整页（四源双列，含趋势箭头与热度条），今日速览页右栏为微博/知乎前五摘要卡；来源带平台标识（微博/知乎/抖音/百度品牌色圆角方标），词条点击直达对应平台讨论页。
- 只有当天 JSON 里有 `hotlists` 时才显示；旧日期数据自然留空，历史快照随日报一起归档。

## 存储保留策略

每天生成完成后自动清理过期产物（`generate.py` 的 `cleanup_expired`），默认：播报音频与稿件保留 30 天、日报 JSON 与衍生报告保留 90 天、缓存 14 天；配置为 `0` 表示该类永久保留：

```json
{ "retention": { "audio_days": 30, "json_days": 90, "cache_days": 14 } }
```

只删除带日期的产物文件；`latest.json`、`favorites.json`、`config.json`、备份目录不受影响。收藏是完整快照，旧日报被清理后仍可阅读。

## 一日简报

每天生成完所有栏目后，会跨栏目挑 5–8 条写成一份简报：

- 200–300 字导语，说明今天几条主线如何相互关联
- 每条要点带栏目名 chip，点击可跳到对应栏目和卡片
- 新增「💡 机会信号」1–3 条，每条写清「机会在哪」和「怎么跟进」，优先来自 AI / 政策 / 经济栏目
- 显示在「今日速览」Hero 下方，也作为邮件正文和语音播报的核心内容
- 同时导出 `reports/brief-YYYY-MM-DD.md`

AI 失败时按热度本地降级：导语用各栏目导语拼接，要点按分数选 5–8 条，机会信号优先从 AI / 政策 / 经济的高分条目里挑。不会让速览页空掉。

## 一周

侧栏最下方的「一周」入口，聚合过去 7 天的本地 JSON：

- 收藏优先；其余按日期轮转，每天先取分数最高的一条，保证一周里每天都有露出
- 按栏目分组，每组最多 6 条
- 顶部展示 open-meteo 未来 7 天天气（杭州富阳默认），SF Symbol 图标 + 最高/最低温
- 点击条目会跳到对应日期的栏目并定位卡片
- 数据不足时显示「本周数据生成中」

天气城市可在配置文件里改：

```json
// ~/Library/Application Support/DailyDigest/config.json
{ "city": "杭州富阳", "latitude": 30.05, "longitude": 119.95 }
```

## 今日专题

每天生成完各个栏目后，会从全部条目里再挑一个跨栏目主题，写一段导语和 3 条要点，并关联 3–6 条原文条目。专题在今日速览页默认折叠成一行，点击「展开」后显示完整内容；相关条目可以直接跳到对应栏目和卡片位置。

专题生成失败时，会退回按共同标签和栏目内容拼出的本地专题，不会让速览页空掉。

## 收藏与归档

- 文章卡片和搜索结果右上角的星标可以收藏；收藏会保存标题、摘要、来源、日期和原文链接的本地快照，跨日期保留。
- 左侧「收藏」可以集中阅读、打开原栏目或取消收藏。
- 顶部日期右侧的日历按钮可以打开归档日历；有日报的日期会显示圆点，点击即可切换。
- 收藏数据保存在 `~/Library/Application Support/DailyDigest/favorites.json`，不上传。
- Bundle ID 仍是 `com.c.dailydigest`，数据目录仍是 `~/Library/Application Support/DailyDigest`，改名不会丢历史数据。

## 第四版视觉系统（晨版印刷）

速览页按晨报头版组织：宋体特黑大日期 + 期数 + 报纸双规则线作刊头；播报条收窄为深蓝电台横带；主体为「一日简报（宽栏，宋体头条 + 朱砂编号要点，默认 8 条可展开）× 全网热榜（340pt 窄栏，微博/知乎各前五堆叠）」双栏；下方是机会信号通栏三列绿带、热点深读双列卡片（描边领域 tag + 宋体标题 + 中外双视角展开）和默认折叠的今日专题行。热榜排名用宋体数字（朱砂/金/铜）+ 爆沸新印章标签，完整热榜页双列展示。卡片统一纸面圆角 14pt + 单层投影，不再描边；版块由朱砂眉标 + 发丝线组织。配色与令牌由 `Theme.swift` 统一管理，深浅色跟随系统外观，验收标准见 `DESIGN.md`。

## 日常使用

打开：

```bash
open "$HOME/Applications/行星日报.app"
```

- 默认进入「今日速览」，显示一行日期、条数与预计阅读时长；正文只保留四块：今日播报 → 一日简报（含机会信号）→ 今日热点 TOP5 → 今日专题（默认折叠成一行）。
- 侧栏五组：速览（今日速览、收藏）、环球（环球通讯社、信息差、经济）、政策（政策解读）、洞见（AI、开源）、生活（设计师、新媒体、健康）；「一周」固定在最下面。
- 顶部搜索框会跨日期搜索全部归档的标题、干货、解读和标签（结果按日期分组，可跳回对应栏目与日期）；点“在栏目中查看”跳回对应栏目。
- 左右箭头切换日期；点击日期打开归档日历；“回到今天”回到当天。
- 右上角“立即更新”或 `Command + Shift + G` 手动生成。
- `Command + R` 重新读取当前日期的数据。
- 生成期间应用仍可阅读旧日报；完成后自动刷新。
- 应用重新激活时，如果今天的新数据已经生成，会自动切到今天。
- 窗口宽时栏目卡片双列（最小 380pt/列），窄时自动单列；速览页始终单列大卡。
- 窗口右上角「外观」可切换白天模式、深色模式或跟随系统，选择会保存；也可通过菜单栏「外观」切换。


## 全中文与信源策略（2026-11-04 改版）

- **不接任何在线翻译 / 大模型服务**：生成过程零 API Key、零排队。原来的智谱调用与硬编码 Key 已删除；`DIGEST_AI` 默认为 0，只有显式设为 1 才会调用本机 opencode CLI。翻译只复用本机永久译文缓存，未命中的条目交给中文门槛暂缓入库。
- **只收中文源**：环球通讯社、外媒编译、人工智能、财经、体育、生活、健康、设计、新媒、游戏、开源动态、政策全部改用中文 RSS 与官方中文站点。
- **外媒中文版优先**：BBC 中文、德国之声中文、法广华语、FT 中文网、日经中文、纽约时报中文、联合早报等标注 `via_proxy`。程序先探测本机可用代理（可用 `DIGEST_PROXY=http://127.0.0.1:7890` 显式指定，也会自动找 7890 / 7897 / 1087 / 8888 / 10809 / 33210 等常见端口），找到就走代理，找不到自动降级为中新网等中文国际报道。开代理后不用改代码，重跑一次即可生效。
- **中文硬门槛**：`fetch_feed` 里标题不含中文的条目直接丢弃，摘要非中文时回退到中文标题；`drop_untranslated` 再兜一层，未完成中文的条目暂缓入库，绝不进口播。
- **RSS 容错**：XML 有轻微瑕疵的中文源改用标签块宽容解析救回，仍要求标题、链接与日期齐全。
- **已下线栏目**：「限时赠送 / 免费模型汇总」「每日羊毛」按用户要求整体移除，配置、侧栏注册表与设置文案均已清理。语音播报只讲勾选的重点栏目，不再念羊毛与免费额度。

## 游戏资讯

- 「游戏资讯」汇总游戏作品、发行和更新动态，以中文新闻与来源链接为主；没有可靠结果时显示空状态。

## 语音播报（第三版）

按用户勾选的播报栏目生成「重点播报」：开场 → 今日重点 → 热点背景 → 勾选的重点栏目 → 收尾（默认 9 章）。只讲重点新闻，羊毛、免费额度、限时赠送、一周回顾、机会信号一律不进播报；未中文化的条目暂缓播报。全稿由本地模板生成，不调用任何在线大模型或翻译服务（只有在线语音合成会发送中文播报稿）。结尾明确告知节目播放完毕。

- 文件：`data/tts/brief-YYYY-MM-DD.txt`、`.aiff`、`.chapters.json`、`.json`，均位于本机数据目录。
- 可在播报条选择音色并试听：云扬、云希（男声），晓晓、晓伊（女声）。自然音色通过 Microsoft Edge 在线语音服务生成，公开播报稿会发送到该服务；无需账号。也可通过配置改回本机 `say`。每章先渲染为 PCM，按真实采样帧拼接成 AIFF；章节起点按帧数累计，使用 `afinfo` 复核总时长。
- 在线自然音色按 `natural_rate` 合成；若网络或合成失败，会保留旧音频并提示重试，不影响日报生成。元数据记录实际音色、语速和时长。同日自动更新与手动重制共用渲染锁。
- 2026-11-06：BBC 中文同时进入环球与外媒栏目，来源明确标为“英国广播公司中文”。本次按用户选择把当前开启的11类栏目都纳入播报，每栏默认3条；节目单中“国内外要闻”“海外新闻”分别成章，海外章按来源轮换并优先保留可播报的 BBC 中文新闻。前几条遇到无法完整中文播报的专名时，继续从同栏目挑选可读条目；长篇正文按原文链接去重，简报头条仍可先报标题。音频侧车 JSON 的 coverage 记录各章实际条目与来源，便于核验，时长随内容量变化。
- App 使用 AVAudioPlayer。支持暂停、拖动带章节刻度的进度条、章节抽屉跳转、0.9x / 1.0x / 1.25x / 1.5x、从头听及按日期记忆进度；切后台继续播放。
- LaunchAgent `com.c.dailydigest.speak` 每 60 秒读取配置，默认 09:10；App 在运行时由 App 的定时器接管。两端共用 POSIX 播放锁与当日已播标记，防止双播。支持计划时间后 30 分钟内补播；当天改时间可重新安排。
- 在今日播报条的「定时」里设置小时、分钟并勾选「每天自动播放」；使用电脑的本地时间。电脑休眠期间不会主动唤醒，恢复后若仍在补播窗口内可补播。
- 配置改变无需重载 launchd。关闭 `tts.enabled` 只关闭自动播放，手动播放仍可用。使用本机 say 时，系统没有中文语音则可到「系统设置 → 辅助功能 → 朗读内容」下载。

```json
{
  "tts": {
    "enabled": true,
    "time": "09:10",
    "rate": 200,
    "engine": "edge",
    "voice": "zh-CN-YunyangNeural",
    "natural_rate": "-6%"
  }
}
```

配置位置：`~/Library/Application Support/DailyDigest/config.json`。`rate` 是渲染起始语速，最终为达到完整节目时长可能自动调整；App 倍速单独保存。既有城市、自定义语速和其它配置在升级时保留。

```bash
python3 ~/Developer/DailyDigest/backend/tts_brief.py --date 2026-10-28
python3 ~/Developer/DailyDigest/backend/tts_brief.py --date 2026-10-28 --ai
python3 ~/Developer/DailyDigest/backend/speak_brief.py --force --dry-run
```

自然语音环境首次安装或修复时，在项目目录运行 `./setup_tts.sh`；选择新音色后 App 会异步重制所选日期的节目。网络不可用时已有音频仍可播放。

`--dry-run` 严格只读，不发声、不生成稿件、不写已播标记；`--force` 可测试当前音频播放，仍遵守互斥锁。真实到点测试可把 `tts.time` 临时改为两分钟后的 HH:mm，测试后恢复原配置。

## 每日邮件

`backend/send_email.py` 读取当天的日报 JSON + 一日简报，渲染一封内联 CSS 的 HTML 邮件（640px，暖色品牌头部、简报 + 💡 机会信号、TOP5、栏目精选）。政策条目会额外显示「与谁有关」，纯文本版本同步包含机会信号。

配置：`~/.config/dailydigest/email.json`（模板见 `backend/email.example.json`）

SMTP 方式：

```json
{
  "method": "smtp",
  "enabled": true,
  "to": ["you@example.com"],
  "from": "行星日报 <digest@example.com>",
  "subject": "行星日报 · {date}",
  "smtp": {
    "host": "smtp.example.com",
    "port": 465,
    "username": "digest@example.com",
    "password": "授权码或密码",
    "ssl": true
  }
}
```

Mail.app 方式（本机 Mail 已配好账号）：

```json
{
  "method": "mailapp",
  "to": ["you@example.com"],
  "subject": "行星日报 · {date}",
  "mailapp": { "send": true }
}
```

命令：

```bash
python3 backend/send_email.py              # 发送今天（没有则最近一期）
python3 backend/send_email.py --date 2026-10-24
python3 backend/send_email.py --dry-run    # 只生成 reports/email-YYYY-MM-DD.html
```

未配置或发送失败时只写日志（`~/Library/Logs/DailyDigest/email.log`），不会影响日报生成。定时任务每天 09:30 运行，留出 09:00 全量生成的余量。

## 自动生成

LaunchAgent：

```text
~/Library/LaunchAgents/com.c.dailydigest.generate.plist
~/Library/LaunchAgents/com.c.dailydigest.email.plist
~/Library/LaunchAgents/com.c.dailydigest.speak.plist
```

每天 4 个时间点执行生成：

```text
09:00  全量生成（含今日专题、一日简报、机会信号、所有栏目 AI 解读、播报稿和音频）
12:00  滚动增量
16:00  滚动增量
20:00  滚动增量
```

定时任务带 `--scheduled` 参数：`run_generate.sh` 在非 09:00 时段自动设置 `DIGEST_ROLLING=1`，进入滚动增量模式——保留当天已解读的条目（含解读文字），只为新增条目调 AI，栏目条目上限放宽到 limit + 2，今日专题沿用早间的版本。条目总数不变时，一日简报也沿用，省一次 AI 调用。如果增量运行时当天还没有数据（比如上午才开机），会自动退化为全量生成。App 内点击“立即更新”或手动运行脚本仍是全量。

语音定时任务 `com.c.dailydigest.speak` 使用 `StartInterval=60` 每分钟轮询，脚本自己校验 `tts.time`、`tts.enabled` 和当天是否已播；因此修改 `config.json` 后不需要重载 launchd。播放前会检测 `行星日报.app` 是否在运行：App 在跑就跳过 `afplay`，交给 App 内定时器，避免两个声音同时响。

生成日志：

```text
~/Library/Application Support/DailyDigest/logs/generate-YYYY-MM-DD.log
```

生成脚本会用 `caffeinate` 在抓取和 AI 解读期间阻止空闲睡眠，避免任务被系统挂起。如果触发时间 Mac 在睡眠，launchd 通常会在唤醒后补跑一次（按当时小时自动判断全量/增量）。也可以手动触发：

```bash
launchctl kickstart -k "gui/$(id -u)/com.c.dailydigest.generate"
launchctl kickstart -k "gui/$(id -u)/com.c.dailydigest.email"
launchctl kickstart -k "gui/$(id -u)/com.c.dailydigest.speak"
```

首次加载 LaunchAgent（如果还没加载）：

```bash
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.c.dailydigest.generate.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.c.dailydigest.email.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.c.dailydigest.speak.plist
```

更省事的方式：在 Finder 里双击项目根目录的 `setup_schedule.command`，它会检查并加载三个任务，然后打印状态。加载失败时窗口不会立刻关闭，方便看报错。

## AI 解读

默认使用本机已登录的 OpenCode CLI 和模型：

```text
opencode/deepseek-v4.1-flash-free
```

生成时按栏目调用一次模型，让模型只根据抓到的标题/摘要写中文标题、干货和解读（政策栏目额外写「与谁有关」）；栏目完成后再调用一次生成今日专题，然后生成一日简报（含机会信号），最后由 `tts_brief.py` 把全部栏目、完整简报、TOP5、天气、周回顾和机会信号整理成分章节口语播报稿。播报不固定字数或时长，优先覆盖可核实的中文条目。模型失败、超时或输出无法解析时，会退回本地摘要、栏目通用解读、本地专题、本地简报和本地播报稿，音频服务不可用时保留已有音频并提示。

临时关闭 AI：

```bash
DIGEST_AI=0 ~/Developer/DailyDigest/backend/run_generate.sh
```

换模型：

```bash
DIGEST_MODEL="provider/model" ~/Developer/DailyDigest/backend/run_generate.sh
```

只重新生成某个栏目（会保留其他栏目和已有专题）：

```bash
DIGEST_ONLY=health ~/Developer/DailyDigest/backend/run_generate.sh
```

注意：AI 可能会误读或遗漏原文信息，卡片保留“阅读原文”链接；健康和金融栏目尤其应以原文和专业意见为准。

## 数据源与抓取覆盖

来源由 `backend/generate.py` 的 `FEEDS` 管理；官方列表解析由 `backend/source_pages.py` 管理。现有栏目采用中新网、英国广播公司中文、德国之声中文、法广、金融时报中文网、日经中文、纽约时报中文、第一财经、界面新闻、量子位、InfoQ中文、极客公园、开源中国、Solidot、IT之家、少数派、爱范儿、机核、巴哈姆特，以及政府与部委公开列表页。

- 默认页面跨天后跟随最新已生成日报；手动打开历史日期则保持该日期。解决长期打开应用后仍停在旧日报的问题。
- 每个来源记录 HTTP/网络结果、可解析条目与缺少日期/未满足中文要求的数量；栏目 JSON 的 `coverage` 保存本轮覆盖情况，App 栏目页显示“信源覆盖 x/y”和异常来源。
- RSS 2.0、RSS 1.0/RDF、Atom 均可解析，每源最多读取120条；同一轮中共享的来源只下载一次，下次更新重新联网抓取。
- 每栏每轮默认选取12条，合并当天之前收录的去重新闻，默认每日最多60条；不再滚动覆盖成仅剩5至8条。新的一天不会把昨天的内容伪标为新抓取。新闻自身发布时间始终保留。
- 专业栏目对综合站点做相关性筛选，避免用社会或数码杂讯填满人工智能、体育、健康、游戏与开源栏目。
- 只有明确标注的广告/推广被过滤；新闻中谈到广告收入、事故等事实不会因此误删。
- 已有本机代理按实际来源逐项验证；不依赖某一个外媒域名的探针，也不改系统网络设置。失败时继续其他源，并明确显示覆盖缺口。同日抓取失败保留已发布内容。

可在本机 `config.json` 调整采集数量，播报每栏条数仍由原有 `broadcast.max_items_per_module` 独立控制：

```json
{"collection": {"per_update_limit": 12, "daily_limit": 60}}
```

## 构建应用

只需要 macOS 自带的 Swift 命令行工具，不需要完整 Xcode：

```bash
~/Developer/DailyDigest/build.sh
```

脚本会：

1. 编译 `app/Sources/*.swift`（包含 `TTSPlayer.swift`，链接 AVFoundation），先输出项目 `build/行星日报.app`；
2. 组装 `~/Applications/行星日报.app`；
3. 做 ad-hoc 签名；
4. 使用 `app/Resources/AppIcon.icns` 作为图标；
5. 把桌面快捷方式换成指向新 App 的符号链接。设置 `DAILYDIGEST_BUILD_ONLY=1` 可仅编译而不安装。

重新生成图标：

```bash
cd ~/Developer/DailyDigest/app/Resources
./build_icon.sh
```

共享的原生矢量路径会分别渲染完整 macOS 图标尺寸，输出 `AppIcon.png`、`AppIcon.icns` 及小尺寸预览。系统图标编码器不可用时使用标准 ICNS PNG 容器，并用系统 `iconutil` 反向解包验证。

## 关闭旧的单独日报任务

新任务已经接管开源栏目。旧的 `com.c.opensource.daily` 已经停用，原来的 plist 改名为 `.disabled`，避免每天重复抓取和重复通知：

```text
~/Library/LaunchAgents/com.c.opensource.daily.plist.disabled
```

旧的报告仍保留在 `~/Library/Application Support/OpenSourceDaily/`，没有删除。需要恢复时，把 `.disabled` 后缀去掉并重新 bootstrap 即可。

## 隐私与边界

- 应用只读取本地 JSON；抓取和 AI 调用由后台脚本完成。
- 抓取的是公开 RSS/API；AI 调用会把候选标题和摘要发送给 OpenCode 所配置的模型提供商。生成语音播报稿时，也会把当天全部栏目、简报、TOP5、天气及本周公开归档重点发给同一模型。
- 使用自然音色时，播报稿逐章发送到 Microsoft Edge 在线语音服务；生成后的音频保存在本机。设置 `engine: "say"` 并选择本机语音可改回离线合成。
- 数据保存在本机；邮件只通过你配置的 SMTP / 本机 Mail 发出，配置里的密码只存在本机。
- 天气来自 open-meteo，只发送经纬度。
- 经济内容不构成投资建议；健康内容不构成医疗建议；政策内容仅为信息梳理，不构成官方解读。

抓取回归验证：`python3 -m unittest discover -s tests -p test_source_reliability.py`；跨天刷新验证：`bash tests/run_store_refresh.sh`。
