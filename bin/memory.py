#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["jieba", "rank-bm25"]
# ///
"""Memory storage/retrieval CLI tool with BM25 and jieba tokenization.

基于参考实现 FinancialSituationMemory，增加 JSONL 持久化和中文分词。
"""

import argparse
import json
import os
import sys
from datetime import datetime
from typing import List, Tuple, Optional, Dict, Any

import jieba
from rank_bm25 import BM25Okapi


def default_memory_dir() -> str:
    pita_data_dir = os.environ.get("PITA_DATA_DIR")
    if pita_data_dir:
        return os.path.join(pita_data_dir, "memory")
    return os.path.join(os.path.expanduser("~"), ".local", "share", "PiTradingAgents", "memory")


class PersistentMemory:
    """持久化记忆存储，支持 BM25 检索和 JSONL 持久化。"""

    def __init__(self, role: str, data_dir: Optional[str] = None):
        """初始化记忆系统。

        Args:
            role: 角色名称 (bull, bear, judge, trader)
            data_dir: 数据文件目录
        """
        self.role = role
        self.data_dir = data_dir or default_memory_dir()
        self.jsonl_path = os.path.join(self.data_dir, f'{role}.jsonl')

        # 内存数据结构
        self.dates: List[str] = []
        self.documents: List[str] = []
        self.recommendations: List[str] = []
        self.timestamps: List[str] = []
        self.records: List[Dict[str, Any]] = []
        self.bm25: Optional[BM25Okapi] = None

        # 确保目录存在并加载数据
        os.makedirs(self.data_dir, exist_ok=True)
        self._load_from_disk()

    def _tokenize(self, text: str) -> List[str]:
        """使用 jieba 进行中文分词。

        Args:
            text: 输入文本

        Returns:
            分词后的词列表
        """
        return jieba.lcut(text.strip())

    def _load_from_disk(self) -> None:
        """从 JSONL 文件加载历史数据。"""
        if not os.path.exists(self.jsonl_path):
            self.bm25 = None
            return

        try:
            with open(self.jsonl_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                        self.records.append(record)
                        self.dates.append(record.get('date', ''))
                        self.documents.append(self._build_search_text(record) or record.get('situation', ''))
                        self.recommendations.append(self._build_legacy_recommendation(record))
                        self.timestamps.append(record.get('ts', ''))
                    except json.JSONDecodeError:
                        continue
        except Exception:
            pass

        self._rebuild_index()

    def _rebuild_index(self) -> None:
        """重建 BM25 索引。"""
        if self.documents:
            tokenized_docs = [self._tokenize(doc) for doc in self.documents]
            self.bm25 = BM25Okapi(tokenized_docs)
        else:
            self.bm25 = None

    def _build_search_text(self, record: Dict[str, Any]) -> str:
        """构建用于 BM25 检索的文本。"""
        parts = [
            record.get('market_situation', ''),
            record.get('role_context', ''),
            record.get('query', ''),
            record.get('summary', ''),
            record.get('situation', ''),
        ]
        return '\n'.join(part for part in parts if part).strip()

    def _build_legacy_recommendation(self, record: Dict[str, Any]) -> str:
        """将结构化记录格式化为兼容旧 prompt 的纯文本。"""
        if record.get('recommendation'):
            return record['recommendation']

        sections = []
        if record.get('decision_review'):
            sections.append(f"[Decision Review] {record['decision_review']}")
        if record.get('summary'):
            sections.append(f"[Summary] {record['summary']}")
        if record.get('mistakes'):
            sections.append(f"[Mistakes] {'; '.join(record['mistakes'])}")
        if record.get('improvements'):
            sections.append(f"[Improvements] {'; '.join(record['improvements'])}")
        if record.get('query'):
            sections.append(f"[Query] {record['query']}")
        return ' '.join(sections)

    def store(self, date: str, situation: str, recommendation: str, extra: Optional[Dict[str, Any]] = None) -> None:
        """存储单条记忆到内存和磁盘（同一日期自动覆盖旧记录）。

        Args:
            date: 日期字符串 (YYYY-MM-DD)
            situation: 市场环境描述
            recommendation: 推荐/反思内容
        """
        ts = datetime.now().isoformat()
        record: Dict[str, Any] = {
            'date': date,
            'situation': situation,
            'recommendation': recommendation,
            'ts': ts
        }
        if extra:
            for key, value in extra.items():
                if key not in {'date', 'situation', 'recommendation', 'ts'}:
                    record[key] = value

        search_text = self._build_search_text(record) or situation
        legacy_recommendation = self._build_legacy_recommendation(record) or recommendation

        # 查找是否已有同一日期的记录
        existing_idx = next((i for i, d in enumerate(self.dates) if d == date), None)

        if existing_idx is not None:
            # 覆盖内存中的旧记录
            self.records[existing_idx] = record
            self.dates[existing_idx] = date
            self.documents[existing_idx] = search_text
            self.recommendations[existing_idx] = legacy_recommendation
            self.timestamps[existing_idx] = ts
            # 重写整个 JSONL 文件
            with open(self.jsonl_path, 'w', encoding='utf-8') as f:
                for r in self.records:
                    f.write(json.dumps(r, ensure_ascii=False) + '\n')
        else:
            # 追加新记录
            with open(self.jsonl_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps(record, ensure_ascii=False) + '\n')
            self.records.append(record)
            self.dates.append(date)
            self.documents.append(search_text)
            self.recommendations.append(legacy_recommendation)
            self.timestamps.append(ts)

        # 重建索引
        self._rebuild_index()

    def query(self, situation: str, n: int = 3) -> List[dict]:
        """使用 BM25 检索相似的历史记忆。

        Args:
            situation: 查询的市场环境描述
            n: 返回的最相似结果数量

        Returns:
            相似记忆列表，每项包含 date, situation, recommendation, similarity_score
        """
        if not self.documents or self.bm25 is None:
            return []

        # 分词并获取 BM25 分数
        query_tokens = self._tokenize(situation)
        scores = self.bm25.get_scores(query_tokens)

        # 获取 top-n 索引
        n = min(n, len(scores))
        top_indices = sorted(range(len(scores)), key=lambda i: scores[i], reverse=True)[:n]

        # 归一化分数到 [0, 1]：将 BM25 原始分数线性映射
        min_score = min(scores)
        max_score = max(scores)
        score_range = max_score - min_score

        results = []
        for idx in top_indices:
            normalized_score = (scores[idx] - min_score) / score_range if score_range > 0 else 0
            results.append({
                'date': self.dates[idx],
                'situation': self.records[idx].get('situation', self.documents[idx]),
                'market_situation': self.records[idx].get('market_situation', ''),
                'role_context': self.records[idx].get('role_context', ''),
                'recommendation': self.recommendations[idx],
                'decision_review': self.records[idx].get('decision_review', ''),
                'summary': self.records[idx].get('summary', ''),
                'mistakes': self.records[idx].get('mistakes', []),
                'improvements': self.records[idx].get('improvements', []),
                'query': self.records[idx].get('query', ''),
                'similarity_score': normalized_score,
                'ts': self.timestamps[idx]
            })

        return results

    def format_query_results(self, results: List[dict]) -> str:
        """格式化查询结果为纯文本。

        Args:
            results: query 返回的结果列表

        Returns:
            格式化后的纯文本
        """
        if not results:
            return ''

        lines = []
        for i, rec in enumerate(results, 1):
            lines.append(f'=== 历史经验 {i} (相似度: {rec["similarity_score"]:.2f}, 日期: {rec["date"]}) ===')
            if rec.get('market_situation'):
                lines.append(f'市场情境: {rec["market_situation"]}')
            if rec.get('role_context'):
                lines.append(f'角色上下文: {rec["role_context"]}')
            if rec.get('decision_review'):
                lines.append(f'复盘结论: {rec["decision_review"]}')
            if rec.get('summary'):
                lines.append(f'经验总结: {rec["summary"]}')
            improvements = rec.get('improvements') or []
            if improvements:
                lines.append('改进规则:')
                for item in improvements:
                    lines.append(f'- {item}')
            if rec.get('query'):
                lines.append(f'检索语句: {rec["query"]}')
            if not any([rec.get('market_situation'), rec.get('role_context'),
                        rec.get('decision_review'), rec.get('summary'),
                        improvements, rec.get('query')]):
                lines.append(rec['recommendation'])
            lines.append('')  # 空行分隔

        return '\n'.join(lines)


def cmd_query(args) -> None:
    """执行 query 子命令。"""
    memory = PersistentMemory(args.role, args.data_dir)
    results = memory.query(args.situation, args.n)
    output = memory.format_query_results(results)
    print(output, end='')


def cmd_store(args) -> None:
    """执行 store 子命令。"""
    memory = PersistentMemory(args.role, args.data_dir)
    memory.store(args.date, args.situation, args.recommendation)
    print(f'Stored to {memory.jsonl_path}', file=sys.stderr)


def cmd_store_batch(args) -> None:
    """执行 store-batch 子命令。"""
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f'Error: Invalid JSON input: {e}', file=sys.stderr)
        sys.exit(1)

    if not isinstance(data, list):
        print('Error: Expected JSON array', file=sys.stderr)
        sys.exit(1)

    count = 0
    for item in data:
        role = item.get('role')
        date = item.get('date')
        situation = item.get('situation')
        recommendation = item.get('recommendation')

        if not all([role, date, situation, recommendation]):
            print(f'Warning: Skipping invalid record: {item}', file=sys.stderr)
            continue

        memory = PersistentMemory(role, args.data_dir)
        extra = {
            k: v for k, v in item.items()
            if k not in {'role', 'date', 'situation', 'recommendation'}
        }
        memory.store(date, situation, recommendation, extra=extra)
        count += 1

    print(f'Stored {count} records', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Memory storage/retrieval CLI tool with BM25 and jieba tokenization',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # 检索相似记忆
  python3 bin/memory.py query --role bull --n 3 --situation '冰点期，涨停28家...'

  # 单条存储
  python3 bin/memory.py store --role bull --date 2026-03-21 --situation '...' --recommendation '...'

  # 批量存储（stdin JSON 数组）
  echo '[{"role":"bull","date":"2026-03-21","situation":"...","recommendation":"..."}]' | python3 bin/memory.py store-batch
''')
    parser.add_argument('--data-dir', default=default_memory_dir(), help='数据目录')

    subparsers = parser.add_subparsers(dest='command', help='可用命令')

    # query 子命令
    query_parser = subparsers.add_parser('query', help='检索相似历史记忆')
    query_parser.add_argument('--role', required=True, choices=['bull', 'bear', 'judge', 'trader'],
                              help='角色名称')
    query_parser.add_argument('--n', type=int, default=3, help='返回结果数量 (default: 3)')
    query_parser.add_argument('--situation', required=True, help='查询的市场环境描述')

    # store 子命令
    store_parser = subparsers.add_parser('store', help='存储单条记忆')
    store_parser.add_argument('--role', required=True, choices=['bull', 'bear', 'judge', 'trader'],
                              help='角色名称')
    store_parser.add_argument('--date', required=True, help='日期 (YYYY-MM-DD)')
    store_parser.add_argument('--situation', required=True, help='市场环境描述')
    store_parser.add_argument('--recommendation', required=True, help='推荐/反思内容')

    # store-batch 子命令
    store_batch_parser = subparsers.add_parser('store-batch', help='批量存储记忆（从 stdin 读取 JSON 数组）')

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    if args.command == 'query':
        cmd_query(args)
    elif args.command == 'store':
        cmd_store(args)
    elif args.command == 'store-batch':
        cmd_store_batch(args)


if __name__ == '__main__':
    main()
