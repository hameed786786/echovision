@echo off
echo === Vision Mate Setup Script ===
echo.

REM Check if Python is installed
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Python is not installed. Please install Python 3.12+ first.
    pause
    exit /b 1
)

REM Check if Flutter is installed
flutter --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Flutter is not installed. Please install Flutter 3.35+ first.
    pause
    exit /b 1
)

echo ✅ Python and Flutter are installed
echo.

REM Setup Backend
echo 🔧 Setting up backend...
cd backend

REM Install dependencies
pip install -r requirements.txt

REM Download YOLO model
echo 📥 Downloading YOLOv8n model...
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')" >nul 2>&1

REM Create .env file if it doesn't exist
if not exist .env (
    copy .env.example .env
    echo 📝 Created .env file. Please add your OpenAI API key.
) else (
    echo ✅ .env file already exists
)

cd ..

REM Setup Frontend
echo 🔧 Setting up Flutter app...
cd frontend\vision_mate_app

REM Get Flutter dependencies
flutter pub get

echo.
echo 🎉 Setup complete!
echo.
echo Next steps:
echo 1. Add your OpenAI API key to backend\.env
echo 2. Start backend: cd backend ^&^& python main.py
echo 3. Start app: cd frontend\vision_mate_app ^&^& flutter run
echo.
pause
