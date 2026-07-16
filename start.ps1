# AI模型价格比价平台 - PowerShell 启动脚本
# 用法 1: 双击运行
# 用法 2: powershell -ExecutionPolicy Bypass -File start.ps1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = 'Continue'

$projectRoot = $PSScriptRoot
$backendDir = Join-Path $projectRoot "backend"
$venvPy = Join-Path $backendDir "venv\Scripts\python.exe"
$stopScript = Join-Path $projectRoot "stop_server.ps1"
$warmupScript = Join-Path $projectRoot "_open_browser_when_ready.ps1"
$port = 8000

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AI模型价格比价平台 - 启动中..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------
# [0/4] 清理：停掉任何占用 8000 的进程 + uvicorn --reload 孤儿 spawn worker
# ------------------------------------------------------------------
Write-Host "[0/4] 清理之前跑过的 8000 端口服务..." -ForegroundColor Yellow
if (Test-Path $stopScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $stopScript -Port $port
    if ($LASTEXITCODE -ne 0) { Write-Warning "cleanup 有告警，继续启动..." }
} else {
    Write-Warning "  找不到 $stopScript，跳过自动清理."
}
Write-Host ""

# ------------------------------------------------------------------
# [1/4] 虚拟环境（显式 venv\Scripts\python.exe，不依赖 activate）
# ------------------------------------------------------------------
Set-Location $backendDir
if (-not (Test-Path $venvPy)) {
    Write-Host "[1/4] 创建 Python 虚拟环境..." -ForegroundColor Yellow
    if (Test-Path "venv") { Remove-Item -Recurse -Force "venv" -ErrorAction Stop }
    & python -m venv venv
    if ($LASTEXITCODE -ne 0) {
        Write-Host "创建虚拟环境失败，请确认已安装 Python 3.10+ 并加入 PATH" -ForegroundColor Red
        Read-Host "按 Enter 退出"
        exit 1
    }
} else {
    Write-Host "[1/4] 虚拟环境已存在" -ForegroundColor Green
}
if (-not (Test-Path $venvPy)) {
    Write-Host "venv Python 仍不存在：$venvPy" -ForegroundColor Red
    Read-Host "按 Enter 退出"
    exit 1
}
Write-Host "  使用的 Python："
& $venvPy --version
& $venvPy -c "import sys; Write-Host ('    ' + sys.executable)"
Write-Host ""

# ------------------------------------------------------------------
# [2/4] 依赖
# ------------------------------------------------------------------
Write-Host "[2/4] 安装依赖（使用 venv pip）..." -ForegroundColor Yellow
& $venvPy -m pip install --upgrade pip -q
& $venvPy -m pip install -r requirements.txt -q
if ($LASTEXITCODE -ne 0) {
    Write-Host "依赖安装失败" -ForegroundColor Red
    Read-Host "按 Enter 退出"
    exit 1
}
Write-Host ""

# ------------------------------------------------------------------
# [3/4] 启动浏览器预热脚本（后台），然后前台跑 uvicorn
# ------------------------------------------------------------------
Write-Host "[3/4] 启动服务 + 浏览器预热助手..." -ForegroundColor Yellow
if (Test-Path $warmupScript) {
    Start-Process powershell -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass',
        '-File',$warmupScript,
        '-Port',$port,
        '-OpenUrl','http://localhost:8000'
    ) -WindowStyle Minimized | Out-Null
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  服务在前台运行中..." -ForegroundColor Green
Write-Host "  访问地址: http://localhost:8000" -ForegroundColor Green
Write-Host "  API    : http://localhost:8000/api/prices" -ForegroundColor Green
Write-Host "  健康检查: http://localhost:8000/api/health" -ForegroundColor Green
Write-Host "  (按 Ctrl+C 停止服务)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------------
# [4/4] 前台 uvicorn，Ctrl+C 会中断后跑 finally
# ------------------------------------------------------------------
try {
    & $venvPy -m uvicorn main:app --host 0.0.0.0 --port $port --reload
} finally {
    Write-Host ""
    Write-Host "正在停止 uvicorn 及子进程..." -ForegroundColor DarkRed
    if (Test-Path $stopScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $stopScript -Port $port -Quiet
    }
    Write-Host "已退出." -ForegroundColor Gray
    Read-Host "按 Enter 关闭窗口"
}
