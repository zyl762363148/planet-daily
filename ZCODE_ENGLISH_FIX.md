# ZCode 指令：行星日报英文夹杂治理（后端管线）

> 项目根目录：`~/Developer/DailyDigest`
> 核心文件：`backend/generate.py`（抓取+AI+翻译，约 2300 行）、`backend/tts_brief.py`（口播生成）、`backend/send_email.py`（邮件版）。
> 运行环境：macOS + 系统 python3；生成进程由 LaunchAgent 定时触发，日志在 `~/Library/Application Support/DailyDigest/logs/`。

## 背景与现状（必须先理解）

1. `generate.py` 的 `call_zhipu()`（约 975 行）用的智谱 Key **已失效**：HTTP 429，错误码 1309「GLM Coding Plan 套餐已到期」。这个 Key 不要再指望。
2. 兜底的 `call_opencode()`（约 1033 行）是 opencode CLI 免费模型，每天约 200 次额度，白天就被耗光，返回码 1。而且它单次调用超时 240 秒——AI 层挂掉时，每个栏目要白白等 4 分钟，一次全量生成拖 30 分钟以上。
3. 结果：`translate_to_chinese()`（约 1174 行）翻译失败后 `return items`「保留原文」，2026-10-30 当天 46 条里 34 条英文标题、28 条英文摘要，直接进 UI 和口播。

## 要做的事（按优先级）

### P0 — AI 熔断，防止生成被拖死
在 `call_ai()` 加全局熔断器：进程内计数器，**连续 2 次** `call_zhipu` 与 `call_opencode` 都失败后，本次进程剩余所有 AI 调用直接返回空串（打一条日志「AI 熔断，本次生成跳过 AI 层」）。这样生成 1 分钟内跑完，而不是 30 分钟。

### P1 — 本地离线翻译兜底（不依赖任何 API Key）
- 用 `pip install ctranslate2 sentencepiece transformers --target <项目venv>`（网络不通时用 `HF_ENDPOINT=https://hf-mirror.com`，pip 源用清华镜像）。
- 下载 Helsinki-NLP/opus-mt-en-zh 模型到 `~/Developer/DailyDigest/models/opus-mt-en-zh/`（走 hf-mirror）。
- 新建 `backend/local_translate.py`：批量翻译函数 `translate_batch(list[dict]) -> list[dict]`，首次加载模型约 3-5 秒，46 条标题+摘要 M4 上几秒翻完。
- 在 `translate_to_chinese()` 里改成三级链：智谱 → opencode → **本地模型**。本地模型永远在线，保证任何情况下都有中文。
- 本地翻译质量一般，够了：只要求标题可读，summary 交给下游 fallback 文案。

### P2 — 宁缺毋滥：翻译失败条目不许播、不许当主角
- `translate_to_chinese()` 结束后遍历一遍：凡是 title 仍不含 CJK 的条目，打标 `"translated": False`。
- `tts_brief.py` 的 `build_ten_chapters()`：`translated: False` 的条目**跳过不播**（播英文是用户最反感的事），并保证跳过后章节仍有内容。
- `send_email.py` / 数据 JSON：保留条目（UI 还能看到），但前端会按「未翻译」角标降级展示（见 UI 指令）。
- 开源栏目特殊处理：GitHub 仓库名（如 `Gathin23/cleanyourtv`）不翻译，改从 item 的 description/README 摘要取中文描述；若仍为空则跳过。

### P3 — 换一个新的免费大模型（可选增强）
- 推荐 ModelScope 魔搭免费 API（`https://api-inference.modelscope.cn/v1/chat/completions`，OpenAI 兼容，每天 2000 次，国内直连）：注册后在 `generate.py` 里把 `call_zhipu` 改造为可配置 base_url/model/key 的通用 `call_llm()`，Key 从环境变量 `DIGEST_LLM_KEY` 读。
- 用户注册好 Key 前不要阻塞 P0-P2 的落地。

## 验收标准
1. 把智谱 Key 环境变量清空、模拟 opencode 失败的情况下，全量生成在 2 分钟内完成。
2. 产出的 `data/YYYY-MM-DD.json` 中，所有条目 title 均「含中文」或「属于开源仓库名且带中文描述」或「translated:false 且不会进入口播」。
3. `tts_brief.py` 生成的口播全文里，连续英文单词（≥3 个连续 ASCII 字母词）出现次数为 0（专名如 GDP、AI 除外，可用白名单）。
4. 手动跑 `python3 backend/generate.py` 与 `python3 backend/tts_brief.py` 各一次验证。
