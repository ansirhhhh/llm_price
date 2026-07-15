# AI模型价格比价平台 - PowerShell 启动脚本
# 用法: powershell -ExecutionPolicy Bypass -File start.ps1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AI模型价格比价平台 - 启动中..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$backendDir = Join-Path $PSScriptRoot "backend"
Set-Location $backendDir

# 1) 虚拟环境
if (-not (Test-Path "venv")) {
    Write-Host "[1/3] 创建 Python 虚拟环境..." -ForegroundColor Yellow
    python -m venv venv
    if ($LASTEXITCODE -ne 0) {
        Write-Host "创建虚拟环境失败，请确认已安装 Python 3.10+" -ForegroundColor Red
        Read-Host "按 Enter 退出"
        exit 1
    }
} else {
    Write-Host "[1/3] 虚拟环境已存在" -ForegroundColor Green
}

# 2) 依赖
Write-Host "[2/3] 安装依赖..." -ForegroundColor Yellow
& ".\venv\Scripts\Activate.ps1"
python -m pip install -r requirements.txt -q
if ($LASTEXITCODE -ne 0) {
    Write-Host "依赖安装失败" -ForegroundColor Red
    Read-Host "按 Enter 退出"
    exit 1
}

# 3) 启动服务
Write-Host "[3/3] 启动服务..." -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  服务启动成功！" -ForegroundColor Green
Write-Host "  打开浏览器访问: http://localhost:8000" -ForegroundColor Green
Write-Host "  API地址:        http://localhost:8000/api/prices" -ForegroundColor Green
Write-Host "  健康检查:        http://localhost:8000/api/health" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  按 Ctrl+C 停止服务" -ForegroundColor Cyan
Write-Host ""

Start-Process "http://localhost:8000"
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Read-Host "按 Enter 退出"
