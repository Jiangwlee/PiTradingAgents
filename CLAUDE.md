# PiTradingAgents

A股题材交易分析 Agent 团队。基于 Pi Agent 框架，通过多 Agent 协作完成情绪周期判断、题材深度研究和交易决策。

## 目录结构

```
PiTradingAgents/
├── CLAUDE.md                           # 本文件
├── agents/                             # Agent 定义（Pi .md 格式）
│   ├── analysts/
│   │   ├── emotion-analyst.md          # 情绪分析师 — 判断情绪周期阶段
│   │   ├── theme-analyst.md            # 题材分析师 — 识别主流题材和阶段
│   │   ├── trend-analyst.md            # 趋势分析师 — 筛选核心交易标的
│   │   └── catalyst-analyst.md         # 催化剂分析师 — 深度研究题材驱动力
│   ├── researchers/
│   │   └── stock-researcher.md         # 个股研究员 — 5轮分层淘汰深度研究走强个股
│   ├── debaters/
│   │   ├── bull-debater.md             # 看多辩手
│   │   └── bear-debater.md             # 看空辩手
│   ├── judges/
│   │   ├── market-judge.md             # 市场环境裁判
│   │   └── theme-judge.md              # 题材机会裁判
│   ├── reflection/
│   │   ├── reflector.md                # Reflector Agent — 4步反思框架
│   │   └── experience-injector.md      # 经验注入研究员 — 研究验证用户经验
│   └── decision/
│       └── investment-manager.md       # 投资经理 — 生成最终报告
│
├── skills/
│   └── ashare-data/                    # 数据采集 Skill
│       ├── SKILL.md
│       ├── scripts/                    # curl wrapper 脚本，调用 ashare-platform API
│       └── references/                 # 情绪周期理论、API 文档
│
├── bin/
│   ├── pi-trader                       # CLI 入口（uv run --script + Typer）
│   ├── run-analysis.sh                 # Pipeline Conductor 编排脚本
│   ├── run-research.sh                 # 个股深度研究编排脚本
│   ├── run-reflect.sh                  # 复盘编排脚本（信号计算→反思→记忆写入）
│   ├── run-inject.sh                   # 经验注入编排脚本（研究验证→记忆写入）
│   ├── memory.py                       # BM25+jieba 记忆存储/检索 CLI
│   ├── save-state.py                   # Pipeline 状态保存（提取预测字段为 state.json）
│   ├── calc-signals.py                 # 结果信号计算（比较预测 vs 实际涨跌）
│   ├── extract-reflections.py          # 从 Reflector 输出提取 JSON 反思结果
│   ├── extract-picks.py                # 从最终报告提取荐股列表
│   ├── update-signals.py               # 信号库评分更新与条件轮换
│   └── lib/                            # 共享 Shell 函数库（pi-runner.sh）
│
├── scripts/                            # 数据获取脚本（ashare API + THS 排行 + 问财涨幅榜）
│
├── data/                               # 已废弃，不存在；数据在 ~/.local/share/PiTradingAgents/
│
├── docs/
│   ├── theory/                         # 情绪周期理论文档
│   ├── design/                         # 设计文档
│   └── requirements/                   # 接口需求文档
│
└── github/                             # 参考项目（只读，不修改）
    ├── TradingAgents/                  # 参考：Agent 团队架构
    ├── chrome-cdp-skill/               # 浏览器自动化参考项目（只读）
    ├── ashare-platform/                # 参考：数据采集（已部署为独立服务）
    └── pi-mono/                        # 参考：Pi Agent 框架源码
```

## 数据根目录

所有运行时数据（报告、记忆库、信号等）存储在：

```
~/.local/share/PiTradingAgents/
├── reports/{YYYY-MM-DD}/   # 每日分析报告输出（pi-trader run 结果）
├── memory/                 # 角色记忆库（BM25 检索）
│   ├── bull.jsonl
│   ├── bear.jsonl
│   ├── judge.jsonl
│   └── trader.jsonl
├── research/               # 个股深度研究输出（pi-trader research 结果）
└── signals/                # 复盘信号数据
```

项目内 `data/` 目录已废弃，不再使用。

## 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| Agent 框架 | Pi (pi-coding-agent) | .md 文件定义 Agent，YAML frontmatter + system prompt |
| LLM | qwen3.5-35b | 所有 Agent 统一使用此模型 |
| 数据接口 | ashare-platform (FastAPI) | 本地运行 http://127.0.0.1:8000 |
| 外部数据 | THS 排行 + 问财涨幅榜 | 连续上涨/持续放量/量价齐升/60-240日涨幅 Top 50 |
| 深度研究 | web-operator Skill (`omp web-operator`) | 催化剂分析师通过 Google/淘股吧/雪球搜索和阅读 |
| 编排 | Shell 脚本 | bin/run-analysis.sh 按 Pipeline 模式调度各 Agent |
| 语言 | Shell (脚本) | Skills 层为 bash curl wrapper |
| 记忆检索 | BM25 + jieba | bin/memory.py，中文分词语义匹配历史教训 |
| Python 包管理 | uv (inline script) | 每个 .py 脚本通过 `uv run --script` + inline deps 自管理依赖 |

## 核心依赖

### 运行时依赖

- **Pi CLI** — Agent 运行时，通过 `pi --print --agent <file.md>` 调用
- **ashare-platform** — 数据 API 服务，需在本地 8000 端口运行
- **Chrome 浏览器** — `omp web-operator` 连接本地浏览器进行网络搜索（可选，不可用时降级）
- **web-operator Skill** — 安装在 `~/.agents/skills/web-operator/`
- **jq** — JSON 处理
- **curl** — API 调用
- **uv** — Python 脚本通过 `uv run --script` 运行，自动管理依赖（无需手动 venv）

### 外部服务

| 服务 | 地址 | 用途 |
|---|---|---|
| ashare-platform API | http://127.0.0.1:8000 | 市场情绪、题材、趋势数据 |
| LiteLLM (本地) | litellm-local/qwen3.5-35b | LLM 推理 |

## 约束

### 架构约束

- **不使用 LangChain/LangGraph** — Agent 编排通过 Shell 脚本 + Pi CLI 实现，不引入 Python 框架
- **Agent 间通过文件传递信息** — 每个 Agent 输出 Markdown 文件，下游 Agent 读取上游输出
- **Skills 层只做数据获取** — 不含业务逻辑，业务判断在 Agent 的 system prompt 中
- **github/ 目录只读** — 仅作参考，不修改其中内容

### 运行约束

- **手动触发** — 通过 `bin/run-analysis.sh [-v] [YYYY-MM-DD]` 执行，不做定时任务
- **盘后分析** — 设计为收盘后运行，不支持盘中实时分析
- **本地执行** — 在当前主机运行，不部署到远程

### Agent 定义格式

遵循 Pi Agent 的 .md 格式：

```markdown
---
name: agent-name
description: 一句话描述
tools: bash, read
model: qwen3.5-35b
---

# System Prompt 正文
...
```

### Skill 规范

- **SKILL.md** 负责 HOW（脚本路径、参数、返回格式），**Agent .md** 只说明 WHEN
- Pi bash 工具 CWD 是**项目根目录**，脚本调用写完整路径
- 质量要求详见 `docs/design/` 相关文档

#### ashare-data Skill 注意事项

- 所有接口返回**直接 JSON 数组** `[...]`，不要用 `.data` 键访问
- 不要在脚本输出后追加额外 jq 过滤器（脚本已 `jq .`）
- `theme_stage` 字段为英文代码，Agent 写报告时必须翻译为中文六阶段名（early→启动、ferment→发酵、main_rise→主升、climax→高潮、middle→分歧、late→退潮）
- 脚本调用失败时注明"数据获取失败"并继续，不要用 curl 自行重建 API 请求

## Pipeline 流程

```
分析团队（并行）          辩论团队（顺序）         研究          决策
┌──────────────┐
│ 情绪分析师   │──┐
│ 题材分析师   │──┤       ┌────────────────┐
│ 趋势分析师   │──├─4份──→│ 市场辩论        │   ┌──────────┐   ┌──────────┐
│ 催化剂分析师 │──┘  报告 │ (多→空→裁判)   │──→│ 个股研究 │──→│ 投资经理 │──→ 最终报告
└──────────────┘          │ 题材辩论 Top3  │   │ 员 3.5   │   └──────────┘
                          │ (多→空→裁判)   │   └──────────┘
                          └────────────────┘
```

- 阶段 3.5（个股研究员）在题材辩论后执行，读取 02-theme-report + 06-theme-debate + C5 候选池，输出 08-stock-research.md
- 投资经理以研究员"强烈推荐"列表为荐股主要依据
- 阶段 5（save-state.py）在阶段 4 之后自动执行，保存预测字段为 state.json
- 阶段 2/3/4 的 prompt 中会自动注入 BM25 检索的历史经验（bull/bear/judge/trader 四角色分别注入对应记忆）

## 自进化闭环

每日 Pipeline 执行后，通过复盘形成完整的学习闭环：

```
决策日 (D)                          复盘日 (D+1)
┌──────────────────────────┐        ┌──────────────────────────┐
│  Pipeline 正常运行         │        │  bin/run-reflect.sh       │
│  ↓ 阶段 2/3/4 注入记忆     │        │  ① calc-signals.py 计算   │
│  ↓ 阶段 5 保存 state.json │──────→│     Signal A/B/C 准确率   │
└──────────────────────────┘        │  ② Reflector Agent 反思   │
          ↑                         │  ③ memory.py 写入记忆     │
          └────────────────────────-┘                           │
                  历史经验注入                                    │
└──────────────────────────────────────────────────────────────┘
```

### 记忆角色映射

路径相对于数据根目录（`~/.local/share/PiTradingAgents/`）：

| 角色 | 记忆库 | 注入时机 |
|------|--------|---------|
| 看多辩手 | memory/bull.jsonl | 阶段 2/3 bull prompt |
| 看空辩手 | memory/bear.jsonl | 阶段 2/3 bear prompt |
| 市场/题材裁判 | memory/judge.jsonl | 阶段 2/3 judge prompt |
| 投资经理 | memory/trader.jsonl | 阶段 4 final prompt |

### 复盘信号类型

- **Signal A** — 推荐个股次日涨跌 vs 交易信号（买入/观望/回避）的一致性
- **Signal B** — 推荐题材次日情绪得分变化 vs 裁判态度的一致性
- **Signal C** — 预测情绪周期阶段 vs 次日实际量化指标推断阶段的一致性

## 常用命令

```bash
# 运行完整分析 Pipeline
pi-trader run 2026-03-21

# Verbose 模式（实时查看每个 Agent 的推理输出）
pi-trader run -v 2026-03-21

# 指定阶段和模型
pi-trader run -v -s 3 --model qwen3.5-35b 2026-03-21

# 复盘（对比决策日预测与次日实际结果，生成反思并写入记忆）
pi-trader reflect 2026-03-20

# 经验注入（AI 研究验证后写入记忆库）
pi-trader inject "冰点期不要抄底，等跌停家数连续两天缩减再入场"

# 指定角色注入
pi-trader inject --role trader "连板股第三天放量要警惕，大概率是出货"

# 个股深度研究（自动获取7连阳+历史新高，5轮分层淘汰）
pi-trader research

# 指定股票研究（跳过前3轮筛选，直接深度研究）
pi-trader research --stocks 600396,603929

# 市场数据查询
pi-trader data emotion 2026-03-21
pi-trader data theme-pool 2026-03-21 50 theme_rank

# 系统诊断
pi-trader doctor

# 查询角色历史记忆（BM25 语义检索）
bin/memory.py query --role bull --n 3 --situation "冰点期 涨停下降"

# 手动生成 state.json（pipeline 阶段 5 会自动执行）
bin/save-state.py $PITA_DATA_DIR/reports/2026-03-20 2026-03-20 > $PITA_DATA_DIR/reports/2026-03-20/state.json

# 单独运行某个 Agent（调试用）
pi --print --agent agents/analysts/emotion-analyst.md "2026-03-21"

# 测试 ashare-platform API 连通性
curl -s http://127.0.0.1:8000/health
```

## 关键设计文档

- `docs/design/agent-team-design.md` — Agent 团队完整设计方案
- `docs/requirements/ashare-platform-api-requirements.md` — 数据接口需求
- `docs/theory/00_情绪周期理论/` — 情绪周期六阶段理论和量化指标
