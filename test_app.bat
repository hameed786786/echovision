@echo off
echo === Vision Mate Debug Test ===
echo.

echo Step 1: Starting Backend...
start cmd /k "cd /d %~dp0backend && python main.py"

echo Step 2: Waiting for backend to start...
timeout /t 5 /nobreak

echo Step 3: Testing backend health...
curl -s http://localhost:8000/health
echo.

echo Step 4: Instructions for Flutter App Testing:
echo.
echo 1. Open a new terminal and run:
echo    cd frontend/vision_mate_app
echo    flutter run
echo.
echo 2. Test these gestures in the app:
echo    - Swipe UP fast = Describe scene
echo    - Swipe RIGHT fast = Ask question  
echo    - Double tap = Stop audio
echo    - Long press = Emergency mode
echo.
echo 3. Check the console logs for debug output
echo.
echo Backend is running at: http://localhost:8000
echo API Documentation: http://localhost:8000/docs
echo.
pause
