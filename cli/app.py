"""
PiTrader CLI - A 股投资分析平台

一个基于多 Agent 协作的 A 股题材交易分析工具，支持：
- 市场分析流程（情绪周期、题材识别、趋势判断）
- 复盘反思与自进化（从历史决策中学习）
- 市场数据查询
- 系统诊断
"""

import os
import subprocess
import sys
import shutil
import requests
from pathlib import Path
from typing import Annotated, Optional

import typer

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.syntax import Syntax

# 初始化 Rich 控制台
console = Console()

# 应用实例
app = typer.Typer(
    name="pi-trader",
    help="A 股投资分析平台 - 基于多 Agent 协作的题材交易分析系统",
    add_completion=False,
)

# 配置常量（从环境变量读取，由 install.sh 设置的包装脚本传入）
PITA_HOME = os.environ.get("PITA_HOME")
PITA_APP_DIR = os.environ.get("PITA_APP_DIR")
PITA_CONFIG_DIR = os.environ.get("PITA_CONFIG_DIR")
PITA_DATA_DIR = os.environ.get("PITA_DATA_DIR")
ASHARE_API_URL = os.environ.get("ASHARE_API_URL", "http://127.0.0.1:8000")

# 验证必需的环境变量
if not PITA_HOME:
    print("[错误] 环境变量 PITA_HOME 未设置", file=sys.stderr)
    print("[错误] 请通过 install.sh 安装", file=sys.stderr)
    sys.exit(1)

# 使用 PITA_APP_DIR（如果设置）或 PITA_HOME
APP_ROOT = Path(PITA_APP_DIR) if PITA_APP_DIR else Path(PITA_HOME)


def _resolve_project_root() -> Path:
    """
    解析项目根目录
    
    部署模式下，代码位于 ~/.PiTradingAgents/
    由 install.sh 设置的环境变量指向正确的位置
    """
    return APP_ROOT


def _run_script(script_name: str, args: list[str], title: str = "") -> None:
    """执行底层 Bash 脚本，带错误处理和输出"""
    project_root = _resolve_project_root()
    script_path = project_root / "bin" / script_name
    
    if not script_path.exists():
        console.print(f"[red]✗ [bold]脚本不存在:[/bold] {script_path}")
        raise typer.Exit(1)
    
    # 设置环境变量
    env = os.environ.copy()
    env["PITA_HOME"] = PITA_HOME
    env["PITA_CONFIG_DIR"] = PITA_CONFIG_DIR
    env["PITA_DATA_DIR"] = PITA_DATA_DIR
    env["ASHARE_API_URL"] = ASHARE_API_URL
    
    try:
        # 执行脚本
        result = subprocess.run(
            [str(script_path)] + args,
            cwd=str(project_root),
            env=env,
            capture_output=False,  # 直接输出到终端
            check=True
        )
        sys.exit(result.returncode)
    except subprocess.CalledProcessError as e:
        console.print(f"[red]✗ [bold]{title}失败[/bold]")
        console.print(f"[dim]错误代码：{e.returncode}[/dim]")
        raise typer.Exit(e.returncode)
    except FileNotFoundError:
        console.print(f"[red]✗ [bold]命令未找到[/bold]")
        raise typer.Exit(1)


# ========== 命令：run ==========

@app.command("run")
def run_analysis(
    date: Annotated[
        Optional[str],
        typer.Argument(help="交易日期 (YYYY-MM-DD)", metavar="DATE")
    ] = None,
    # Options 必须在 Arguments 之后，否则 Typer 会混淆参数顺序
    stages: Annotated[
        Optional[str],
        typer.Option("--stages", "-s", help="指定执行阶段，如 '1,2,3'；空 = 全部执行")
    ] = None,
    model: Annotated[
        Optional[str],
        typer.Option("--model", "-m", help="指定 LLM 模型名称\n支持：qwen3.5-35b, qwen3.5-27b, kimi-k2p5, kimi-k2-thinking")
    ] = None,
    verbose: Annotated[
        bool,
        typer.Option("--verbose", "-v", help="详细输出模式，实时显示 Agent 推理过程")
    ] = False,
):
    """
    运行分析流程
    
    执行完整的 A 股市场分析 Pipeline：
    
    • 阶段 1: 分析团队并行工作（情绪/题材/趋势/催化剂分析师）
    • 阶段 2: 市场环境辩论（看多→看空→裁判）
    • 阶段 3: 题材机会辩论（对 Top 题材进行多空辩论）
    • 阶段 4: 最终决策（投资经理生成报告）
    • 阶段 5: 状态保存（为次日复盘准备）
    
    支持的模型：
      • qwen3.5-35b, qwen3.5-27b → litellm-local/qwen3.5-*
      • kimi-k2p5, kimi-k2-thinking → kimi-coding/k*
    
    示例：
      pi-trader run 2026-03-21
      pi-trader run --model qwen3.5-35b 2026-03-21
      pi-trader run -v -s 3 2026-03-21
    """
    console.print(Panel.fit(
        "PiTrader — A 股题材交易分析",
        subtitle=f"交易日期：{date or '自动获取最近交易日'}",
        border_style="cyan"
    ))
    
    # 构建参数列表（注意：run-analysis.sh 要求 DATE 在最后）
    args = []
    if verbose:
        args.append("-v")
    if stages:
        args.extend(["-s", stages])
    if model:
        args.extend(["-m", model])
    if date:
        args.append(date)
    
    # 执行分析脚本
    _run_script("run-analysis.sh", args, "分析流程")


# ========== 命令：insight ==========

@app.command("insight")
def run_insight(
    date: Annotated[
        str,
        typer.Argument(help="决策日期 (YYYY-MM-DD)", metavar="DATE")
    ],
    # Options 必须在 Arguments 之后，否则 Typer 会混淆参数顺序
    model: Annotated[
        Optional[str],
        typer.Option("--model", "-m", help="指定 Reflector Agent 使用的 LLM 模型\n支持：qwen3.5-35b, qwen3.5-27b, kimi-k2p5, kimi-k2-thinking")
    ] = None,
    verbose: Annotated[
        bool,
        typer.Option("--verbose", "-v", help="详细输出模式，实时显示反思过程")
    ] = False,
):
    """
    运行复盘反思（自进化）
    
    对比决策日预测与次日实际结果，生成结构化反思并注入历史经验：
    
    • 步骤 1: 验证前置条件（检查 state.json）
    • 步骤 2: 计算评估日期（D+1 交易日）
    • 步骤 3: 计算结果信号（Signal A/B/C 准确率）
    • 步骤 4: 获取次日实际市场数据
    • 步骤 5: 调用 Reflector Agent 生成反思（分 4 个角色）
    • 步骤 6: 提取反思结果并存储到记忆库
    
    支持的模型：
      • qwen3.5-35b, qwen3.5-27b → litellm-local/qwen3.5-*
      • kimi-k2p5, kimi-k2-thinking → kimi-coding/k*
    
    示例：
      pi-trader insight 2026-03-20
      pi-trader insight --model qwen3.5-35b 2026-03-20
      pi-trader insight -v 2026-03-20
    """
    console.print(Panel.fit(
        "PiTrader — 复盘反思与自进化",
        subtitle=f"决策日期：{date}",
        border_style="cyan"
    ))
    
    # 构建参数列表（注意：run-reflect.sh 要求 DATE 在最后）
    args = []
    if verbose:
        args.append("-v")
    if model:
        args.extend(["-m", model])
    if date:
        args.append(date)
    
    # 执行反思脚本
    _run_script("run-reflect.sh", args, "复盘流程")


# ========== 命令：data ==========

@app.command("data")
def query_data(
    subcommand: Annotated[
        str,
        typer.Argument(help="子命令", metavar="SUBCOMMAND")
    ],
    args: Annotated[
        list[str],
        typer.Argument(help="子命令参数")
    ] = [],
):
    """
    市场数据查询
    
    从 ashare-platform API 获取 A 股市场数据：
    
    可用子命令：
      emotion              单日市场情绪
      emotion-history      市场情绪历史
      theme-pool           题材池排名
      theme-emotion        题材情绪排名
      theme-emotion-history 单题材情绪历史
      theme-stocks         题材成分股
      trend-pool           趋势池排名
      trend-history        个股趋势历史
      review               市场回顾数据
    
    示例：
      pi-trader data emotion 2026-03-21
      pi-trader data theme-pool 2026-03-21 50 theme_rank
      pi-trader data emotion-history 20 2026-03-21
    """
    console.print(Panel.fit(
        "PiTrader — 市场数据查询",
        subtitle=f"子命令：{subcommand}",
        border_style="cyan"
    ))
    
    # 执行数据脚本（直接调用 bash 脚本）
    # 注意：args 已经包含子命令之后的所有参数，不需要再添加 subcommand
    project_root = _resolve_project_root()
    scripts_dir = project_root / "scripts"
    
    # 映射子命令到实际脚本名
    subcommand_map = {
        "emotion": "fetch-market-emotion.sh",
        "emotion-history": "fetch-market-emotion-history.sh",
        "theme-pool": "fetch-theme-pool.sh",
        "theme-emotion": "fetch-theme-emotion.sh",
        "theme-emotion-history": "fetch-theme-emotion-history.sh",
        "theme-stocks": "fetch-theme-stocks.sh",
        "trend-pool": "fetch-trend-pool.sh",
        "trend-history": "fetch-trend-stock-history.sh",
        "review": "fetch-market-review.sh",
    }
    
    script_name = subcommand_map.get(subcommand)
    if not script_name:
        console.print(f"[red]✗ [bold]未知子命令:[/bold] {subcommand}")
        raise typer.Exit(1)
    
    script_path = scripts_dir / script_name
    
    if not script_path.exists():
        console.print(f"[red]✗ [bold]脚本不存在:[/bold] {script_path}")
        raise typer.Exit(1)
    
    # 设置环境变量
    env = os.environ.copy()
    env["PITA_HOME"] = PITA_HOME
    env["PITA_CONFIG_DIR"] = PITA_CONFIG_DIR
    env["PITA_DATA_DIR"] = PITA_DATA_DIR
    env["ASHARE_API_URL"] = ASHARE_API_URL
    
    try:
        result = subprocess.run(
            ["bash", str(script_path)] + args,
            cwd=str(project_root),
            env=env,
            capture_output=False,
            check=True
        )
        sys.exit(result.returncode)
    except subprocess.CalledProcessError as e:
        console.print(f"[red]✗ [bold]数据查询失败[/bold]")
        console.print(f"[dim]错误代码：{e.returncode}[/dim]")
        raise typer.Exit(e.returncode)
    except FileNotFoundError:
        console.print(f"[red]✗ [bold]命令未找到[/bold]")
        raise typer.Exit(1)


# ========== 命令：doctor ==========

@app.command("doctor")
def system_diagnostic():
    """
    系统诊断
    
    检查当前配置和依赖项状态，确保所有组件正常工作。
    """
    console.print(Panel.fit(
        "PiTrader — 系统诊断",
        border_style="cyan"
    ))
    
    # 执行 doctor 逻辑（内联实现）
    print(f"PITA_HOME={PITA_HOME}")
    print(f"PITA_CONFIG_DIR={PITA_CONFIG_DIR}")
    print(f"PITA_DATA_DIR={PITA_DATA_DIR}")
    print(f"PITA_APP_DIR={_resolve_project_root()}")
    print(f"ASHARE_API_URL={ASHARE_API_URL}")
    print()
    
    for cmd in ["pi", "jq", "curl"]:
        if command := shutil.which(cmd):
            print(f"[OK] command found: {cmd} ({command})")
        else:
            print(f"[MISSING] command not found: {cmd}")
    
    venv_python = f"{_resolve_project_root()}/.venv/bin/python3"
    if os.path.exists(venv_python) and os.access(venv_python, os.X_OK):
        print(f"[OK] python venv: {venv_python}")
    else:
        print(f"[MISSING] python venv: {venv_python}")
    
    scripts_dir = _resolve_project_root() / "scripts"
    if scripts_dir.exists():
        print(f"[OK] data scripts: {scripts_dir}")
    else:
        print(f"[MISSING] data scripts not found (check scripts directory)")
    
    try:
        response = requests.get(f"{ASHARE_API_URL}/health", timeout=3)
        if response.status_code == 200:
            print(f"[OK] ashare API reachable: {ASHARE_API_URL}")
        else:
            print(f"[WARN] ashare API returned status {response.status_code}")
    except Exception as e:
        print(f"[WARN] ashare API unreachable: {ASHARE_API_URL} ({e})")


# ========== 命令：help ==========

@app.command("help")
def show_help(
    command: Annotated[
        Optional[str],
        typer.Argument(help="要查看的帮助命令", metavar="COMMAND")
    ] = None,
):
    """
    显示帮助信息
    
    [dim]示例：[/dim]
      [cyan]pi-trader help[/cyan]              # 主帮助
      [cyan]pi-trader help run[/cyan]         # 特定命令帮助
      [cyan]pi-trader --help[/cyan]           # 等同于 pi-trader help
    """
    if command:
        # 显示特定命令帮助
        console.print(f"\n[bold]命令：{command}[/bold]\n")
        
        # 根据命令类型显示不同的帮助信息
        if command == "run":
            console.print("[dim]运行分析流程的详细帮助将在执行时显示（使用 --help）[/dim]")
        elif command == "insight":
            console.print("[dim]运行复盘反思的详细帮助将在执行时显示（使用 --help）[/dim]")
        elif command == "data":
            console.print("[dim]数据查询的详细帮助将在执行时显示（使用 pi-trader data --help）[/dim]")
        else:
            console.print(f"[yellow]未知命令：{command}[/yellow]")
    else:
        # 显示主帮助（Typer 会自动处理）
        typer.echo(app.get_help(typer.Context(app)))


# ========== 主入口 ==========

def main():
    """CLI 主入口点"""
    app()


if __name__ == "__main__":
    main()
