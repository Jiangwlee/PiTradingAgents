# PiTradingAgents

基于多 Agent 协作的 A 股题材交易分析平台

## 简介

PiTradingAgents 是一个 A 股投资分析系统，采用多 Agent 协作架构，通过情绪周期判断、题材识别、趋势分析和多空辩论，生成投资决策报告。

**核心特性:**
- 🧠 多 Agent 协作（情绪/题材/趋势/催化剂分析师 + 多空辩手 + 裁判 + 个股研究员）
- 📊 六阶段情绪周期理论量化分析
- 💡 自进化机制（复盘反思 + BM25 记忆检索）
- 🔌 集成 ashare-platform 行情数据 API
- 🌐 支持 `omp-web-operator` 深度研究（可选）

## 快速开始

### 安装

```bash
# 1. 克隆仓库
git clone <repository-url> PiTradingAgents
cd PiTradingAgents

# 2. 运行安装脚本
./install.sh

# 3. 确保 PATH 包含 ~/.local/bin
export PATH="$PATH:$HOME/.local/bin"

# 4. 验证安装
pi-trader doctor
```

### 基本使用

```bash
# 1. 确保 ashare-data 服务已启动
curl http://localhost:8000/health  # 应该返回 {"status":"ok"}

# 2. 运行市场分析
pi-trader run 2026-03-24

# 3. 运行复盘反思（在次日执行）
pi-trader reflect 2026-03-23

# 4. 个股深度研究
pi-trader research

# 5. 查询市场数据
pi-trader data emotion 2026-03-24
pi-trader data theme-pool 2026-03-24 50

# 查看帮助
pi-trader --help
pi-trader run --help
```

## 项目结构

```
PiTradingAgents/
├── agents/                 # Agent 定义
│   ├── analysts/          # 分析师（情绪/题材/趋势/催化剂）
│   ├── researchers/       # 个股研究员
│   ├── debaters/          # 多空辩手
│   ├── judges/            # 裁判
│   ├── reflection/        # Reflector Agent + 经验注入
│   └── decision/          # 投资经理
├── bin/                    # 可执行脚本
│   ├── pi-trader          # CLI 入口
│   ├── run-analysis.sh    # 分析 Pipeline
│   ├── run-research.sh    # 个股研究 Pipeline
│   ├── run-reflect.sh     # 复盘 Pipeline
│   └── lib/               # 共享 Shell 函数库
├── skills/                 # Agent Skill 定义
│   └── ashare-data/       # 数据采集 Skill
├── scripts/                # 数据获取脚本
├── docs/                   # 文档
├── install.sh              # 安装脚本
└── README.md              # 本文件
```

## 安装路径

遵循 Linux XDG 标准：

| 内容 | 路径 | 说明 |
|------|------|------|
| 应用代码 | `~/.PiTradingAgents/` | 程序、脚本、虚拟环境 |
| 运行时数据 | `~/.local/share/PiTradingAgents/` | 报告、记忆库、信号 |
| 用户配置 | `~/.config/PiTradingAgents/` | 环境变量配置 |
| 命令入口 | `~/.local/bin/pi-trader` | CLI 命令 |

## 文档

- [安装指南](./docs/installation-guide.md) - 详细安装说明
- [CLI 使用指南](./docs/cli-guide.md) - 完整的命令参考
- [迁移指南](./docs/cli-migration.md) - 从旧版迁移说明
- [更新日志](./docs/CHANGELOG.md) - 版本历史

## 系统要求

- Python 3.12+
- Linux/macOS (Bash)
- **[ashare-platform](https://github.com/Jiangwlee/ashare-platform)** - 行情数据服务（**必需**）
- 可选: Chrome 浏览器（用于深度研究）

### 前置依赖：ashare-platform

**PiTradingAgents 依赖 ashare-platform 提供行情数据，必须先安装并启动服务。**

```bash
# 1. 克隆 ashare-platform
git clone git@github.com:Jiangwlee/ashare-platform.git
cd ashare-platform

# 2. 按照 ashare-platform 的文档启动服务（通常使用 Docker）
docker-compose up -d

# 3. 验证服务是否运行
curl http://localhost:8000/health
```

**注意**: 如果 ashare-platform 未运行，PiTradingAgents 将无法获取市场数据，所有命令都会失败。

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

复盘反思（次日执行）：Signal A/B/C 计算 → Reflector Agent 反思 → 记忆库存储

## 命令

| 命令 | 说明 |
|------|------|
| `pi-trader run [DATE]` | 运行分析 Pipeline |
| `pi-trader research [--stocks CODE,CODE]` | 个股深度研究 |
| `pi-trader reflect [DATE]` | 复盘反思（自进化） |
| `pi-trader inject EXPERIENCE` | 注入交易经验到记忆库 |
| `pi-trader data <sub>` | 查询市场数据 |
| `pi-trader doctor` | 系统诊断 |

### 常用选项

```bash
# 指定模型
pi-trader run -m qwen3.5-35b 2026-03-24

# 详细输出
pi-trader run -v 2026-03-24

# 选择阶段
pi-trader run -s 3 2026-03-24        # 仅阶段 3
pi-trader run -s 1,2 2026-03-24      # 阶段 1+2
```

## 支持的模型

| 名称 | Provider/ID |
|------|-------------|
| qwen3.5-35b | litellm-local/qwen3.5-35b |

更多模型可通过 `~/.config/PiTradingAgents/config.env` 中的 `PITA_DEFAULT_MODEL` 等变量配置。

## 升级

```bash
cd ~/Projects/PiTradingAgents
git pull
./install.sh
```

## 许可证

MIT License
