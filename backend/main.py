"""
AI模型价格比价平台 - Backend API
Fetches model pricing data from llm-oracle and serves it with caching.
"""

import time
import logging
from typing import Optional

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

# CORS: allow all origins for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Data source ---
PRICE_API = "https://oracle.weiseer.com/catalog.json"

# --- Cache ---
CACHE_TTL = 30 * 60  # 30 minutes in seconds
_cache: dict = {"data": None, "timestamp": 0}


# --- Provider display names ---
PROVIDER_NAMES: dict[str, str] = {
    "openai": "OpenAI",
    "anthropic": "Anthropic",
    "google": "Google",
    "mistral": "Mistral AI",
    "cohere": "Cohere",
    "meta": "Meta",
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
    "minimax": "MiniMax",
    "01.ai": "01.AI",
    "qwen": "Qwen",
    "stepfun": "StepFun",
    "amazon": "Amazon",
    "nvidia": "NVIDIA",
}


def format_provider(raw_provider: str) -> str:
    """Format provider name with proper casing."""
    key = (raw_provider or "").lower().strip()
    return PROVIDER_NAMES.get(key, raw_provider or "Unknown")


# --- Fallback URLs by provider ---
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


def resolve_url(model: dict) -> str:
    """Resolve the pricing URL for a model, with fallback logic."""
    # Primary: use pricing_source_url from llm-oracle
    url = model.get("pricing_source_url") or model.get("url") or ""
    if url.strip():
        return url.strip()

    # Fallback: match by provider name
    provider = (model.get("provider") or "").lower()
    for key, fallback_url in FALLBACK_URLS.items():
        if key in provider:
            return fallback_url
    return ""


def extract_capabilities(cap_obj) -> list[str]:
    """Extract capability names from llm-oracle capabilities object."""
    if isinstance(cap_obj, dict):
        return sorted([k for k, v in cap_obj.items() if v])
    if isinstance(cap_obj, list):
        return cap_obj
    return []


def normalize_prices(models: list[dict]) -> list[dict]:
    """
    Normalize model data for the frontend.
    - Prices are already per 1M tokens USD from llm-oracle
    - Extract capabilities from object to array
    - Resolve pricing URLs
    """
    normalized = []
    for m in models:
        input_price = m.get("input_price")
        output_price = m.get("output_price")

        normalized.append({
            "model_id": m.get("model_id", "Unknown"),
            "display_name": m.get("display_name", m.get("model_id", "Unknown")),
            "provider": format_provider(m.get("provider", "")),
            "family": m.get("family", ""),
            "input_price": round(input_price, 4) if isinstance(input_price, (int, float)) else None,
            "output_price": round(output_price, 4) if isinstance(output_price, (int, float)) else None,
            "context_window": m.get("context_window"),
            "max_output_tokens": m.get("max_output_tokens"),
            "url": resolve_url(m),
            "capabilities": extract_capabilities(m.get("capabilities")),
            "availability_status": m.get("availability_status", ""),
        })
    return normalized


async def fetch_from_oracle() -> dict:
    """Fetch raw catalog data from llm-oracle API."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.get(PRICE_API)
        resp.raise_for_status()
        return resp.json()


@app.get("/api/prices")
async def get_prices():
    """
    Returns model pricing data, cached for 30 minutes.
    Response: { data: [...], as_of: "...", count: N, cached: bool }
    """
    global _cache
    now = time.time()

    # Return cached data if still valid
    if _cache["data"] is not None and (now - _cache["timestamp"]) < CACHE_TTL:
        logger.info("Serving from cache")
        return {**_cache["data"], "cached": True}

    try:
        raw = await fetch_from_oracle()
    except Exception as e:
        logger.error(f"Failed to fetch from llm-oracle: {e}")
        # If cache exists (even if expired), serve stale data
        if _cache["data"] is not None:
            logger.warning("Serving stale cache due to fetch failure")
            return {**_cache["data"], "cached": True, "stale": True}
        raise HTTPException(status_code=502, detail="无法获取价格数据，请稍后重试。")

    models = normalize_prices(raw.get("models", []))
    result = {
        "data": models,
        "as_of": raw.get("as_of", ""),
        "count": len(models),
        "cached": False,
        "stale": False,
    }
    _cache["data"] = result
    _cache["timestamp"] = now
    logger.info(f"Fetched {len(models)} models from llm-oracle")
    return result


@app.get("/api/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "timestamp": time.time()}


# --- Serve frontend static files ---
frontend_dir = Path(__file__).resolve().parent.parent / "frontend"
if frontend_dir.is_dir():
    app.mount("/", StaticFiles(directory=str(frontend_dir), html=True), name="frontend")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
