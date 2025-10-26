@echo off
REM ============================================
REM Check Status of All n8n Instances (Windows)
REM ============================================

echo.
echo ============================================
echo   n8n Instance Status
echo ============================================
echo.

echo Running containers:
echo.
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo.
echo ============================================
echo   Health Checks
echo ============================================
echo.

echo Checking Client A (Port 5678)...
curl -s http://localhost:5678/healthz
echo.

echo Checking Client B (Port 5679)...
curl -s http://localhost:5679/healthz
echo.

echo.
echo ============================================
echo   Access URLs
echo ============================================
echo.
echo Client A: http://localhost:5678
echo Client B: http://localhost:5679
echo.
echo Press any key to exit...
pause >nul

