# 同花顺概念板块成员爬取需求

**文档版本**：v1.1  
**日期**：2026-04-02  
**实现载体**：`omp web-operator` CLI（由 ashare-data 作为子进程调用）  
**数据控制方**：ashare-data（调度、存储、查询全部由 ashare-data 控制）

---

## 1. 背景与目标

### 1.1 为什么需要这份数据

ashare-platform 当前有一个核心缺口：**无法将候选股票与主流题材关联**。

现状（2026-04-01 实测）：
- `red_window_daily` 表：连阳候选股 **306 只**
- `theme_stock_daily` 表：题材-股票映射 **19 只**（仅涵盖当日涨停板上板精选）
- 两表交叉命中：**5 只（1.6%）**

根因：`theme_stock_daily` 只录入了每日涨停行情中出现的股票，不是题材全量成员。

**目标**：建立"题材全量成员表"`theme_member_stock`，覆盖同花顺全部 362 个概念板块的所有成员股，使题材交叉命中率从 1.6% 提升至 80%+。

### 1.2 架构分工

```
ashare-data (fetcher)
  │
  ├─ subprocess: omp web-operator page nav <url>    # 建立 THS 会话
  ├─ subprocess: omp web-operator page eval <js>    # 在浏览器内执行 fetch，返回 JSON
  │
  └─ 解析 stdout → 写入 theme_member_stock 表
```

**ashare-data 负责**：调用时机、参数构造、结果解析、入库、错误重试逻辑  
**omp web-operator 负责**：维护真实浏览器会话、执行 page 操作、将结果输出到 stdout

---

## 2. 数据来源分析

### 2.1 已发现的有效接口（均已通过 Chrome DevTools + eval 验证）

#### 接口 A：题材成员列表（核心接口）

```
GET https://basic.10jqka.com.cn/ajax/stock/conceptlist.php?cid={concept_id}&code=000001
```

**认证方式**：`hexin-v` header（值等于 `v` cookie）  
**响应格式**：JSON  
**验证方式**：在浏览器页面内通过 `fetch(..., {credentials: 'include'})` 调用，返回完整数据

**实测响应结构**（概念 ID 309264，AI应用）：

```json
{
  "errorcode": 0,
  "errormsg": "success",
  "result": {
    "report": "2025-09-30",
    "name": "AI应用",
    "plateid": 886108,
    "listdata": {
      "2025-09-30": [
        [
          "600666",     // [0] 股票代码
          "奥瑞德",      // [1] 股票名称
          "148.09亿",   // [2] 总市值
          "168.39亿",   // [3] 流通市值
          "2.91亿",     // [4] 净利润
          "-2.39",      // [5] 涨跌幅(%)
          "6.12",       // [6] PE(TTM)
          "根据2025年8月26日公司官微：近日，奥瑞德控股子公司...",               // [7] 关联理由（摘要）
          "根据2025年8月26日公司官微：近日，奥瑞德控股子公司深圳市智算力...",   // [8] 关联理由（详细）
          "3",          // [9] 疑似星级或连板数
          4,            // [10] 未知
          25.41,        // [11] 疑似区间涨幅
          "43.422",     // [12] 疑似30/60日涨幅
          "", "", "", "", ""  // [13-17] 未知
        ]
      ]
    }
  }
}
```

**关键发现**：
- AI应用 有 **478 只成员股**，黄金概念 ~30 只，规模差异较大
- `[7]`/`[8]` 字段为该股与概念关联的**文字理由**（公告摘要/互动易内容），是确定 `role_in_theme` 语义的重要依据
- `&code=` 参数仅用于触发接口，传任意有效股票代码（如 `000001`）不影响返回结果

#### 接口 B：概念列表（枚举所有概念 ID）

```
GET https://q.10jqka.com.cn/gn/
```

**认证方式**：无需认证（公开页面，服务端渲染）  
**内容**：包含全部 **362 个**概念板块的 ID 和名称  
**解析方式**（UTF-8 解码后正则提取）：

```python
import re
with open(html_file, 'rb') as f:
    content = f.read().decode('utf-8', errors='replace')
matches = re.findall(r'detail/code/(\d+)/\" target=\"_blank\">([^<]+)</a>', content)
# → [('308614', '阿尔茨海默概念'), ('309121', 'AI PC'), ('309120', 'AI手机'), ...]
```

**关键发现**：`gn/detail/code/{id}` 中的 ID 与 `conceptlist.php?cid={id}` 中的 `cid` **完全是同一套 ID，无需任何映射**。

已验证的 ID 对应关系：

| cid | 概念名称 |
|-----|---------|
| 300248 | 黄金概念 |
| 300733 | 锂电池概念 |
| 301491 | 粤港澳大湾区 |
| 309264 | AI应用 |
| 309263 | 2025年报预增 |
| 301248 | 两轮车 |
| 301175 | 智能穿戴 |

---

### 2.2 为什么必须用 CDP，不能直接 curl

**已测试的失败场景**：

1. **hexin-v 认证无法静态复用**  
   THS 的 `hexin-v` header 由前端 JS 动态生成，绑定 IP + 时间因子。从 DevTools 复制的静态 token 直接 curl 后返回 `Nginx forbidden`（403）。

2. **IPv6 地址被封锁**  
   分页 AJAX 接口（`/gn/detail/field/.../ajax/1/...`）对 IPv6 返回 403。本机 IPv6 地址 `240e:36f:15a1:ff21:e708:4d2f:7b6:ef6` 已被确认封锁。主页面（非 AJAX）不受影响。

3. **频率限制**  
   快速连续请求触发 Nginx 封锁，返回 `<h1>Nginx forbidden.</h1>`。

4. **Cookie 与 hexin-v 需配对**  
   `v` cookie 和 `hexin-v` header 的值相同，必须来自同一真实浏览器会话，单独设置无效。

**结论**：通过 CDP 控制真实 Chrome，在浏览器上下文内执行 `fetch(..., {credentials: 'include'})`，可绕过上述所有限制——浏览器自动附带正确的 cookie 和 hexin-v header。

---

## 3. omp web-operator 集成规格

### 3.1 调用方式

ashare-data 的 fetcher 以 **子进程方式**调用 `omp web-operator`，读取 stdout 获取结果。

#### Step 1：建立 THS 会话（每次任务开始时执行一次）

```bash
omp web-operator page nav https://basic.10jqka.com.cn/000001/concept.html
```

作用：在 CDP 浏览器内导航到 THS 页面，触发 hexin-v 初始化和 cookie 写入。此后该浏览器会话对 `basic.10jqka.com.cn` 域下所有请求自动携带认证信息。

#### Step 2：获取概念列表

```bash
omp web-operator page nav https://q.10jqka.com.cn/gn/
omp web-operator page html
```

`page html` 输出页面 HTML，ashare-data 侧用正则解析 362 个概念 ID + 名称。

#### Step 3：获取单个概念成员（循环调用）

```bash
omp web-operator page eval "
  fetch('https://basic.10jqka.com.cn/ajax/stock/conceptlist.php?cid=309264&code=000001', {
    credentials: 'include',
    headers: { 'Referer': 'https://basic.10jqka.com.cn/000001/concept.html' }
  }).then(r => r.json())
"
```

stdout 为 JSON 字符串，ashare-data 直接 `json.loads()` 解析。

**Python 封装示例**（ashare-data 侧）：

```python
import subprocess, json

def fetch_concept_members(concept_id: str) -> dict:
    js = f"""
    fetch('https://basic.10jqka.com.cn/ajax/stock/conceptlist.php?cid={concept_id}&code=000001', {{
        credentials: 'include',
        headers: {{ 'Referer': 'https://basic.10jqka.com.cn/000001/concept.html' }}
    }}).then(r => r.json())
    """
    result = subprocess.run(
        ['omp', 'web-operator', 'page', 'eval', js],
        capture_output=True, text=True, timeout=30
    )
    return json.loads(result.stdout)
```

### 3.2 会话刷新策略

`cdp eval` 返回的 JSON 中 `errorcode != 0` 或 stdout 不是合法 JSON 时，表示会话失效。此时重新执行 Step 1（`cdp nav` 到 THS 页面）后继续。

### 3.3 请求节奏

- 每次 `cdp eval` 调用间隔 **800ms~1200ms**（随机抖动）
- 连续 3 次失败后暂停 **5 分钟**再重试
- 总任务 362 个概念，预计耗时约 **8~12 分钟**

---

## 4. 数据结构定义

### 4.1 `cdp eval` 返回的原始数据（ashare-data 负责解析）

```python
data = json.loads(stdout)
# data["result"]["name"]               → 概念名称
# data["result"]["report"]             → 财报基准日
# data["result"]["listdata"]           → dict，key 为日期，value 为成员数组
report_date = list(data["result"]["listdata"].keys())[0]
members = data["result"]["listdata"][report_date]
# members[i][0]  → 股票代码
# members[i][1]  → 股票名称
# members[i][7]  → 关联理由（摘要）
# members[i][8]  → 关联理由（详细），优先取此字段，为空则退回 [7]
```

### 4.2 ashare-platform 数据模型

```python
class ThemeMemberStock(Base):
    __tablename__ = "theme_member_stock"
    __table_args__ = (UniqueConstraint("concept_id", "code", name="uq_theme_member"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    concept_id: Mapped[str] = mapped_column(String(16), index=True)   # THS 概念 ID，如 "309264"
    concept_name: Mapped[str] = mapped_column(String(128))            # 概念名称，如 "AI应用"
    code: Mapped[str] = mapped_column(String(16), index=True)         # 股票代码，如 "600666"
    name: Mapped[str] = mapped_column(String(64))                     # 股票名称，如 "奥瑞德"
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)   # 关联理由文本
    report_date: Mapped[str] = mapped_column(String(10))              # 数据基准日，如 "2025-09-30"
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

### 4.3 查询接口（ashare-data 对外暴露）

```
GET /stocks/themes/{code}/{trade_date}   ← 已实现（C3）
    内部逻辑变更：theme_stock_daily JOIN theme_member_stock 双源合并

GET /stocks/theme-aligned-candidates/{trade_date}   ← C5，建库后实现
    内部逻辑：red_window_daily JOIN theme_member_stock JOIN theme_emotion_daily
```

---

## 5. 错误处理

| 场景 | 处理方式 |
|------|---------|
| `errorcode != 0` | 重新执行 `cdp nav` 刷新会话，重试当前概念，最多 3 次 |
| stdout 非合法 JSON | 同上 |
| `listdata` 为空或无 key | 跳过，记录 warning |
| Nginx 403（`<h1>Nginx forbidden`） | 暂停整个任务 5 分钟后续跑 |
| subprocess timeout（>30s） | 记录失败，跳过继续 |

---

## 6. 验收标准

- [ ] `omp web-operator page eval` 能在 THS 页面上下文中成功执行 fetch 并返回 JSON
- [ ] 362 个概念中 ≥ 350 个成功返回成员数据
- [ ] AI应用（309264）成员数 ≥ 400（实测 478）
- [ ] 黄金概念（300248）成员数 ≥ 20
- [ ] ashare-data 侧 `theme_member_stock` 表记录数 ≥ 30,000 条
- [ ] `GET /stocks/themes/{code}/{trade_date}` 接口的题材命中率（相比当前 1.6%）显著提升
