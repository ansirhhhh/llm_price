#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/backend"

echo "========================================"
echo "  🤖 AI模型价格比价平台 - 启动中..."
echo "========================================"
echo ""

# Create virtual environment if needed
if [ ! -d "venv" ]; then
    echo "[1/3] 创建 Python 虚拟环境..."
    python3 -m venv venv
fi

# Activate and install
echo "[2/3] 安装依赖..."
source venv/bin/activate
pip install -r requirements.txt -q

# Start server
echo "[3/3] 启动服务..."
echo ""
echo "========================================"
echo "  🚀 服务启动成功！"
echo "  📖 打开浏览器访问: http://localhost:8000"
echo "  📡 API地址: http://localhost:8000/api/prices"
echo "  🩺 健康检查: http://localhost:8000/api/health"
echo "========================================"
echo ""
echo "  按 Ctrl+C 停止服务"
echo ""

python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
