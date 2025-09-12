@echo off

echo Installing Python dependencies...
pip install -r requirements.txt

echo Downloading YOLOv8n model...
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"

echo Setup complete! Run 'python main.py' to start the server.
pause
