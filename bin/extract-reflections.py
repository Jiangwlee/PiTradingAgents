#!/usr/bin/env python3
"""从 Reflector Agent 输出中提取 JSON 反思结果，转换为 store-batch 格式。

兼容两种格式：
1. 旧格式：{"reflections": [{role, situation, recommendation}, ...]}
2. 新格式：单角色结构化 JSON，对应一个 role

用法:
  python3 bin/extract-reflections.py <reflection_file> <decision_date> [role]

输出: JSON 数组到 stdout，可 pipe 给 memory.py store-batch
"""

import json
import re
import sys


def main():
    if len(sys.argv) < 3:
        print("用法: extract-reflections.py <reflection_file> <decision_date> [role]", file=sys.stderr)
        sys.exit(1)

    reflection_file = sys.argv[1]
    decision_date = sys.argv[2]
    role_arg = sys.argv[3] if len(sys.argv) > 3 else None

    with open(reflection_file, 'r', encoding='utf-8') as f:
        content = f.read()

    data = None

    # 方法1: 匹配 ```json ... ``` code block
    json_match = re.search(r'```json\s*(.*?)\s*```', content, re.DOTALL)
    if json_match:
        try:
            data = json.loads(json_match.group(1))
        except json.JSONDecodeError:
            pass

    # 方法2: 直接尝试解析整个内容
    if data is None:
        try:
            data = json.loads(content)
        except json.JSONDecodeError:
            pass

    # 方法3: 尝试匹配最外层的大括号块
    if data is None:
        brace_match = re.search(r'\{.*\}', content, re.DOTALL)
        if brace_match:
            try:
                data = json.loads(brace_match.group(0))
            except json.JSONDecodeError:
                pass

    if data is None:
        print('警告: 无法从反思报告中提取有效 JSON', file=sys.stderr)
        sys.exit(0)

    batch = []

    # 旧格式：含 reflections 数组
    if isinstance(data, dict) and isinstance(data.get('reflections'), list):
        reflections = data.get('reflections', [])
        for r in reflections:
            role = r.get('role')
            situation = r.get('situation', '')
            recommendation = r.get('recommendation', '')

            if role and situation and recommendation:
                batch.append({
                    'role': role,
                    'date': decision_date,
                    'situation': situation,
                    'recommendation': recommendation
                })
    # 新格式：单角色结构化对象
    elif isinstance(data, dict) and role_arg:
        market_situation = data.get('market_situation', '')
        role_context = data.get('role_context', '')
        summary = data.get('summary', '')
        query = data.get('query', '')
        situation = market_situation or data.get('situation', '')
        recommendation = summary or query or role_context

        if situation and recommendation:
            batch.append({
                'role': role_arg,
                'date': decision_date,
                'situation': situation,
                'recommendation': recommendation,
                'market_situation': market_situation,
                'role_context': role_context,
                'decision_review': data.get('decision_review', ''),
                'validated_points': data.get('validated_points', []),
                'invalidated_points': data.get('invalidated_points', []),
                'mistakes': data.get('mistakes', []),
                'improvements': data.get('improvements', []),
                'summary': summary,
                'query': query,
            })
    else:
        print('警告: 未识别到支持的反思 JSON 结构', file=sys.stderr)
        sys.exit(0)

    if batch:
        print(json.dumps(batch, ensure_ascii=False))
    else:
        print('警告: 未找到有效的反思记录', file=sys.stderr)


if __name__ == '__main__':
    main()
