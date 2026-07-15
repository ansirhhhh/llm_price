@echo off
setlocal
chcp 65001 >nul
title AI Model Price Compare Platform

echo ========================================
echo   AI Model Price Compare Platform
echo ========================================
echo.

set "SCRIPT_DIR=%~dp0"
set "BACKEND_DIR=%SCRIPT_DIR%backend"
set "PY=%BACKEND_DIR%\venv\Scripts\python.exe"

rem ------------------------------------------------------------------
rem [0/4] Stop any prior server processes + orphan uvicorn spawn workers
rem ------------------------------------------------------------------
echo [0/4] Stopping any previous server on port 8000...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%stop_server.ps1" -Port 8000
if errorlevel 1 (
    echo [WARN] Cleanup had warnings; continuing...
)

rem ------------------------------------------------------------------
rem Enter backend directory and ensure venv exists with proper python
rem ------------------------------------------------------------------
cd /d "%BACKEND_DIR%"

rem ------------------------------------------------------------------
rem [1/4] Virtual environment (explicit python -m venv, no activate)
rem ------------------------------------------------------------------
if not exist "%PY%" (
    echo [1/4] Creating Python virtual environment...
    if exist "venv" ( rmdir /s /q venv )
    python -m venv venv
    if errorlevel 1 (
        echo [ERROR] Could not create venv. Please install Python 3.10+ and add to PATH.
        pause
        exit /b 1
    )
) else (
    echo [1/4] venv already exists.
)
if not exist "%PY%" (
    echo [ERROR] "%PY%" not found. Aborting.
    pause
    exit /b 1
)
echo       Using Python:
"%PY%" --version
"%PY%" -c "import sys; print('        ' + sys.executable)"

rem ------------------------------------------------------------------
rem [2/4] Dependencies (explicit venv python -m pip)
rem ------------------------------------------------------------------
echo [2/4] Installing / upgrading dependencies (venv pip)...
"%PY%" -m pip install --upgrade pip -q
"%PY%" -m pip install -r requirements.txt -q
if errorlevel 1 (
    echo [ERROR] Dependency install failed.
    pause
    exit /b 1
)

rem ------------------------------------------------------------------
rem [3/4] Launch a background helper that opens the browser once
rem      HTTP /api/health returns 200. Uses a project helper script.
rem ------------------------------------------------------------------
echo [3/4] Starting uvicorn + wait-for-healthy helper...
start "Browser-Waiter" /B /MIN powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%_open_browser_when_ready.ps1" -Port 8000 -OpenUrl "http://localhost:8000"

echo.
echo ========================================
echo   Server starting in foreground (Ctrl+C to exit)...
echo   URL      : http://localhost:8000
echo   API      : http://localhost:8000/api/prices
echo   Health   : http://localhost:8000/api/health
echo ========================================
echo.

rem ------------------------------------------------------------------
rem [4/4] Foreground uvicorn. Ctrl+C here kills it cleanly.
rem ------------------------------------------------------------------
"%PY%" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

rem Best-effort cleanup on user exit
echo.
echo Exiting. Running cleanup once more...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%stop_server.ps1" -Port 8000 -Quiet
endlocal
