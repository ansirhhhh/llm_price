# 🤖 AI 模型价格比价平台 (LLM Price Compare)

> 实时对比各大 AI 大模型 API 调用价格，一键直达官方定价页面。

一款**零配置、开箱即用**的 LLM 价格对比工具。后端自动从 [llm-prices.com](https://www.llm-prices.com/) 拉取最新模型定价（含 Prompt Caching 缓存价）和**历史价格变更**，本地缓存 30 分钟；前端提供搜索、筛选、排序、一键跳转官网等功能，帮你快速找到**性价比最高**的模型。

---

## ✨ 功能特性

### 核心功能
- **🔍 智能搜索**：按模型名称或提供商关键字搜索
- **🏷️ 提供商筛选**：按厂商快速过滤（OpenAI / Anthropic / Google / DeepSeek / MiniMax / Qwen 等 28+ 家）
- **🆓 免费模型过滤**：一键只显示免费模型
- **📊 多列排序**：按输入价、输出价任意升降序
- **🔗 一键跳转**：每个模型都能直达官方定价页
- **💾 Prompt Caching 价格透传**：每个模型都带有 `cached_input_price`，能直接看到缓存命中的优惠价
- **📈 历史价格追踪**：`/api/prices/historical` 返回所有历史调价记录，同模型可按日期区间查询
- **📦 本地缓存**：30 分钟 TTL，拉取失败时自动回退过期缓存（不炸站）
- **⌨️ 快捷键**：`Ctrl+F` 聚焦搜索框、页面打开 30 分钟自动刷新
- **🔁 强制刷新**：`/api/prices?force_refresh=true` / `/api/prices/historical?force_refresh=true` 立即拉取最新数据

### 数据覆盖
| 分类 | 提供商 |
|------|--------|
| 海外头部 | OpenAI, Anthropic, Google, xAI, Meta, Mistral, Cohere, Perplexity, Groq |
| 国产主流 | DeepSeek, Moonshot, MiniMax, Zhipu, 01.AI, Qwen, Baidu, Alibaba, StepFun |
| 聚合平台 | Together AI, Fireworks AI, Replicate, Amazon, NVIDIA |
| 图像 | Stability AI, Midjourney |

---

## 🚀 快速开始

### 环境要求
- Python **3.10+**
- 能访问互联网（首次启动会拉取模型目录）

### 方式一：Windows 一键启动（推荐）

```bat
:: 双击或 cmd 运行
start.bat

:: 或 PowerShell
powershell -ExecutionPolicy Bypass -File start.ps1
```

启动后自动打开浏览器访问 <http://localhost:8000>。

### 方式二：Mac / Linux

```bash
chmod +x start.sh
./start.sh
```

### 方式三：手动启动

```bash
cd backend
python -m venv venv

# Windows
venv\Scripts\activate.bat
# macOS / Linux
source venv/bin/activate

pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

浏览器打开 <http://localhost:8000> 即可。

---

## 📂 项目结构

```
llm_price/
├── backend/
│   ├── main.py              # FastAPI 后端（API + 静态文件挂载 + 缓存）
│   ├── requirements.txt     # Python 依赖
│   └── venv/                # 首次运行自动创建的虚拟环境
├── frontend/
│   ├── index.html           # 页面结构
│   ├── style.css            # 样式
│   └── app.js               # 搜索 / 筛选 / 排序 / 渲染逻辑
├── start.bat                # Windows 启动 (cmd / PowerShell 通用)
├── start.ps1                # Windows 启动 (PowerShell 专用, 中文 UI)
└── start.sh                 # macOS / Linux / WSL 启动
```

---

## 🔌 API 接口

后端启动后直接用浏览器或 `curl` 调用：

| 路径 | 说明 |
|------|------|
| `GET /` | 前端页面 |
| `GET /api/prices` | 获取当前全部模型价格（30 分钟缓存，失败时回退过期缓存；`?force_refresh=true` 绕过缓存） |
| `GET /api/prices/historical` | 历史价格变更记录（含 `from_date` / `to_date` 区间，数据分组为 `data` 平铺列表 + `by_model` 按模型 ID 分组字典） |
| `GET /api/health` | 健康检查，额外返回缓存年龄秒数 |

### `/api/prices` 响应示例

```json
{
  "data": [
    {
      "model_id": "gpt-4o",
      "display_name": "GPT-4o",
      "provider": "OpenAI",
      "vendor": "openai",
      "family": "",
      "input_price": 2.5,
      "output_price": 10.0,
      "cached_input_price": 1.25,
      "context_window": null,
      "max_output_tokens": null,
      "url": "https://openai.com/pricing",
      "capabilities": [],
      "availability_status": ""
    }
  ],
  "as_of": "2026-07-09",
  "count": 100,
  "source": "llm-prices.com/current-v1.json",
  "cached": false,
  "stale": false
}
```

价格单位：**美元 / 每 1 Million tokens**。`cached_input_price` 为 Prompt Caching 命中后的优惠输入价（若厂商不支持则为 `null`）。

### `/api/prices/historical` 响应示例

```json
{
  "data": [
    {
      "model_id": "deepseek-chat",
      "input_price": 0.14,
      "output_price": 0.28,
      "from_date": null,
      "to_date": "2025-02-08"
    },
    {
      "model_id": "deepseek-chat",
      "input_price": 0.27,
      "output_price": 1.1,
      "from_date": "2025-02-08",
      "to_date": null
    }
  ],
  "by_model": {
    "deepseek-chat": [
      { "from_date": null, "to_date": "2025-02-08", "input_price": 0.14, "..." : "..." },
      { "from_date": "2025-02-08", "to_date": null, "input_price": 0.27, "..." : "..." }
    ]
  },
  "count": 200,
  "unique_models": 95,
  "source": "llm-prices.com/historical-v1.json",
  "cached": false
}
```

`from_date` 为 `null` 表示「最早记录之前」；`to_date` 为 `null` 表示「到现在仍然生效」。两个值同时不为 null 时，半开区间 `[from_date, to_date)` 生效。

---

## ⚙️ 架构说明

```
┌─────────────────┐    30-min cache + stale fallback    ┌──────────────────────┐
│   Frontend      │◄────────────────────────────────────►│  FastAPI Backend     │
│  (index.html    │   GET /api/prices                    │  (main.py)           │
│   + app.js)     │   GET /api/prices/historical         │                       │
└─────────────────┘                                       └───────────┬──────────┘
                                                                        │
                                           ┌────────────────────────────┴─────────────────────────────┐
                                           ▼                                                          ▼
                            ┌──────────────────────────────────┐         ┌──────────────────────────────────┐
                            │  llm-prices.com/current-v1.json  │         │ llm-prices.com/historical-v1.json│
                            │  (current prices + prompt cache) │         │  (all price changes w/ dates)    │
                            └──────────────────────────────────┘         └──────────────────────────────────┘
```

- 后端每 30 分钟拉取一次 [llm-prices.com](https://www.llm-prices.com/) 两个 JSON 文件，分别存在两个独立的内存缓存里
- 前端每 30 分钟自动刷新一次（`setInterval`），用户也可以手动点刷新
- 如果数据源接口失败，后端会尽量返回上次成功拉取的**过期缓存**，并在响应里带上 `stale: true`
- 想跳过缓存立刻拉最新？URL 加 `?force_refresh=true`
- FastAPI 同时托管前端静态文件，所以**一个端口搞定全部**，不用起前端服务

---

## 🛠️ 常见问题

**Q: 启动报错 `'not' 不是内部或外部命令`？**
A: Windows 老版 conhost 不认 UTF-8 BOM，已在新版 `start.bat` 改为纯 ASCII echo，拉取最新代码即可。

**Q: 页面一直显示「正在加载价格数据」？**
A: 检查能不能访问 `https://www.llm-prices.com/current-v1.json`，被墙的话需要代理。

**Q: 价格和官网对不上？想查涨价/降价历史？**
A: 当前价来自 `current-v1.json`，历史变更看 `/api/prices/historical`；最新官方价格点每一行的「🔗 前往」直达官网。

**Q: `context_window` / `max_output_tokens` / `capabilities` 都是空？**
A: 新数据源 llm-prices.com 主打价格，不提供这些元字段；需要这些的版本可以回退 1 个 commit 用 llm-oracle 数据源。

---

## 📜 许可证

本项目代码以 MIT 协议开源。价格数据版权归各提供商及 [llm-prices.com](https://www.llm-prices.com/) 项目所有。
