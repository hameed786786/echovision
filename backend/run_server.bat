@echo off
echo Starting Vision Mate Backend Server...
echo.

REM Change to backend directory
cd /d "%~dp0"

REM Check if virtual environment exists
if not exist "..\\.venv\\Scripts\\python.exe" (
    echo Error: Virtual environment not found!
    echo Please run setup.bat first to create the virtual environment.
    pause
    exit /b 1
)

REM Activate virtual environment and run server
echo Using virtual environment Python...
..\.venv\Scripts\python.exe main.py

pause
