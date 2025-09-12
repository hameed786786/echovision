# VisionMate - Real-time Navigation Testing Guide

## 🚀 Quick Test Commands

### Backend Testing
```bash
# Start the enhanced backend server
cd backend
python main.py

# Test health endpoint
curl http://localhost:8000/health

# Test WebSocket connection (requires wscat)
npm install -g wscat
wscat -c ws://localhost:8000/ws/guide
```

### Real-time Guidance Features

#### 1. **Enhanced Distance Estimation**
- **Very Close**: Large objects taking >50% of frame
- **Close**: Objects 30-50% of frame size  
- **Medium**: Objects 15-30% of frame size
- **Far**: Objects 5-15% of frame size
- **Very Far**: Objects <5% of frame size

#### 2. **Path Smoothing Directions**
- **Center**: Target is directly ahead
- **Slightly Left/Right**: Minor direction adjustments
- **Left/Right**: Standard turning directions
- **Hard Left/Right**: Sharp turns required

#### 3. **Obstacle Analysis**
- **High Threat**: Large, close obstacles blocking path
- **Medium Threat**: Moderate obstacles requiring attention
- **Low Threat**: Distant or small objects

## 📱 Frontend Integration

### Key WebSocket Messages

**Send to server:**
```json
{
  "image": "base64_encoded_image",
  "question": "navigate me to the door"
}
```

**Receive from server:**
```json
{
  "target": "door",
  "direction": "slightly left",
  "distance": "close",
  "instruction": "Move slightly left. Door is close ahead.",
  "scene_description": "1 door left; 2 chairs center",
  "objects": [...],
  "obstacles": [...],
  "confidence": 0.85,
  "ts": 1703123456.789
}
```

## 🧪 Testing Scenarios

### Scenario 1: Navigate to Door
1. Point camera at room with door
2. Send: `"navigate me to the door"`
3. Expected: Direction guidance + obstacle warnings

### Scenario 2: Find Seating
1. Point camera at room with chairs
2. Send: `"find me a chair to sit"`
3. Expected: Chair location + path guidance

### Scenario 3: Obstacle Avoidance
1. Point camera with obstacles in path
2. Send: `"navigate me forward"`
3. Expected: Obstacle warnings + alternative directions

## 🔧 Configuration

### Backend Settings (main.py)
```python
THROTTLE_DELAY = 0.3  # WebSocket throttle (seconds)
MAX_IMAGE_SIZE = 1024  # Max image dimension
CONFIDENCE_THRESHOLD = 0.3  # YOLOv8 confidence
```

### Flutter Dependencies
Add to `pubspec.yaml`:
```yaml
dependencies:
  web_socket_channel: ^2.4.0
  camera: ^0.10.5
  flutter_tts: ^3.8.3
  http: ^1.1.0
```

## 📊 Enhanced Features Summary

### ✅ Implemented
- **Real-time WebSocket streaming** with throttling
- **Distance estimation** using object size heuristics
- **Path smoothing** with granular directions
- **Obstacle analysis** with threat assessment
- **Focused speech** generation for relevant objects
- **Enhanced object detection** supporting multiple bbox formats

### 🎯 Key Improvements
- **Contextual Instructions**: "Move slightly left" vs "Turn hard right"
- **Threat-based Warnings**: High/medium/low obstacle classification
- **Confidence Weighting**: More reliable direction calculations
- **Smooth Guidance**: Continuous navigation vs discrete commands

### 🚀 Ready for Testing
- Backend fully functional with enhanced navigation
- WebSocket endpoint active for real-time streaming
- Flutter integration example provided
- Distance and obstacle algorithms implemented

## 💡 Usage Tips

1. **Optimal Camera Distance**: 2-4 feet from target areas
2. **Lighting**: Ensure adequate lighting for better detection
3. **Movement**: Move slowly for smoother guidance
4. **Questions**: Use specific targets ("door", "chair", "exit")
5. **Feedback**: System provides audio + visual guidance

## 🔍 Debugging

### Common Issues
- **WebSocket disconnects**: Check server status and network
- **No guidance**: Verify target objects are visible
- **Delayed responses**: Normal due to AI processing time
- **False detections**: Adjust confidence thresholds if needed

### Logs to Monitor
- Object detection counts
- Direction calculations
- Distance estimations
- WebSocket connection status
- TTS speech events

The enhanced system is ready for real-world navigation testing! 🎉
