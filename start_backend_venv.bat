@echo off
echo 🚀 Starting Vision Mate Backend Server...
echo.

REM Check if virtual environment exists
if not exist ".venv\Scripts\python.exe" (
    echo ❌ Virtual environment not found!
    echo Please run setup.bat first to create the virtual environment.
    pause
    exit /b 1
)

REM Navigate to backend directory and start server
cd backend
echo 📂 Current directory: %CD%
echo 🐍 Using Python: ..\\.venv\\Scripts\\python.exe
echo.

..\\.venv\\Scripts\\python.exe main.py

pause
