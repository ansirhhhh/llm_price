@echo off
chcp 65001 >nul
title AI Model Price Compare Platform

echo ========================================
echo   AI Model Price Compare Platform
echo ========================================
echo.

cd /d "%~dp0backend"

if not exist "venv\" (
    echo [1/3] Creating Python virtual environment...
    python -m venv venv
    if errorlevel 1 (
        echo [ERROR] Failed to create venv. Please install Python 3.10+.
        pause
        exit /b 1
    )
) else (
    echo [1/3] venv already exists.
)

echo [2/3] Installing dependencies...
call venv\Scripts\activate.bat
pip install -r requirements.txt -q
if errorlevel 1 (
    echo [ERROR] Failed to install dependencies.
    pause
    exit /b 1
)

echo [3/3] Starting server...
echo.
echo ========================================
echo   Server started!
echo   Open browser: http://localhost:8000
echo   API:          http://localhost:8000/api/prices
echo   Health:       http://localhost:8000/api/health
echo ========================================
echo.
echo   Press Ctrl+C to stop.
echo.

start "" http://localhost:8000
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

pause