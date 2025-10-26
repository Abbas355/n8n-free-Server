@echo off
REM ============================================
REM n8n Multi-Instance Startup Script (Safe)
REM Checks Docker first
REM ============================================

echo.
echo ============================================
echo   n8n Multi-Instance Setup
echo ============================================
echo.

REM Check if Docker is running
echo [0/5] Checking if Docker is running...
docker info >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ❌ Docker is not running!
    echo.
    echo Please start Docker Desktop:
    echo   1. Look for Docker Desktop in Start Menu
    echo   2. Or run: "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    echo   3. Wait for Docker to fully start (icon in system tray)
    echo   4. Then run this script again
    echo.
    pause
    exit /b 1
)
echo    ✓ Docker is running

echo.
echo [1/5] Creating directory structure...
mkdir client-data\client-a\n8n 2>nul
mkdir client-data\client-a\postgres 2>nul
mkdir client-data\client-a\redis 2>nul
mkdir client-data\client-a\custom-nodes 2>nul
mkdir client-data\client-b\n8n 2>nul
mkdir client-data\client-b\postgres 2>nul
mkdir client-data\client-b\redis 2>nul
mkdir client-data\client-b\custom-nodes 2>nul
echo    ✓ Directories created

echo.
echo [2/5] Pulling Docker images (first time only)...
echo    This may take 5-10 minutes on first run...
docker pull n8nio/n8n:latest
docker pull postgres:16-alpine
docker pull redis:7-alpine
echo    ✓ Images ready

echo.
echo [3/5] Starting Client A (Port 5678)...
docker-compose -f docker-compose.client-a.yml up -d
if %ERRORLEVEL% NEQ 0 (
    echo    ❌ Failed to start Client A
    echo    Check logs: docker-compose -f docker-compose.client-a.yml logs
    pause
    exit /b 1
)
echo    ✓ Client A starting...

echo.
echo [4/5] Starting Client B (Port 5679)...
docker-compose -f docker-compose.client-b.yml up -d
if %ERRORLEVEL% NEQ 0 (
    echo    ❌ Failed to start Client B
    echo    Check logs: docker-compose -f docker-compose.client-b.yml logs
    pause
    exit /b 1
)
echo    ✓ Client B starting...

echo.
echo [5/5] Waiting for instances to be ready...
echo    This takes about 60 seconds...

REM Wait and check health
timeout /t 10 /nobreak >nul
echo    ⏳ 10 seconds...
timeout /t 10 /nobreak >nul
echo    ⏳ 20 seconds...
timeout /t 10 /nobreak >nul
echo    ⏳ 30 seconds...
timeout /t 10 /nobreak >nul
echo    ⏳ 40 seconds...
timeout /t 10 /nobreak >nul
echo    ⏳ 50 seconds...
timeout /t 10 /nobreak >nul
echo    ⏳ 60 seconds...

echo.
echo Checking health...
curl -s http://localhost:5678/healthz >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo    ✓ Client A is healthy
) else (
    echo    ⚠️  Client A is still starting (may need more time)
)

curl -s http://localhost:5679/healthz >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo    ✓ Client B is healthy
) else (
    echo    ⚠️  Client B is still starting (may need more time)
)

echo.
echo ============================================
echo   Setup Complete!
echo ============================================
echo.
echo Client A: http://localhost:5678
echo Client B: http://localhost:5679
echo.
echo View logs:
echo   docker-compose -f docker-compose.client-a.yml logs -f
echo   docker-compose -f docker-compose.client-b.yml logs -f
echo.
echo Check status:
echo   docker ps
echo.
echo Stop instances:
echo   docker-compose -f docker-compose.client-a.yml down
echo   docker-compose -f docker-compose.client-b.yml down
echo.
echo Press any key to open Client A in browser...
pause >nul
start http://localhost:5678

echo.
echo Press any key to open Client B in browser...
pause >nul
start http://localhost:5679

echo.
echo ============================================
echo   If instances are not accessible:
echo   1. Wait another minute
echo   2. Check logs: docker-compose -f docker-compose.client-a.yml logs
echo   3. Check containers: docker ps
echo ============================================
echo.
echo Press any key to exit...
pause >nul

