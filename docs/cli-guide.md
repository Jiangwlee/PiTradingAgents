# PiTrader CLI 使用指南

## 简介

`pi-trader` 是基于 Typer Python CLI 框架构建的 A 股投资分析平台命令行工具，提供友好的用户界面和强大的功能。

**重要**: 本项目已完全移除旧的 `pita` 命令，请只使用 `pi-trader`。

## 安装依赖

```bash
cd /home/bruce/Projects/PiTradingAgents
uv pip install typer
```

## 运行安装脚本

```bash
./install.sh
```

这将：
- 安装 `pi-trader` 到 `~/.local/bin/pi-trader`
- 创建配置目录和数据目录
- 初始化记忆文件
- 检查 Typer 依赖

确保 `~/.local/bin` 在你的 PATH 中（通常在 `~/.bashrc` 中已配置）。

## 基本用法

```bash
# 查看主帮助
pi-trader --help

# 运行分析流程
pi-trader run [DATE]

# 运行复盘反思
pi-trader reflect DATE

# 查询市场数据
pi-trader data <subcommand> [args...]

# 系统诊断
pi-trader doctor
```

## 命令详解

### `run` - 运行分析流程

执行完整的 A 股市场分析 Pipeline，包括情绪周期判断、题材识别、趋势分析和最终决策。

**用法：**
```bash
pi-trader run [OPTIONS] [DATE]
```

**参数：**
- `DATE`（可选）: 交易日期 (YYYY-MM-DD)，不指定则自动获取最近交易日

**选项：**
- `-m, --model TEXT`: 指定 LLM 模型名称
  - 支持：`qwen3.5-35b`, `qwen3.5-27b`, `kimi-k2p5`, `kimi-k2-thinking`
- `--mode [text|stream|json|interactive]`: 运行模式
  - `text`: 默认，输出最终文本
  - `stream`: 人类可读流式输出；`run` 在并行阶段采用 workflow-safe stream，避免多 Agent 混流
  - `json`: 输出 JSON 事件流
  - `interactive`: 进入 Pi TUI（当前仅 `research` 支持）
- `-s, --stages TEXT`: 指定执行阶段，如 `'1,2,3'`；空 = 全部执行

**示例：**
```bash
# 使用默认配置分析最新交易日
pi-trader run 2026-03-24

# 使用 Qwen3.5-35B 模型并流式查看执行过程
pi-trader run --mode stream -m qwen3.5-35b 2026-03-24

# 仅执行阶段 3（题材辩论）
pi-trader run -s 3 2026-03-24

# 组合多个选项（任意顺序）
pi-trader run --mode json -s 1,2,4 -m kimi-k2-thinking 2026-03-24
```

**Pipeline 阶段说明：**
- **阶段 1**: 分析团队并行工作（情绪/题材/趋势/催化剂分析师）
- **阶段 2**: 市场环境辩论（看多→看空→裁判）
- **阶段 3**: 题材机会辩论（对 Top 题材进行多空辩论）
- **阶段 4**: 最终决策（投资经理生成报告）
- **阶段 5**: 状态保存（为次日复盘准备）

### `reflect` - 运行复盘反思（自进化）

对比决策日预测与次日实际结果，生成结构化反思并注入历史经验，实现系统的自进化能力。

**用法：**
```bash
pi-trader reflect [OPTIONS] DATE
```

**参数：**
- `DATE`（必需）: 决策日期 (YYYY-MM-DD)

**选项：**
- `-m, --model TEXT`: 指定 Reflector Agent 使用的 LLM 模型
  - 支持：`qwen3.5-35b`, `qwen3.5-27b`, `kimi-k2p5`, `kimi-k2-thinking`
- `--mode [text|stream|json]`: 运行模式
  - `interactive` 当前不支持，因为反思流程包含多个角色

**示例：**
```bash
# 对 2026-03-20 的决策进行复盘
pi-trader reflect 2026-03-20

# 使用自定义模型并流式查看反思过程
pi-trader reflect --mode stream -m qwen3.5-35b 2026-03-20
```

**自进化机制说明：**
- **步骤 1**: 验证前置条件（检查 state.json）
- **步骤 2**: 计算评估日期（D+1 交易日）
- **步骤 3**: 计算结果信号（Signal A/B/C 准确率）
- **步骤 4**: 获取次日实际市场数据
- **步骤 5**: 调用 Reflector Agent 生成反思（分 4 个角色：bull/bear/judge/trader）
- **步骤 6**: 提取反思结果并存储到记忆库

**记忆角色映射：**
| 角色 | 记忆库 | 用途 |
|------|--------|------|
| bull | `data/memory/bull.jsonl` | 看多辩手历史教训 |
| bear | `data/memory/bear.jsonl` | 看空辩手历史教训 |
| judge | `data/memory/judge.jsonl` | 裁判历史教训 |
| trader | `data/memory/trader.jsonl` | 投资经理历史教训 |

### `data` - 市场数据查询

从 ashare-platform API 获取 A 股市场数据。

**用法：**
```bash
pi-trader data <SUBCOMMAND> [ARGS...]
```

**可用子命令：**

| 子命令 | 说明 | 示例 |
|--------|------|------|
| `emotion` | 单日市场情绪 | `pi-trader data emotion 2026-03-21` |
| `emotion-history` | 市场情绪历史 | `pi-trader data emotion-history 20 2026-03-21` |
| `theme-pool` | 题材池排名 | `pi-trader data theme-pool 2026-03-21 50 theme_rank` |
| `theme-emotion` | 题材情绪排名 | `pi-trader data theme-emotion 2026-03-21 50 score` |
| `theme-emotion-history` | 单题材情绪历史 | `pi-trader data theme-emotion-history "机器人" 20` |
| `theme-stocks` | 题材成分股 | `pi-trader data theme-stocks "机器人" 2026-03-21` |
| `trend-pool` | 趋势池排名 | `pi-trader data trend-pool 2026-03-21 50 rank` |
| `trend-history` | 个股趋势历史 | `pi-trader data trend-history 000001 20` |
| `review` | 市场回顾数据 | `pi-trader data review 2026-03-21` |

### `doctor` - 系统诊断

检查当前配置和依赖项状态，确保所有组件正常工作。

**用法：**
```bash
pi-trader doctor
```

**输出示例：**
```
PITA_HOME=/home/bruce/.local/share/PiTradingAgents
PITA_CONFIG_DIR=/home/bruce/.local/share/PiTradingAgents/config
PITA_DATA_DIR=/home/bruce/.local/share/PiTradingAgents/data
ASHARE_API_URL=http://127.0.0.1:8000

[OK] command found: pi
[OK] command found: jq
[OK] command found: curl
[OK] python venv: /home/bruce/Projects/PiTradingAgents/.venv/bin/python3
[OK] data scripts: /home/bruce/Projects/PiTradingAgents/scripts
[OK] ashare API reachable: http://127.0.0.1:8000
```

## 支持的模型

| 简写名称 | 完整 provider/id | 说明 |
|---------|------------------|------|
| `qwen3.5-35b` | `litellm-local/qwen3.5-35b` | 通义千问 3.5 35B |
| `qwen3.5-27b` | `litellm-local/qwen3.5-27b` | 通义千问 3.5 27B |
| `kimi-k2p5` | `kimi-coding/k2p5` | Kimi K2.5 |
| `kimi-k2-thinking` | `kimi-coding/kimi-k2-thinking` | Kimi K2 Thinking |

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `PITA_HOME` | `$HOME/.local/share/PiTradingAgents` | 项目主目录 |
| `PITA_CONFIG_DIR` | `$PITA_HOME/config` | 配置文件目录 |
| `PITA_DATA_DIR` | `$PITA_HOME/data` | 数据文件目录 |
| `ASHARE_API_URL` | `http://127.0.0.1:8000` | 行情 API 地址 |

## 故障排除

### 问题：Typer 未找到

**解决方案：**
```bash
cd /home/bruce/Projects/PiTradingAgents
uv pip install typer
```

### 问题：API 连接失败

**解决方案：**
```bash
# 检查 ashare-platform 是否运行
curl http://127.0.0.1:8000/health

# 如果不运行，启动服务
cd ~/ashare-platform
./start.sh
```

### 问题：web-operator 不可用

**解决方案：**
`omp web-operator` 不可用时，催化剂分析师会自动降级处理，其他功能不受影响：
```bash
pi-trader run 2026-03-24
```

如需启用深度研究功能：
```bash
# 安装 web-operator Skill 并确保 `omp web-operator` 可执行
omp install skill web-operator
```

### 问题：reflect 命令失败

**症状**: `state.json 不存在`

**原因**: 需要先运行完整的分析 Pipeline 才能执行复盘

**解决方案：**
```bash
# 先运行分析
pi-trader run 2026-03-24

# 再运行复盘（在次日或之后）
pi-trader reflect 2026-03-24
```

## 最佳实践

### 日常分析流程
```bash
# 每日收盘后运行
pi-trader run 2026-03-24

# 次日早上复盘
pi-trader reflect 2026-03-24
```

### 调试特定阶段
```bash
# 仅运行分析团队
pi-trader run -s 1 2026-03-24

# 仅运行市场环境辩论
pi-trader run -s 2 2026-03-24

# 仅运行题材辩论
pi-trader run -s 3 2026-03-24

# 仅运行最终决策
pi-trader run -s 4 2026-03-24
```

### 测试不同模型
```bash
# 使用 Qwen 模型
pi-trader run -m qwen3.5-35b 2026-03-24

# 使用 Kimi 模型
pi-trader run -m kimi-k2-thinking 2026-03-24
```

## 技术细节

### 参数解析
Typer 自动处理参数顺序，以下命令完全等价：
```bash
pi-trader run 2026-03-24 -m qwen3.5-35b -v
pi-trader run -m qwen3.5-35b -v 2026-03-24
pi-trader run -v -s 3 -m qwen3.5-35b 2026-03-24
```

### 错误处理
- 参数格式错误会给出清晰的错误提示
- API 连接失败会显示友好提示
- 脚本执行失败会显示错误代码

### 日志输出
- Verbose 模式 (`-v`) 会实时显示每个 Agent 的推理过程
- 输出带有颜色标记，便于区分不同角色
- JSONL 格式的事件流可用于高级调试

## 开发说明

如需修改 CLI 代码，编辑以下文件：
- `/home/bruce/Projects/PiTradingAgents/cli/app.py` - Typer 应用主程序
- `/home/bruce/Projects/PiTradingAgents/bin/pi-trader` - 入口脚本

重新运行后无需重新安装，直接执行即可生效。

## 相关文档

- [`docs/cli-migration.md`](./cli-migration.md) - CLI 重构说明
- [`docs/CHANGELOG.md`](./CHANGELOG.md) - 版本更新日志
- [`docs/design/agent-team-design.md`](../docs/design/agent-team-design.md) - Agent 团队设计
- [`AGENTS.md`](../AGENTS.md) - 项目架构总览

---

**版本**: 1.1.0  
**更新日期**: 2026-03-25  
**重要**: 本项目已完全移除 `pita` 命令，请使用 `pi-trader`
