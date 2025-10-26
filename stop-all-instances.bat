@echo off
REM ============================================
REM Stop All n8n Instances (Windows)
REM ============================================

echo.
echo ============================================
echo   Stopping All n8n Instances
echo ============================================
echo.

echo Stopping Client A...
docker-compose -f docker-compose.client-a.yml down

echo.
echo Stopping Client B...
docker-compose -f docker-compose.client-b.yml down

echo.
echo ============================================
echo   All instances stopped!
echo ============================================
echo.

docker ps
echo.
echo Press any key to exit...
pause >nul

