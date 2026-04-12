#!/usr/bin/env -S uv run --script
# /// script
# dependencies = []
# ///
"""
Pipeline 信号计算脚本
比较决策日 (D日) 的预测与实际结果 (D+1日)，计算准确率信号

用法:
    calc-signals.py --state data/reports/2026-03-20/state.json --eval-date 2026-03-21
"""

import argparse
import json
import sys
import re
import urllib.request
import urllib.error
from urllib.parse import urlencode
import os

API_BASE_URL = os.environ.get("ASHARE_API_URL", "http://127.0.0.1:8000")


def eprint(*args, **kwargs):
    """输出到 stderr"""
    print(*args, file=sys.stderr, **kwargs)


def api_get(endpoint, params=None):
    """调用 API 并返回 JSON 数据"""
    url = f"{API_BASE_URL}{endpoint}"
    if params:
        query = urlencode(params, safe=',')
        url = f"{url}?{query}"
    
    try:
        req = urllib.request.Request(url, method='GET')
        req.add_header('Accept', 'application/json')
        
        with urllib.request.urlopen(req, timeout=30) as response:
            data = response.read().decode('utf-8')
            return json.loads(data)
    except urllib.error.HTTPError as e:
        eprint(f"API HTTP Error: {e.code} {e.reason} for {url}")
        if e.code == 404:
            return None
        return None
    except Exception as e:
        eprint(f"API Error: {e} for {url}")
        return None


def get_market_emotion(date):
    """获取单日市场情绪数据"""
    return api_get(f"/market-emotion/daily/{date}")


def get_theme_emotion_daily(date, theme_name=None):
    """获取单日题材情绪列表"""
    params = {'trade_date': date, 'limit': 200}
    data = api_get('/theme-emotion/daily', params)
    if data is None or not isinstance(data, list):
        return None
    
    if theme_name:
        for item in data:
            if item.get('theme_name') == theme_name:
                return item
        return None
    return data


def get_kline_daily(code, days=2):
    """获取个股 K 线数据"""
    return api_get(f"/kline/daily/{code}", {'days': days})


def get_stock_change_pct(code, date):
    """获取个股指定日期的涨跌幅"""
    kline = get_kline_daily(code, days=5)
    if not kline or not isinstance(kline, list):
        return None
    
    for item in kline:
        if item.get('date') == date:
            return item.get('change_pct')
    return None


def infer_emotion_stage(market_data):
    """
    根据市场数据推断情绪周期阶段
    阈值参考:
    - 冰点期: 涨停<40, 跌停>10
    - 启动期: 封板率>65%, 晋级率100%
    - 高潮期: 涨停>100, 连板股>20
    - 退潮期: 涨停骤降>30%, 炸板率>50%
    """
    if not market_data:
        return None
    
    limit_up = market_data.get('limit_up_count', 0) or 0
    limit_down = market_data.get('limit_down_count', 0) or 0
    seal_rate = market_data.get('seal_rate', 0) or 0
    blowup_rate = market_data.get('blowup_rate', 0) or 0
    
    # 晋级率计算
    promo_2to3_total = market_data.get('promotion_2to3_total', 0) or 0
    promo_2to3_success = market_data.get('promotion_2to3_success', 0) or 0
    promo_3to4_total = market_data.get('promotion_3to4_total', 0) or 0
    promo_3to4_success = market_data.get('promotion_3to4_success', 0) or 0
    
    promo_rate = None
    if promo_2to3_total > 0 and promo_3to4_total > 0:
        total = promo_2to3_total + promo_3to4_total
        success = promo_2to3_success + promo_3to4_success
        promo_rate = success / total if total > 0 else None
    
    # 判断逻辑
    # 冰点期
    if limit_up < 40 and limit_down > 10:
        return "冰点期"
    
    # 高潮期
    if limit_up > 100:
        board_ge_2 = market_data.get('board_ge_2_count', 0) or 0
        if board_ge_2 > 20:
            return "高潮期"
    
    # 退潮期
    if blowup_rate > 0.5:
        return "退潮期"
    
    # 启动期
    if seal_rate > 0.65 and promo_rate == 1.0:
        return "启动期"
    
    # 修复期（介于冰点和启动之间）
    if seal_rate > 0.65 and limit_up > 60:
        return "修复期"
    
    # 震荡期/过渡期
    return "震荡期"


def calc_signal_a(recommended_stocks, eval_date):
    """
    计算个股预测准确率 (Signal A)
    - signal="买入/加仓" + next_day_pct > 0 → correct
    - signal="观望/减仓" + next_day_pct <= 0 → correct
    """
    stocks_result = []
    correct_count = 0
    total_count = 0
    
    for stock in recommended_stocks:
        code = stock.get('code', '')
        name = stock.get('name', '')
        signal = stock.get('signal', '')
        theme = stock.get('theme', '')
        stars = stock.get('stars', '')
        
        if not code:
            continue
        
        next_day_pct = get_stock_change_pct(code, eval_date)
        
        stock_result = {
            'code': code,
            'name': name,
            'signal': signal,
            'theme': theme,
            'stars': stars,
            'next_day_pct': next_day_pct
        }
        
        if next_day_pct is None:
            stock_result['correct'] = None
            stock_result['note'] = '无法获取数据'
        else:
            total_count += 1
            # 判定规则
            is_correct = False
            if '买入' in signal or '加仓' in signal:
                is_correct = next_day_pct > 0
            elif '观望' in signal or '减仓' in signal or '卖出' in signal:
                is_correct = next_day_pct <= 0
            else:
                # 默认规则：有星级推荐视为看多
                is_correct = next_day_pct > 0 if stars else None
            
            stock_result['correct'] = is_correct
            if is_correct:
                correct_count += 1
        
        stocks_result.append(stock_result)
    
    accuracy = correct_count / total_count if total_count > 0 else None
    
    return {
        'description': '推荐个股次日表现',
        'stocks': stocks_result,
        'accuracy': accuracy,
        'correct_count': correct_count,
        'total_count': total_count
    }


def calc_signal_b(top_themes, decision_date, eval_date):
    """
    计算题材预测准确率 (Signal B)
    - attitude 含"看好" + score_change > 0 → correct
    - attitude 含"回避/谨慎" + score_change <= 0 → correct
    - attitude 含"中性" → 不计入准确率
    """
    themes_result = []
    correct_count = 0
    total_count = 0
    
    for theme in top_themes:
        name = theme.get('name', '')
        stage = theme.get('stage', '')
        attitude = theme.get('attitude', '')
        key_stocks = theme.get('key_stocks', [])
        
        if not name:
            continue
        
        # 获取 D 日和 D+1 日的题材情绪数据
        decision_data = get_theme_emotion_daily(decision_date, name)
        eval_data = get_theme_emotion_daily(eval_date, name)
        
        theme_result = {
            'name': name,
            'stage': stage,
            'attitude': attitude,
            'key_stocks': key_stocks
        }
        
        if decision_data and eval_data:
            decision_score = decision_data.get('emotion_score') or decision_data.get('heat_score')
            eval_score = eval_data.get('emotion_score') or eval_data.get('heat_score')
            
            if decision_score is not None and eval_score is not None:
                score_change = eval_score - decision_score
                theme_result['decision_score'] = decision_score
                theme_result['eval_score'] = eval_score
                theme_result['score_change'] = round(score_change, 2)
                
                attitude_lower = attitude.lower()
                
                # 判断是否中性
                if '中性' in attitude:
                    theme_result['correct'] = None
                    theme_result['note'] = '中性态度不计入统计'
                else:
                    total_count += 1
                    is_correct = False
                    
                    if '看好' in attitude or '积极' in attitude:
                        is_correct = score_change > 0
                    elif '回避' in attitude or '谨慎' in attitude or '看空' in attitude:
                        is_correct = score_change <= 0
                    
                    theme_result['correct'] = is_correct
                    if is_correct:
                        correct_count += 1
            else:
                theme_result['score_change'] = None
                theme_result['note'] = '无法计算得分变化'
        else:
            theme_result['score_change'] = None
            theme_result['note'] = '无法获取题材数据'
        
        themes_result.append(theme_result)
    
    accuracy = correct_count / total_count if total_count > 0 else None
    
    return {
        'description': '推荐题材次日表现',
        'themes': themes_result,
        'accuracy': accuracy,
        'correct_count': correct_count,
        'total_count': total_count
    }


def calc_signal_c(emotion_stage, market_data):
    """
    计算情绪周期阶段判断准确率 (Signal C)
    """
    if not market_data:
        return {
            'description': '情绪周期阶段判断',
            'predicted_stage': emotion_stage,
            'actual_indicators': None,
            'inferred_stage': None,
            'correct': None,
            'note': '无法获取市场数据'
        }
    
    actual_indicators = {
        'limit_up': market_data.get('limit_up_count'),
        'limit_down': market_data.get('limit_down_count'),
        'seal_rate': market_data.get('seal_rate'),
        'blowup_rate': market_data.get('blowup_rate'),
        'emotion_score': market_data.get('emotion_score')
    }
    
    inferred_stage = infer_emotion_stage(market_data)
    
    # 简化判定：如果预测阶段和推断阶段一致，则认为正确
    # 或者：如果预测的"启动期/高潮期"对应实际上涨，"冰点期/退潮期"对应实际下跌
    correct = None
    if emotion_stage and inferred_stage:
        # 阶段分组
        bullish_stages = ['启动期', '高潮期', '主升期', '修复期']
        bearish_stages = ['冰点期', '退潮期', '衰退期']
        
        pred_bullish = any(s in emotion_stage for s in bullish_stages)
        pred_bearish = any(s in emotion_stage for s in bearish_stages)
        
        actual_bullish = any(s in inferred_stage for s in bullish_stages)
        actual_bearish = any(s in inferred_stage for s in bearish_stages)
        
        if pred_bullish and actual_bullish:
            correct = True
        elif pred_bearish and actual_bearish:
            correct = True
        elif pred_bullish and actual_bearish:
            correct = False
        elif pred_bearish and actual_bullish:
            correct = False
        elif emotion_stage in inferred_stage or inferred_stage in emotion_stage:
            correct = True
    
    return {
        'description': '情绪周期阶段判断',
        'predicted_stage': emotion_stage,
        'actual_indicators': actual_indicators,
        'inferred_stage': inferred_stage,
        'correct': correct
    }


def calc_bull_bear_eval(bull_points, bear_points, market_data):
    """
    计算多空观点验证
    简化方案：根据市场整体涨跌方向做粗略分类
    """
    # 获取市场综合情绪得分变化作为判断依据
    emotion_score = market_data.get('emotion_score') if market_data else None
    limit_up = market_data.get('limit_up_count') if market_data else None
    limit_down = market_data.get('limit_down_count') if market_data else None
    
    # 判断市场方向
    market_up = False
    market_down = False
    
    if emotion_score is not None:
        market_up = emotion_score > 5  # 假设 5 是中位数
        market_down = emotion_score < 5
    elif limit_up is not None and limit_down is not None:
        market_up = limit_up > limit_down + 20
        market_down = limit_down > limit_up
    
    # 简化分类
    bull_validated = []
    bull_invalidated = []
    bear_validated = []
    bear_invalidated = []
    
    if market_up:
        # 市场上涨，多方观点更可能验证，空方观点更可能证伪
        bull_validated = [f"[市场上涨] {p[:50]}..." if len(p) > 50 else f"[市场上涨] {p}" for p in bull_points[:3]]
        bear_invalidated = [f"[市场上涨] {p[:50]}..." if len(p) > 50 else f"[市场上涨] {p}" for p in bear_points[:3]]
    elif market_down:
        # 市场下跌，空方观点更可能验证，多方观点更可能证伪
        bear_validated = [f"[市场下跌] {p[:50]}..." if len(p) > 50 else f"[市场下跌] {p}" for p in bear_points[:3]]
        bull_invalidated = [f"[市场下跌] {p[:50]}..." if len(p) > 50 else f"[市场下跌] {p}" for p in bull_points[:3]]
    else:
        # 震荡市场，难以判断
        bull_validated = [f"[震荡市-待验证] {p[:50]}..." if len(p) > 50 else f"[震荡市-待验证] {p}" for p in bull_points[:2]]
        bear_validated = [f"[震荡市-待验证] {p[:50]}..." if len(p) > 50 else f"[震荡市-待验证] {p}" for p in bear_points[:2]]
    
    return {
        'bull_validated_points': bull_validated,
        'bull_invalidated_points': bull_invalidated,
        'bear_validated_points': bear_validated,
        'bear_invalidated_points': bear_invalidated,
        'market_direction': 'up' if market_up else ('down' if market_down else 'neutral'),
        'note': '基于市场涨跌方向的粗略分类，详细验证需要 Reflector Agent 定性分析'
    }


def main():
    parser = argparse.ArgumentParser(description='计算 Pipeline 预测信号准确率')
    parser.add_argument('--state', required=True, help='state.json 文件路径')
    parser.add_argument('--eval-date', required=True, help='评估日期 (D+1日)，格式 YYYY-MM-DD')
    
    args = parser.parse_args()
    
    # 读取 state.json
    try:
        with open(args.state, 'r', encoding='utf-8') as f:
            state = json.load(f)
    except Exception as e:
        eprint(f"错误: 无法读取 state.json: {e}")
        sys.exit(1)
    
    decision_date = state.get('trade_date')
    eval_date = args.eval_date
    
    eprint(f"决策日期: {decision_date}")
    eprint(f"评估日期: {eval_date}")
    
    # 获取 D+1 日市场数据
    eprint("正在获取市场数据...")
    market_data = get_market_emotion(eval_date)
    
    if not market_data:
        eprint("警告: 无法获取市场数据，部分信号将为空")
    else:
        eprint(f"  - 涨停: {market_data.get('limit_up_count')}")
        eprint(f"  - 跌停: {market_data.get('limit_down_count')}")
        eprint(f"  - 封板率: {market_data.get('seal_rate')}")
    
    # 计算各信号
    eprint("正在计算 Signal A (个股预测)...")
    signal_a = calc_signal_a(state.get('recommended_stocks', []), eval_date)
    eprint(f"  - 评估个股数: {signal_a['total_count']}")
    eprint(f"  - 准确率: {signal_a['accuracy']}")
    
    eprint("正在计算 Signal B (题材预测)...")
    signal_b = calc_signal_b(state.get('top_themes', []), decision_date, eval_date)
    eprint(f"  - 评估题材数: {signal_b['total_count']}")
    eprint(f"  - 准确率: {signal_b['accuracy']}")
    
    eprint("正在计算 Signal C (情绪阶段)...")
    signal_c = calc_signal_c(state.get('emotion_stage', ''), market_data)
    eprint(f"  - 预测阶段: {signal_c['predicted_stage']}")
    eprint(f"  - 推断阶段: {signal_c['inferred_stage']}")
    eprint(f"  - 判断正确: {signal_c['correct']}")
    
    eprint("正在计算多空观点验证...")
    bull_bear = calc_bull_bear_eval(
        state.get('bull_key_points', []),
        state.get('bear_key_points', []),
        market_data
    )
    eprint(f"  - 市场方向: {bull_bear['market_direction']}")
    
    # 计算总体准确率
    accuracies = []
    if signal_a['accuracy'] is not None:
        accuracies.append(signal_a['accuracy'])
    if signal_b['accuracy'] is not None:
        accuracies.append(signal_b['accuracy'])
    if signal_c['correct'] is not None:
        accuracies.append(1.0 if signal_c['correct'] else 0.0)
    
    overall_accuracy = sum(accuracies) / len(accuracies) if accuracies else None
    
    # 构建输出
    result = {
        'decision_date': decision_date,
        'eval_date': eval_date,
        'signal_a': signal_a,
        'signal_b': signal_b,
        'signal_c': signal_c,
        'bull_bear_eval': bull_bear,
        'overall_accuracy': overall_accuracy
    }
    
    print(json.dumps(result, ensure_ascii=False, indent=2))
    eprint("信号计算完成")


if __name__ == '__main__':
    main()
