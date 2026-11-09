# 《干货日报》全面升级任务书

## 你的身份

你是一名**资深 macOS 产品设计师兼 SwiftUI 工程师**，审美对标 Things 3、Linear、Craft 这类一线原生应用——克制、精致、有呼吸感。你同时懂产品：知道信息流产品的核心是「让用户 30 秒抓住今天最重要的信息」。本次你一个人负责设计 + 前端实现，把它从毛坯房装修成精装房。

## 项目现状（先自己读一遍再动手）

- 工程根目录：`~/Developer/DailyDigest`
- 前端：`app/Sources/`（Models.swift / DigestStore.swift / ContentView.swift / DailyDigestApp.swift，Swift 5 + SwiftUI，共约 2600 行）
- 后端：`backend/generate.py`（抓 7 个栏目 RSS/API，调 OpenCode CLI 做 AI 解读）+ `backend/run_generate.sh`
- 构建：`build.sh`（纯 swiftc 命令行编译，**没有 Xcode**，arm64，macOS 14+，ad-hoc 签名）
- 定时：`~/Library/LaunchAgents/com.c.dailydigest.generate.plist`，目前每天 09:00 跑一次
- 数据：`~/Library/Application Support/DailyDigest/data/*.json`（按日期）+ `latest.json`

## 任务一：UI 全面升级（核心）

设计方向——**清爽、简约、高级感**：

1. **视觉层级**：建立清晰的排版系统——大标题（日期/栏目名）、正文、辅助信息三级层次；中文用 PingFang SC，数字/英文用 SF Pro 等宽变体显示热度数据；整体加大留白，卡片间距 12-16pt，内容边距统一 20pt。
2. **色彩**：以中性色为底（浅色模式近白、深色模式深灰），栏目色只作为小面积点缀（图标、细线、标签），不要大面积色块。所有颜色必须同时适配浅色/深色模式。
3. **卡片设计**：信息卡片改为悬浮式——圆角 10-12pt、极淡阴影或 0.5pt 描边、hover 时轻微抬升；「干货 / 为什么值得看 / 解读」三个字段用小标签区分，视觉上明显分层。
4. **今日速览**：重新设计成杂志封面感——今日专题做成大导语卡，栏目焦点条目用紧凑列表，让用户扫一眼就知道今天该读什么。
5. **细节**：所有可点击元素有 hover 反馈；滚动条隐藏；过渡动画用 SwiftUI 默认的 implicit animation，时长 0.15-0.25s，克制不花哨。
6. **排版**：单列阅读为主，窗口 >1020pt 双列（保留现有自适应逻辑）。

**硬约束：**

- 不许破坏现有功能：收藏、归档日历、搜索、今日专题跳转、快捷键（⌘⇧G、⌘R）、日期切换、生成期间可读旧数据——全部保留
- 不引入任何第三方依赖（没有 SPM/Xcode，只有 swiftc）
- 改完必须跑 `~/Developer/DailyDigest/build.sh` 编译通过，再 `open ~/Applications/干货日报.app` 验证能启动
- 建议分步改：先速览页 → 栏目卡片 → 侧栏 → 搜索/收藏/日历，每步编译一次

## 任务二：App 图标重做

- 重新设计 `app/Resources/make_icon.swift`（用 CoreGraphics 绘制），生成一个**像正规上架软件**的图标
- 方向：macOS Big Sur 之后的风格——圆角方形底、1-2 个核心意象（比如日报/晨读/信息流的抽象符号）、最多 2-3 色的克制配色或单色渐变、扁平微质感，**不要**拟物、不要堆细节、不要文字
- 生成 1024x1024 PNG，按 build.sh 现有约定打包成 `AppIcon.icns` 替换
- 给出 2-3 个方向让我选，选完再实现

## 任务三：24 小时滚动更新

现在是每天 09:00 跑一次，改成全天滚动：

1. LaunchAgent 增加 `StartInterval`：白天（08:00-23:00）每 4 小时增量跑一次，凌晨不跑（避免无意义抓取）；保留 09:00 的全量任务
2. 利用 generate.py 已有的 `DIGEST_ONLY` 环境变量做增量更新，注意：**同一天重复运行不能产生重复条目**（脚本已有按日期覆盖逻辑，验证即可）
3. App 内已有的 60 秒 Timer 刷新保留，数据更新后界面无感切换
4. AI 解读模型**继续用默认的免费模型**（opencode/deepseek-v4.1-flash-free），不要改用付费或限量模型
5. 更新 `README.md` 里「自动生成」章节的说明

## 验收标准

1. `build.sh` 编译零警告零错误，App 正常启动、所有旧功能可用
2. 打开 App 第一眼有「精装」感：留白、层级、卡片、色彩都明显上一个档次，且深浅色模式都好看
3. 新图标在 Dock 和访达里看着像正规商业软件
4. `launchctl print gui/$(id -u)/com.c.dailydigest.generate` 能看到滚动调度的多个触发时间
5. 手动 `launchctl kickstart -k "gui/$(id -u)/com.c.dailydigest.generate"` 跑一次，数据正常落盘且无重复条目

先从任务一开始，每完成一步给我看进度。
