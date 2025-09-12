#!/bin/bash

echo "=== Vision Mate Setup Script ==="
echo ""

# Check if Python is installed
if ! command -v python &> /dev/null; then
    echo "❌ Python is not installed. Please install Python 3.12+ first."
    exit 1
fi

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter 3.35+ first."
    exit 1
fi

echo "✅ Python and Flutter are installed"
echo ""

# Setup Backend
echo "🔧 Setting up backend..."
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Download YOLO model
echo "📥 Downloading YOLOv8n model..."
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')" > /dev/null 2>&1

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    echo "📝 Created .env file. Please add your OpenAI API key."
else
    echo "✅ .env file already exists"
fi

cd ..

# Setup Frontend
echo "🔧 Setting up Flutter app..."
cd frontend/vision_mate_app

# Get Flutter dependencies
flutter pub get

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Add your OpenAI API key to backend/.env"
echo "2. Start backend: cd backend && python main.py"
echo "3. Start app: cd frontend/vision_mate_app && flutter run"
echo ""
