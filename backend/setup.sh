#!/bin/bash

# Install dependencies
echo "Installing Python dependencies..."
pip install -r requirements.txt

# Download YOLO model if not exists
echo "Downloading YOLOv8n model..."
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"

echo "Setup complete! Run 'python main.py' to start the server."
