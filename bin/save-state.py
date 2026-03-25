#!/usr/bin/env python3
"""
Pipeline 状态保存脚本
从 data/reports/日期/ 目录读取所有 .md 报告文件，提取关键预测字段，输出结构化 state.json 到 stdout

用法:
    python3 bin/save-state.py <REPORT_DIR> <TRADE_DATE>
"""

import os
import re
import sys
import json
import glob
from pathlib import Path


def eprint(*args, **kwargs):
    """输出到 stderr"""
    print(*args, file=sys.stderr, **kwargs)


def read_file(filepath):
    """读取文件内容，失败返回空字符串"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception as e:
        eprint(f"警告: 无法读取文件 {filepath}: {e}")
        return ""


def extract_emotion_stage(content):
    """从内容提取情绪周期阶段"""
    # 匹配 Markdown 列表项格式: - **情绪周期阶段**: 冰点期
    patterns = [
        r'[-*]\s*\*\*情绪周期阶段\*\*[:：]\s*([^\n\r]+)',
        r'情绪周期阶段[:：]\s*([^\n\r]+)',
    ]
    for pattern in patterns:
        match = re.search(pattern, content)
        if match:
            stage = match.group(1).strip()
            # 清理 Markdown 格式
            stage = re.sub(r'\*+', '', stage)
            return stage
    return ""


def extract_market_env(content):
    """从内容提取市场环境"""
    patterns = [
        r'[-*]\s*\*\*市场环境\*\*[:：]\s*([^\n\r]+)',
        r'市场环境[:：]\s*([^\n\r]+)',
        r'市场环境评级[:：]\s*([^\n\r]+)',
    ]
    for pattern in patterns:
        match = re.search(pattern, content)
        if match:
            env = match.group(1).strip()
            # 清理 Markdown 格式
            env = re.sub(r'\*+', '', env)
            return env
    return ""


def extract_position(content):
    """从内容提取建议仓位"""
    patterns = [
        r'[-*]\s*\*\*建议仓位\*\*[:：]\s*([^\n\r]+)',
        r'建议仓位[:：]\s*([^\n\r]+)',
    ]
    for pattern in patterns:
        match = re.search(pattern, content)
        if match:
            position = match.group(1).strip()
            # 清理 Markdown 格式
            position = re.sub(r'\*+', '', position)
            # 提取百分比数字
            pct_match = re.search(r'(\d+)%', position)
            if pct_match:
                return pct_match.group(0)
            if re.match(r'^\d+$', position):
                return f"{position}%"
            return position
    return ""


def extract_markdown_table(content, section_pattern):
    """从指定部分提取 Markdown 表格"""
    # 找到对应章节
    section_match = re.search(section_pattern, content, re.IGNORECASE)
    if not section_match:
        return [], []
    
    # 从章节开始位置查找表格
    start_pos = section_match.end()
    section_content = content[start_pos:start_pos + 5000]
    
    lines = section_content.split('\n')
    table_lines = []
    in_table = False
    
    for line in lines:
        stripped = line.strip()
        
        if stripped.startswith('|'):
            in_table = True
            table_lines.append(stripped)
        elif in_table:
            if not stripped or stripped.startswith('#'):
                break
            if stripped.startswith('|'):
                table_lines.append(stripped)
    
    return parse_markdown_table(table_lines)


def parse_markdown_table(table_lines):
    """解析 Markdown 表格行"""
    if not table_lines:
        return [], []
    
    # 过滤分隔行
    data_lines = []
    for line in table_lines:
        if not re.match(r'^\|[-:\s|]+$', line):
            data_lines.append(line)
    
    if len(data_lines) < 1:
        return [], []
    
    # 解析表头
    header_line = data_lines[0]
    headers = [cell.strip() for cell in header_line.split('|')[1:-1]]
    
    # 解析数据行
    rows = []
    for line in data_lines[1:]:
        cells = [cell.strip() for cell in line.split('|')[1:-1]]
        if any(cells):
            rows.append(cells)
    
    return headers, rows


def extract_recommended_stocks(content):
    """从内容提取推荐股票列表"""
    stocks = []
    
    headers, rows = extract_markdown_table(content, r'##\s+.*核心标的池')
    
    if not headers or not rows:
        return stocks
    
    # 映射列索引
    col_map = {}
    for i, h in enumerate(headers):
        h_clean = re.sub(r'\*+', '', h).lower().strip()
        if any(k in h_clean for k in ['代码', 'code']):
            col_map['code'] = i
        elif any(k in h_clean for k in ['名称', 'name']):
            col_map['name'] = i
        elif any(k in h_clean for k in ['题材', 'theme']):
            col_map['theme'] = i
        elif any(k in h_clean for k in ['星级', 'stars']):
            col_map['stars'] = i
        elif any(k in h_clean for k in ['信号', 'signal']):
            col_map['signal'] = i
    
    for row in rows:
        if len(row) < 2:
            continue
        
        stock = {
            'code': row[col_map.get('code', 0)] if col_map.get('code', 0) < len(row) else '',
            'name': row[col_map.get('name', 1)] if col_map.get('name', 1) < len(row) else '',
            'theme': row[col_map.get('theme', 2)] if col_map.get('theme', 2) < len(row) else '',
            'stars': row[col_map.get('stars', 3)] if col_map.get('stars', 3) < len(row) else '',
            'signal': row[col_map.get('signal', 4)] if col_map.get('signal', 4) < len(row) else ''
        }
        
        # 清理数据
        stock['code'] = re.sub(r'[^\d]', '', stock['code'])
        stock['name'] = re.sub(r'\*+', '', stock['name']).strip()
        stock['theme'] = re.sub(r'\*+', '', stock['theme']).strip()
        stock['stars'] = ''.join(c for c in stock['stars'] if c in '⭐★')
        stock['signal'] = re.sub(r'\*+', '', stock['signal']).strip()
        
        if stock['code'] or stock['name']:
            stocks.append(stock)
    
    return stocks


def extract_top_themes(content):
    """从内容提取主流题材排名"""
    themes = []
    
    headers, rows = extract_markdown_table(content, r'##\s+.*主流题材排名')
    
    if not headers or not rows:
        return themes
    
    # 映射列索引
    col_map = {}
    for i, h in enumerate(headers):
        h_clean = re.sub(r'\*+', '', h).lower().strip()
        if any(k in h_clean for k in ['名称', 'name', '题材']):
            col_map['name'] = i
        elif any(k in h_clean for k in ['阶段', 'stage']):
            col_map['stage'] = i
        elif any(k in h_clean for k in ['判定', 'attitude']):
            col_map['attitude'] = i
        elif any(k in h_clean for k in ['核心标的', 'key_stocks']):
            col_map['key_stocks'] = i
    
    for row in rows:
        if len(row) < 2:
            continue
        
        key_stocks_raw = row[col_map.get('key_stocks', 3)] if col_map.get('key_stocks', 3) < len(row) else ''
        key_stocks = []
        if key_stocks_raw:
            key_stocks_raw = re.sub(r'\*+', '', key_stocks_raw)
            key_stocks = [s.strip() for s in re.split(r'[/\\,，\s]+', key_stocks_raw) if s.strip()]
        
        theme = {
            'name': row[col_map.get('name', 1)] if col_map.get('name', 1) < len(row) else '',
            'stage': row[col_map.get('stage', 2)] if col_map.get('stage', 2) < len(row) else '',
            'attitude': row[col_map.get('attitude', 4)] if col_map.get('attitude', 4) < len(row) else '',
            'key_stocks': key_stocks
        }
        
        theme['name'] = re.sub(r'\*+', '', theme['name']).strip()
        theme['stage'] = re.sub(r'\*+', '', theme['stage']).strip()
        theme['attitude'] = re.sub(r'\*+', '', theme['attitude']).strip()
        
        if theme['name']:
            themes.append(theme)
    
    return themes


def extract_judge_verdict(content):
    """从市场环境辩论内容提取裁判判定"""
    patterns = [
        r'[-*]\s*\*\*市场环境\*\*[:：]\s*([^\n]+)',
        r'裁判判定.*?[-–—]\s*([^\n]+)',
        r'判定结果[:：]\s*([^\n]+)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)
        if match:
            verdict = match.group(1).strip()
            verdict = re.sub(r'\*+', '', verdict)
            verdict = verdict.split('。')[0]
            return verdict.strip()
    
    return ""


def extract_key_points(content, point_type='bull'):
    """从辩论内容提取核心论据列表"""
    points = []
    
    if point_type == 'bull':
        patterns = [
            r'###?\s*多方核心论据\s*(.+?)(?=###?\s*空方核心论据|###?\s*裁判判定|$)',
            r'多方核心论据\s*(.+?)(?=空方核心论据|裁判判定|$)',
        ]
    else:
        patterns = [
            r'###?\s*空方核心论据\s*(.+?)(?=###?\s*裁判判定|$)',
            r'空方核心论据\s*(.+?)(?=裁判判定|$)',
        ]
    
    for pattern in patterns:
        match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)
        if match:
            section = match.group(1)
            list_items = re.findall(r'(?:^|\n)\s*(?:\d+[\.、]|[-\*])\s*([^\n]+)', section)
            if list_items:
                points = [item.strip() for item in list_items if len(item.strip()) > 5]
            break
    
    return points


def find_final_report(report_path):
    """查找最终报告文件（支持重命名后的文件）"""
    # 优先查找重命名后的文件
    renamed_files = list(report_path.glob('A股题材交易决策-*.md'))
    if renamed_files:
        # 返回最新的文件
        return max(renamed_files, key=lambda p: p.stat().st_mtime)
    # 回退到旧文件名
    old_file = report_path / '07-final-report.md'
    if old_file.exists():
        return old_file
    return None


def collect_reports(report_dir):
    """收集所有报告文件的完整内容"""
    reports = {}
    report_path = Path(report_dir)
    
    key_patterns = [
        '01-emotion-report.md',
        '05a-bull-argument.md',
        '05b-bear-argument.md',
        '05-market-debate.md',
    ]
    
    for pattern in ['06a-bull-*.md', '06b-bear-*.md', '06-theme-debate.md']:
        files = list(report_path.glob(pattern))
        for f in files:
            key_patterns.append(f.name)
    
    for filename in key_patterns:
        filepath = report_path / filename
        if filepath.exists():
            content = read_file(filepath)
            if content:
                reports[filename] = content
    
    # 单独处理最终报告（支持重命名）
    final_report_file = find_final_report(report_path)
    if final_report_file:
        content = read_file(final_report_file)
        if content:
            reports['07-final-report.md'] = content
    
    return reports


def main():
    if len(sys.argv) < 3:
        eprint("用法: python3 save-state.py <REPORT_DIR> <TRADE_DATE>")
        eprint("例如: python3 save-state.py data/reports/2026-03-20 2026-03-20")
        sys.exit(1)
    
    report_dir = sys.argv[1]
    trade_date = sys.argv[2]
    
    eprint(f"正在处理报告目录: {report_dir}")
    eprint(f"交易日期: {trade_date}")
    
    if not os.path.isdir(report_dir):
        eprint(f"错误: 目录不存在 {report_dir}")
        sys.exit(1)
    
    report_path = Path(report_dir)
    
    final_report_file = find_final_report(report_path)
    final_report = read_file(final_report_file) if final_report_file else ""
    market_debate = read_file(report_path / '05-market-debate.md')
    
    state = {
        'trade_date': trade_date,
        'emotion_stage': '',
        'market_env': '',
        'position': '',
        'top_themes': [],
        'recommended_stocks': [],
        'bull_key_points': [],
        'bear_key_points': [],
        'judge_verdict': '',
        'reports': {}
    }
    
    if final_report:
        state['emotion_stage'] = extract_emotion_stage(final_report)
        state['market_env'] = extract_market_env(final_report)
        state['position'] = extract_position(final_report)
        state['recommended_stocks'] = extract_recommended_stocks(final_report)
        state['top_themes'] = extract_top_themes(final_report)
        eprint(f"  - 情绪周期阶段: {state['emotion_stage']}")
        eprint(f"  - 市场环境: {state['market_env']}")
        eprint(f"  - 建议仓位: {state['position']}")
        eprint(f"  - 推荐标的数: {len(state['recommended_stocks'])}")
        eprint(f"  - 主流题材数: {len(state['top_themes'])}")
    
    if market_debate:
        state['judge_verdict'] = extract_judge_verdict(market_debate)
        state['bull_key_points'] = extract_key_points(market_debate, 'bull')
        state['bear_key_points'] = extract_key_points(market_debate, 'bear')
        eprint(f"  - 裁判判定: {state['judge_verdict']}")
        eprint(f"  - 多方论据数: {len(state['bull_key_points'])}")
        eprint(f"  - 空方论据数: {len(state['bear_key_points'])}")
    
    state['reports'] = collect_reports(report_dir)
    eprint(f"  - 收集报告文件数: {len(state['reports'])}")
    
    print(json.dumps(state, ensure_ascii=False, indent=2))
    
    eprint("状态提取完成")


if __name__ == '__main__':
    main()
