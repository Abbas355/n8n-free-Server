@echo off
REM ============================================
REM n8n Multi-Instance Startup Script (Windows)
REM ============================================

echo.
echo ============================================
echo   n8n Multi-Instance Setup
echo ============================================
echo.

REM Step 1: Create directory structure
echo [1/4] Creating directory structure...
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
echo [2/4] Starting Client A (Port 5678)...
docker-compose -f docker-compose.client-a.yml up -d
echo    ✓ Client A starting...

echo.
echo [3/4] Starting Client B (Port 5679)...
docker-compose -f docker-compose.client-b.yml up -d
echo    ✓ Client B starting...

echo.
echo [4/4] Waiting for instances to be ready (30 seconds)...
timeout /t 30 /nobreak >nul

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
echo Done! Press any key to exit...
pause >nul

