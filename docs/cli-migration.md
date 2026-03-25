# CLI 重构指南：从 Bash 到 Python + Typer

## 概述

本项目已完成 CLI 工具的重大升级，将原有的 Bash 实现升级为基于 Python + Typer 的现代化 CLI (`pi-trader`)。

**重要提示**: `pita` 命令已完全移除，请只使用 `pi-trader`。

## 主要改进

### 1. **更友好的用户界面**
- ✅ 自动生成的 Help 信息（无需手动维护）
- ✅ 彩色输出和格式化排版
- ✅ 类型安全的参数验证
- ✅ 优雅的错误提示

### 2. **命令重命名**
| 旧名称 | 新名称 | 说明 |
|--------|--------|------|
| N/A | `run` | 运行分析流程 |
| N/A | `insight` | 运行复盘反思（自进化） |
| N/A | `data` | 市场数据查询 |
| N/A | `doctor` | 系统诊断 |

### 3. **统一参数支持**
所有命令现在都支持统一的选项：
- `--model, -m`: 指定 LLM 模型
- `--verbose, -v`: 详细输出模式
- `--help, -h`: 显示帮助

### 4. **智能参数解析**
Typer 自动处理参数顺序，用户可以使用任意顺序：
```bash
# 以下命令等价
pi-trader run 2026-03-24 -m qwen3.5-35b -v
pi-trader run -m qwen3.5-35b -v 2026-03-24
pi-trader run -v -s 3 -m qwen3.5-35b 2026-03-24
```

## 快速开始

### 安装依赖
```bash
cd /home/bruce/Projects/PiTradingAgents
uv pip install typer
```

### 运行安装脚本
```bash
./install.sh
```

### 基本用法
```bash
# 查看帮助
pi-trader --help

# 运行分析
pi-trader run 2026-03-24

# 运行复盘
pi-trader insight 2026-03-20

# 查询数据
pi-trader data emotion 2026-03-21

# 系统诊断
pi-trader doctor
```

## 命令对照表

### `run` 命令

| 功能 | 用法 | 说明 |
|------|------|------|
| 基础运行 | `pi-trader run 2026-03-24` | 分析最新交易日 |
| 详细模式 | `pi-trader run -v 2026-03-24` | 实时显示推理过程 |
| 阶段选择 | `pi-trader run -s 3 2026-03-24` | 仅执行阶段 3 |
| 多阶段 | `pi-trader run -s 1,2 2026-03-24` | 执行阶段 1 和 2 |
| 指定模型 | `pi-trader run -m qwen3.5-35b 2026-03-24` | 使用 Qwen 模型 |
| 组合选项 | `pi-trader run -v -s 1,2,4 -m kimi-k2-thinking 2026-03-24` | 任意顺序 |

### `insight` 命令

| 功能 | 用法 | 说明 |
|------|------|------|
| 基础复盘 | `pi-trader insight 2026-03-20` | 对决策日进行复盘 |
| 详细模式 | `pi-trader insight -v 2026-03-20` | 实时显示反思过程 |
| 指定模型 | `pi-trader insight -m qwen3.5-35b 2026-03-20` | 使用自定义模型 |

### `data` 命令

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

### `doctor` 命令

| 功能 | 用法 | 说明 |
|------|------|------|
| 系统诊断 | `pi-trader doctor` | 检查配置和依赖状态 |

## 技术架构

### 新架构 (Python + Typer)
```
pi-trader (Python)
├── cli/app.py (Typer)
│   ├── run_analysis() → 调用 run-analysis.sh
│   ├── run_insight() → 调用 run-reflect.sh
│   ├── query_data() → 调用底层脚本
│   └── system_diagnostic() → 调用 doctor 逻辑
└── bin/pi-trader (入口脚本)
```

### 优势
- **自动化 Help**: 从代码注释自动生成，无需手动维护
- **类型安全**: 参数格式自动验证
- **扩展性**: 易于添加新功能
- **可测试性**: Python 单元测试友好
- **用户体验**: 彩色输出、错误提示优化

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

## 常见问题

### Q: 为什么移除了 `pita`？
A: 为了提供更现代化的用户体验，我们完全重写了 CLI，采用 Python + Typer 框架。`pi-trader` 提供了更好的 Help 信息、类型安全和错误提示。

### Q: 需要重新学习吗？
A: 不需要！基本用法与之前类似，只是命令名称变化（`reflect` → `insight`）。新增的 `--model` 和 `-s` 选项让配置更灵活。

### Q: 如果 Typer 未安装怎么办？
A: 运行 `uv pip install typer` 即可。安装脚本会自动检查并提示。

### Q: 如何切换回旧版？
A: 无法切换。`pita` 已完全移除，请全部使用 `pi-trader`。

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

### 问题：Chrome CDP Skill 不可用

**解决方案：**
```bash
# Chrome CDP Skill 不可用时，催化剂分析师会降级处理
# 其他功能不受影响
pi-trader run 2026-03-24
```

## 下一步

1. **阅读完整文档**: [`docs/cli-guide.md`](./cli-guide.md)
2. **尝试新功能**: 使用 `--model` 选项测试不同模型
3. **探索数据查询**: `pi-trader data --help`
4. **反馈建议**: 如有问题或建议，欢迎提交 Issue

---

**版本**: 1.1.0  
**更新日期**: 2026-03-25  
**重要**: `pita` 命令已完全移除，请使用 `pi-trader`
