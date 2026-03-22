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
│   ├── debaters/
│   │   ├── bull-debater.md             # 看多辩手
│   │   └── bear-debater.md             # 看空辩手
│   ├── judges/
│   │   ├── market-judge.md             # 市场环境裁判
│   │   └── theme-judge.md              # 题材机会裁判
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
│   └── run-analysis.sh                 # Pipeline Conductor 编排脚本
│
├── data/
│   ├── reports/{YYYY-MM-DD}/           # 每日分析报告输出
│   └── memory/                         # 记忆/学习存储
│
├── docs/
│   ├── theory/                         # 情绪周期理论文档
│   ├── design/                         # 设计文档
│   └── requirements/                   # 接口需求文档
│
└── github/                             # 参考项目（只读，不修改）
    ├── TradingAgents/                  # 参考：Agent 团队架构
    ├── chrome-cdp-skill/               # 参考：Skill 架构和 Agent 定义格式
    ├── ashare-platform/                # 参考：数据采集（已部署为独立服务）
    └── pi-mono/                        # 参考：Pi Agent 框架源码
```

## 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| Agent 框架 | Pi (pi-coding-agent) | .md 文件定义 Agent，YAML frontmatter + system prompt |
| LLM | kimi-k2-thinking | 所有 Agent 统一使用此模型 |
| 数据接口 | ashare-platform (FastAPI) | 本地运行 http://127.0.0.1:8000 |
| 深度研究 | chrome-cdp Skill | 催化剂分析师通过 Google/淘股吧/雪球搜索和阅读 |
| 编排 | Shell 脚本 | bin/run-analysis.sh 按 Pipeline 模式调度各 Agent |
| 语言 | Shell (脚本) | Skills 层为 bash curl wrapper |

## 核心依赖

### 运行时依赖

- **Pi CLI** — Agent 运行时，通过 `pi --print --agent <file.md>` 调用
- **ashare-platform** — 数据 API 服务，需在本地 8000 端口运行
- **Chrome 浏览器** — 催化剂分析师通过 chrome-cdp 进行网络搜索（可选，不可用时降级）
- **chrome-cdp Skill** — 安装在 `~/.agents/skills/chrome-cdp/`
- **jq** — JSON 处理
- **curl** — API 调用

### 外部服务

| 服务 | 地址 | 用途 |
|---|---|---|
| ashare-platform API | http://127.0.0.1:8000 | 市场情绪、题材、趋势数据 |
| Kimi API | 远程 | LLM 推理 |

## 约束

### 架构约束

- **不使用 LangChain/LangGraph** — Agent 编排通过 Shell 脚本 + Pi CLI 实现，不引入 Python 框架
- **Agent 间通过文件传递信息** — 每个 Agent 输出 Markdown 文件，下游 Agent 读取上游输出
- **Skills 层只做数据获取** — 不含业务逻辑，业务判断在 Agent 的 system prompt 中
- **github/ 目录只读** — 仅作参考，不修改其中内容

### 运行约束

- **手动触发** — 通过 `bin/run-analysis.sh [YYYY-MM-DD]` 执行，不做定时任务
- **盘后分析** — 设计为收盘后运行，不支持盘中实时分析
- **本地执行** — 在当前主机运行，不部署到远程

### Agent 定义格式

遵循 Pi Agent 的 .md 格式：

```markdown
---
name: agent-name
description: 一句话描述
tools: bash, read
model: kimi-k2-thinking
---

# System Prompt 正文
...
```

### Skill 脚本规范

- 脚本位于 `skills/ashare-data/scripts/`
- 每个脚本是一个 curl wrapper，接收参数、调用 API、返回 JSON
- 使用 `ASHARE_API_URL` 环境变量（默认 http://127.0.0.1:8000）
- 出错时写 stderr 并以非零退出码退出

## Pipeline 流程

```
分析团队（并行）                辩论团队（顺序）              决策
┌──────────────┐
│ 情绪分析师   │──┐
│ 题材分析师   │──┤          ┌─────────────────┐
│ 趋势分析师   │──├── 4份 ──→│ 市场辩论        │
│ 催化剂分析师 │──┘   报告   │ (多→空→裁判)    │
└──────────────┘             │                 │     ┌──────────┐
                             │ 题材辩论 Top3   │────→│ 投资经理 │──→ 最终报告
                             │ (多→空→裁判)    │     └──────────┘
                             └─────────────────┘
```

## 常用命令

```bash
# 运行完整分析 Pipeline
bin/run-analysis.sh 2026-03-21

# 测试 ashare-platform API 连通性
curl -s http://127.0.0.1:8000/health

# 查看某日市场情绪
curl -s http://127.0.0.1:8000/market-emotion/daily/2026-03-21 | jq .

# 单独运行某个 Agent（调试用）
pi --print --agent agents/analysts/emotion-analyst.md "2026-03-21"
```

## 关键设计文档

- `docs/design/agent-team-design.md` — Agent 团队完整设计方案
- `docs/requirements/ashare-platform-api-requirements.md` — 数据接口需求
- `docs/theory/00_情绪周期理论/` — 情绪周期六阶段理论和量化指标
