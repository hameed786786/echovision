# Vision Mate - AI-Powered Navigation Assistant

A cross-platform Flutter app that helps visually impaired individuals navigate and understand their surroundings using AI.

## Project Structure

```
vision_mate/
├── frontend/vision_mate_app/     # Flutter mobile app
├── backend/                      # FastAPI backend
└── project_requirements.md      # Project specifications
```

## Quick Start

### Backend Setup

1. Navigate to backend directory:
   ```bash
   cd backend
   ```

2. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Set up environment variables:
   ```bash
   cp .env.example .env
   # Edit .env and add your OpenAI API key
   ```

4. Start the server:
   ```bash
   # On Windows (with virtual environment):
   cd backend
   ..\.venv\Scripts\python.exe main.py
   
   # On macOS/Linux (with virtual environment):
   cd backend
   ../.venv/bin/python main.py
   
   # Alternative using Python directly (if no virtual environment):
   python main.py
   ```

### Frontend Setup

1. Navigate to the Flutter app directory:
   ```bash
   cd frontend/vision_mate_app
   ```

2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Run on Android/iOS (make sure you're in the vision_mate_app directory):
   ```bash
   flutter run
   ```

   **Note**: Make sure you have:
   - Android device connected via USB with USB debugging enabled, OR
   - iOS device connected (requires Mac with Xcode)
   - Backend server running on `http://127.0.0.1:8000`

## Running on Mobile Device

### Android Setup:
1. Enable Developer Options: Settings → About Phone → Tap "Build Number" 7 times
2. Enable USB Debugging: Settings → Developer Options → USB Debugging
3. Connect phone via USB cable
4. Run: `flutter run` (from `frontend/vision_mate_app` directory)

### iOS Setup:
1. Requires Mac with Xcode installed
2. Connect iPhone via USB cable
3. Run: `flutter run` (from `frontend/vision_mate_app` directory)

### Build APK for Android:
```bash
cd frontend/vision_mate_app
flutter build apk --release
```
Transfer the APK file to your Android device to install directly.

## Features

### Core Features
- ✅ Real-time object detection using YOLOv8n
- ✅ Scene description using BLIP-2
- ✅ Voice-based Q&A using GPT-4o-mini
- ✅ Text-to-Speech audio guidance
- ✅ Speech-to-Text voice input
- ✅ Gesture-based navigation
- ✅ Haptic feedback
- ✅ Accessibility-first design
- ✅ **Auto-flashlight**: Automatically turns on in low light conditions

### Gesture Controls
- **Swipe Up**: Describe surroundings
- **Swipe Right**: Ask a question
- **Swipe Down**: Toggle flashlight (for low light conditions)
- **Swipe Left**: Stop audio
- **Double Tap**: Stop audio
- **Long Press**: Emergency mode

### Innovative Features
- 🚨 Context-aware safety alerts
- 🧭 Smart navigation guidance
- 🆘 SOS emergency assistance
- 💡 **Intelligent Auto-Flashlight**: Automatically detects low light and enables flashlight
  - Analyzes image brightness in real-time
  - Turns on flashlight when brightness drops below 25%
  - Turns off flashlight when brightness exceeds 55%
  - Can be manually disabled/enabled
  - Shows current light level percentage

## API Endpoints

- `GET /` - Health check
- `POST /detect` - Object detection
- `POST /describe` - Scene description
- `POST /qa` - Question answering
- `POST /analyze` - Complete scene analysis

## Dependencies

### Backend
- FastAPI
- YOLOv8 (Ultralytics)
- BLIP-2 (Transformers)
- OpenAI API
- OpenCV
- Python 3.12+

### Frontend
- Flutter 3.35+
- Camera plugin
- TTS/STT plugins
- Provider state management
- HTTP client (Dio)

## Configuration

### API Configuration
Update `lib/config/constants.dart` to point to your backend:

```dart
static const String baseUrl = 'http://your-api-url:8000';
```

### Environment Variables
Required environment variables for backend:

```
OPENAI_API_KEY=your_openai_api_key
HUGGINGFACE_TOKEN=your_hf_token (optional)
```

## Deployment

### Backend Deployment
- Recommended: Heroku, Render, or Hugging Face Spaces
- Docker support included

### Mobile App Deployment
- Android: Build APK with `flutter build apk`
- iOS: Build with `flutter build ios`

## Development Notes

- The app is designed for accessibility-first usage
- All UI elements have semantic labels for screen readers
- Audio feedback is prioritized over visual UI
- Gesture controls are optimized for single-hand usage

## Testing

### Backend Testing
```bash
cd backend
python -m pytest
```

### Frontend Testing
```bash
cd frontend/vision_mate_app
flutter test
```

## Known Issues & Limitations

- Requires stable internet connection for full functionality
- Camera permission required for core features
- Microphone permission needed for voice commands
- Processing time depends on image complexity

### Troubleshooting

**Build Failed Error (Gradle):**
If you encounter build errors, try:
```bash
flutter clean
flutter pub get
flutter run
```

**No Device Connected:**
- Make sure USB debugging is enabled on Android
- Check if device shows up with: `flutter devices`
- Try reconnecting the USB cable

## Future Enhancements

- Offline mode with local TTS/STT
- GPS integration for location-based guidance
- Multi-language support
- Custom voice training
- Wearable device integration

## License

This project is developed for educational and accessibility purposes.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Support

For support and questions, please create an issue in the repository.
