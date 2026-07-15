"""
AI模型价格比价平台 - Backend API
Fetches model pricing data from llm-prices.com and serves it with caching.
"""

import time
import logging
from typing import Any

from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import httpx
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="AI模型价格比价平台 API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Data source: llm-prices.com ---
CURRENT_PRICE_API = "https://www.llm-prices.com/current-v1.json"
HISTORICAL_PRICE_API = "https://www.llm-prices.com/historical-v1.json"

# --- Cache ---
CACHE_TTL = 30 * 60  # 30 minutes in seconds
_current_cache: dict[str, Any] = {"data": None, "timestamp": 0}
_historical_cache: dict[str, Any] = {"data": None, "timestamp": 0}

# --- Provider display names (keys match new llm-prices.com vendor field) ---
PROVIDER_NAMES: dict[str, str] = {
    "openai": "OpenAI",
    "anthropic": "Anthropic",
    "google": "Google",
    "mistral": "Mistral AI",
    "cohere": "Cohere",
    "meta": "Meta",
    "meta-ai": "Meta",
    "deepseek": "DeepSeek",
    "xai": "xAI",
    "groq": "Groq",
    "together": "Together AI",
    "fireworks": "Fireworks AI",
    "replicate": "Replicate",
    "perplexity": "Perplexity",
    "stability": "Stability AI",
    "midjourney": "Midjourney",
    "alibaba": "Alibaba",
    "zhipu": "Zhipu AI",
    "baidu": "Baidu",
    "moonshot": "Moonshot AI",
    "moonshot-ai": "Moonshot AI",
    "minimax": "MiniMax",
    "01.ai": "01.AI",
    "qwen": "Qwen",
    "stepfun": "StepFun",
    "amazon": "Amazon",
    "nvidia": "NVIDIA",
}


def format_provider(raw_vendor: str) -> str:
    """Format vendor name with proper casing."""
    key = (raw_vendor or "").lower().strip()
    if key in PROVIDER_NAMES:
        return PROVIDER_NAMES[key]
    # Fallback: try prefix match (e.g. "moonshot-ai" can fall back to "moonshot" if mapping missing)
    for k, v in PROVIDER_NAMES.items():
        if key.startswith(k) or k.startswith(key):
            return v
    return raw_vendor or "Unknown"


# --- Fallback URLs by vendor/provider ---
FALLBACK_URLS: dict[str, str] = {
    "openai": "https://openai.com/pricing",
    "anthropic": "https://www.anthropic.com/pricing",
    "google": "https://cloud.google.com/vertex-ai/pricing",
    "mistral": "https://mistral.ai/pricing",
    "cohere": "https://cohere.com/pricing",
    "meta": "https://ai.meta.com/pricing/",
    "deepseek": "https://platform.deepseek.com/api-docs/pricing",
    "xai": "https://x.ai/api",
    "groq": "https://groq.com/pricing/",
    "together": "https://www.together.ai/pricing",
    "fireworks": "https://fireworks.ai/pricing",
    "replicate": "https://replicate.com/pricing",
    "perplexity": "https://docs.perplexity.ai/docs/pricing",
    "stability": "https://platform.stability.ai/pricing",
    "midjourney": "https://www.midjourney.com/pricing",
    "alibaba": "https://www.alibabacloud.com/product/tongyi/pricing",
    "zhipu": "https://open.bigmodel.cn/pricing",
    "baidu": "https://cloud.baidu.com/product/wenxinworkshop/pricing",
    "moonshot": "https://platform.moonshot.cn/docs/pricing",
    "minimax": "https://platform.minimaxi.com/document/Price",
    "01.ai": "https://platform.01.ai/pricing",
    "qwen": "https://www.alibabacloud.com/product/tongyi/pricing",
    "stepfun": "https://platform.stepfun.com/pricing",
}


def resolve_url(vendor: str) -> str:
    """Resolve the pricing URL for a vendor by prefix match."""
    vendor_key = (vendor or "").lower().replace("_", "-")
    for key, fallback_url in FALLBACK_URLS.items():
        if key in vendor_key or vendor_key in key:
            return fallback_url
    return ""


def _round_price(v: Any) -> float | None:
    if isinstance(v, (int, float)):
        return round(float(v), 4)
    return None


def normalize_current(entry: dict) -> dict:
    """Normalize a single current-prices entry for the frontend."""
    vendor = entry.get("vendor") or ""
    input_price = _round_price(entry.get("input"))
    output_price = _round_price(entry.get("output"))
    cached_input = _round_price(entry.get("input_cached"))

    return {
        "model_id": entry.get("id", "Unknown"),
        "display_name": entry.get("name") or entry.get("id", "Unknown"),
        "provider": format_provider(vendor),
        "vendor": vendor,
        "family": entry.get("family", ""),
        "input_price": input_price,
        "output_price": output_price,
        "cached_input_price": cached_input,
        "context_window": None,
        "max_output_tokens": None,
        "url": resolve_url(vendor),
        "capabilities": [],
        "availability_status": "",
    }


def normalize_historical(entry: dict) -> dict:
    """Normalize a single historical-prices entry."""
    base = normalize_current(entry)
    base["from_date"] = entry.get("from_date")
    base["to_date"] = entry.get("to_date")
    return base


async def fetch_json(url: str, timeout: float = 15.0) -> dict:
    """Fetch a JSON payload via HTTP with timeout."""
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        return resp.json()


# ------------------ Current prices ------------------

def _build_current_result(raw: dict) -> dict:
    entries = raw.get("prices", []) or []
    models = [normalize_current(e) for e in entries]
    return {
        "data": models,
        "as_of": raw.get("updated_at", ""),
        "count": len(models),
        "source": "llm-prices.com/current-v1.json",
        "cached": False,
        "stale": False,
    }


async def _load_current(force: bool = False) -> dict:
    """Load current prices with TTL cache and stale-on-failure fallback."""
    global _current_cache
    now = time.time()

    if not force and _current_cache["data"] is not None and (now - _current_cache["timestamp"]) < CACHE_TTL:
        logger.info("Serving current prices from cache")
        return {**_current_cache["data"], "cached": True}

    try:
        raw = await fetch_json(CURRENT_PRICE_API)
    except Exception as e:
        logger.error(f"Failed to fetch current prices: {e}")
        if _current_cache["data"] is not None:
            logger.warning("Serving stale current cache due to fetch failure")
            return {**_current_cache["data"], "cached": True, "stale": True}
        raise HTTPException(status_code=502, detail="无法获取价格数据，请稍后重试。")

    result = _build_current_result(raw)
    _current_cache["data"] = result
    _current_cache["timestamp"] = now
    logger.info(f"Fetched {result['count']} current models from llm-prices.com")
    return result


@app.get("/api/prices")
async def get_prices(force_refresh: bool = False):
    """
    Returns current model pricing data. Cached for 30 minutes.
    Query param `force_refresh=true` bypasses the cache.
    """
    return await _load_current(force=force_refresh)


# ------------------ Historical prices ------------------

def _build_historical_result(raw: dict) -> dict:
    entries = raw.get("prices", []) or []
    rows = [normalize_historical(e) for e in entries]
    # Group by model id for convenience on the consumer side
    by_model: dict[str, list[dict]] = {}
    for r in rows:
        by_model.setdefault(r["model_id"], []).append(r)
    return {
        "data": rows,
        "by_model": by_model,
        "count": len(rows),
        "unique_models": len(by_model),
        "source": "llm-prices.com/historical-v1.json",
        "cached": False,
        "stale": False,
    }


async def _load_historical(force: bool = False) -> dict:
    global _historical_cache
    now = time.time()

    if not force and _historical_cache["data"] is not None and (now - _historical_cache["timestamp"]) < CACHE_TTL:
        logger.info("Serving historical prices from cache")
        return {**_historical_cache["data"], "cached": True}

    try:
        raw = await fetch_json(HISTORICAL_PRICE_API)
    except Exception as e:
        logger.error(f"Failed to fetch historical prices: {e}")
        if _historical_cache["data"] is not None:
            logger.warning("Serving stale historical cache due to fetch failure")
            return {**_historical_cache["data"], "cached": True, "stale": True}
        raise HTTPException(status_code=502, detail="无法获取历史价格数据，请稍后重试。")

    result = _build_historical_result(raw)
    _historical_cache["data"] = result
    _historical_cache["timestamp"] = now
    logger.info(
        f"Fetched {result['count']} historical rows ({result['unique_models']} unique models) from llm-prices.com"
    )
    return result


@app.get("/api/prices/historical")
async def get_historical_prices(force_refresh: bool = False):
    """
    Returns historical pricing data (all recorded price changes).
    - `data`: flat list of all rows
    - `by_model`: dict keyed by model_id of rows per model
    Each row has `from_date`/`to_date` (ISO date or null) indicating the
    period for which those prices apply.
    """
    return await _load_historical(force=force_refresh)


@app.get("/api/health")
async def health():
    """Health check endpoint."""
    now = time.time()
    cur_age = None if _current_cache["timestamp"] == 0 else round(now - _current_cache["timestamp"])
    hist_age = None if _historical_cache["timestamp"] == 0 else round(now - _historical_cache["timestamp"])
    return {
        "status": "ok",
        "timestamp": now,
        "current_cache_age_seconds": cur_age,
        "historical_cache_age_seconds": hist_age,
    }


# --- Serve frontend static files ---
frontend_dir = Path(__file__).resolve().parent.parent / "frontend"
if frontend_dir.is_dir():
    app.mount("/", StaticFiles(directory=str(frontend_dir), html=True), name="frontend")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
