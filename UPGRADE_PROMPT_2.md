# 《行星日报》第二版改造任务书（UI 重设计 + 新栏目 + 邮件推送）

## 你的身份

你是一名同时服务过 **Apple News、Flipboard、今日头条** 这类产品的资深中文资讯 App 产品设计师 + 工程师。你对「热点资讯」的视觉语言有本能级的判断：鲜亮但不廉价、热闹但有秩序、信息密度高但不压抑。这一版你要把《干货日报》彻底改名为《行星日报》，并把它从「能看的工具」升级成「想每天打开的资讯产品」。

## 项目现状（先通读再动手）

- 工程根目录：`~/Developer/DailyDigest`（尚未改名，README 里已实现滚动更新：09:00 全量 + 12/16/20 增量）
- 前端：`app/Sources/`（Swift 5 + SwiftUI，纯 swiftc 构建，无 Xcode、无第三方依赖）
- 构建：`~/Developer/DailyDigest/build.sh` → 产出 `~/Applications/干货日报.app`
- 后端：`backend/generate.py`（7 个栏目 RSS + GitHub + OpenCode 免费模型 AI 解读）
- 定时：`~/Library/LaunchAgents/com.c.dailydigest.generate.plist`
- 数据：`~/Library/Application Support/DailyDigest/data/*.json`（按日期，收藏在 favorites.json）

## 任务零：改名为《行星日报》

1. Info.plist 的 CFBundleName / CFBundleDisplayName、App 内标题、侧栏 Logo 文字，全部改为「行星日报」；副标题可用「每天一颗信息星球」这类一句话定位
2. build.sh 产出目录改为 `~/Applications/行星日报.app`，构建完成后自动把 `~/Desktop/干货日报.app`（旧快捷方式）替换为指向新 App 的桌面快捷方式
3. **保留** bundle identifier（com.c.dailydigest）和 `~/Library/Application Support/DailyDigest` 数据目录不动——收藏、归档、历史日报必须原样保留，只改名字不改数据

## 任务一：UI 重设计（核心，参考热点资讯产品）

先去看去学（搜索/回忆均可）：今日头条（栏目色彩系统、大卡片）、Apple News（杂志封面感、彩色 hero）、Flipboard（杂志排版、色块标签）、微博热搜（排名数字、热度标识）、Google News（Full Coverage 聚合感）。取它们共通的「热点感」手法：

1. **主视觉气质**：鲜亮、有热度感。顶部「今日速览」做成杂志封面式的 hero 区——今日简报大标题 + 1-2 条焦点 + 渐变主色横幅（主色建议暖橙红系，如 #FF5A36→#FF9F45，全局只此一处大面积渐变，其他区域克制）
2. **热点榜单**：速览页增加「今日热点 TOP5」——用大号排名数字（01-05）+ 标题 + 来源 + 热度标识，直接抄微博热搜的榜单心智，让用户 10 秒扫完全天最重要的 5 条
3. **栏目色彩系统**：每个栏目一个高饱和但受控的主题色（沿用 JSON 里的 color 字段），用在侧栏图标、卡片左侧 3pt 色条、标签 chip 上——**只做点缀不做大面积**。侧栏栏目分组：「速览 / 环球 / 洞见 / 生活」四组，别一长条平铺
4. **排版修复**（上一版的问题）：标题行高、字重、层级必须统一规范（建立 type scale：hero 28pt bold / 卡片标题 15pt semibold / 正文 13pt regular / 辅助 11pt secondary）；卡片内「干货 / 为什么值得看 / 解读」用带色 chip 小标签区分；来源、时间、热度放卡片底部一行 metadata，等宽字体显示数字
5. **卡片**：圆角 12pt、0.5pt 细描边或极淡阴影、hover 抬升；卡片间距 12pt；页面最大阅读宽度约束，速览单列大卡 + 栏目双列
6. 深浅色模式都好看；保留所有既有功能（收藏、日历、搜索、快捷键、专题跳转、滚动更新无感切换）

**硬约束**：不许破坏现有功能；不引入第三方依赖；每完成一个页面跑一次 `build.sh` 确认编译通过。

## 任务二：新增「环球通讯社」栏目

抓全球几大通讯社/权威媒体的公开 RSS，每天 4-5 条，权重最高（排在侧栏「环球」组第一位）：

- 候选源：Reuters（路透社）、Associated Press、AFP、Bloomberg、CNBC、Financial Times、The Economist、BBC News；RSS 不可用的换可访问镜像/聚合源（如 Google News RSS `https://news.google.com/rss/search?q=site:reuters.com`），抓不到就在日志记录并跳过
- 该栏目走和其他栏目一样的 AI 解读流程，brief 里注明「来源：全球通讯社」

## 任务三：新增「一日简报」

这是全天的总编辑简报，出现在速览页 hero 区下方，内容为：**从今天所有栏目（含环球通讯社）的条目里，跨栏目梳理出全天最重要的 5-8 条**，写成一段 200-300 字的编辑导语 + 要点列表，每条带来源栏目名。用现有的 AI 调用机制生成（复用 build_topic 的模式），失败时用本地降级（按热度取 top N）。同时导出成 `reports/brief-YYYY-MM-DD.md`，供邮件功能使用。

## 任务四：新增「一周」区

在侧栏最下面加「一周」入口（日历/周报图标），内容：

1. **一周热点**：聚合过去 7 天所有日报里收藏/热度最高的条目，按栏目分组列出，标题写明周期
2. **一周天气**：调用免 key 的 open-meteo API（如 `https://api.open-meteo.com/v1/forecast?latitude=39.9&longitude=116.4&daily=temperature_2m_max,temperature_2m_min,weather_code`，城市默认北京，做成配置文件可改），展示未来 7 天最高/最低温和天气图标（用 SF Symbol 映射 weather code）
3. 数据从本地已归档 JSON 聚合，不重复抓取；失败时降级显示「本周数据生成中」

## 任务五：每日邮件推送

每天早上把「一日简报」发到邮箱：

1. 新增 `backend/send_email.py`：读取当日 JSON + 生成的简报 Markdown，渲染成一份**排版良好的 HTML 邮件**（内联 CSS，标题/要点/来源/原文链接，无外部资源，邮件客户端兼容），通过 SMTP 发送
2. SMTP 凭据放在配置文件 `~/.config/dailydigest/email.json`（host/port/ssl/username/authcode/收件人），**我稍后自己填**；代码里未配置或发送失败时只写日志不报错，不影响主流程
3. 新增 LaunchAgent `com.c.dailydigest.email`，每天 **09:30**（全量生成完成后）执行；支持手动测试：`python3 backend/send_email.py --dry-run` 只生成 HTML 不发送
4. 兼容方案：如果检测到系统「邮件」App 已登录账号，也支持通过 AppleScript 走系统邮件客户端发送（二选一，配置文件里 `method: "smtp" | "mailapp"`）

## 验收标准

1. `build.sh` 编译通过；`~/Applications/行星日报.app` 启动正常，Dock 图标为新图标，标题为「行星日报」
2. 打开 App：速览页有杂志感 hero + 热点 TOP5 + 一日简报；侧栏分组清晰；深浅色都好看；收藏/日历/搜索/快捷键全部照旧工作
3. 历史数据仍在（收藏数、归档日期不变）
4. `python3 backend/generate.py` 跑完后 JSON 里出现「环球通讯社」栏目和「一日简报」字段；「一周」页能显示上周回顾和未来 7 天天气
5. `python3 backend/send_email.py --dry-run` 能产出 HTML；填写 SMTP 配置后能真实收到一封测试邮件

按「改名 → UI → 新栏目 → 简报 → 一周 → 邮件」顺序推进，每步编译/运行验证后再进下一步，每步完成汇报进度。
