class ApiConfig {
  // IMPORTANT: Choose the correct URL based on your device:
  // For physical Android/iOS device on same WiFi network:
  static const String baseUrl =
      'http://10.123.74.126:8000'; // Your current laptop IP (updated)

  // For Android emulator:
  // static const String baseUrl = 'http://10.0.2.2:8000';

  // For iOS simulator:
  // static const String baseUrl = 'http://localhost:8000';

  // For production:
  // static const String baseUrl = 'https://your-deployed-api.herokuapp.com';

  // Fallback URLs to try if primary fails (updated with current IP)
  static const List<String> fallbackUrls = [
    'http://10.123.74.126:8000', // Current WiFi IP (updated)
    'http://192.168.137.227:8000', // Previous WiFi IP
    'http://10.227.99.126:8000', // Previous WiFi IP
    'http://10.76.115.126:8000', // Previous WiFi IP
    'http://172.17.16.212:8000', // Previous WiFi IP
    'http://10.0.2.2:8000', // Android emulator fallback
    'http://localhost:8000', // Local
    'http://127.0.0.1:8000', // Loopback
  ];

  static const String detectEndpoint = '/detect';
  static const String describeEndpoint = '/describe';
  static const String qaEndpoint = '/qa';
  static const String analyzeEndpoint = '/analyze';

  static const Duration requestTimeout = Duration(
    seconds: 180,
  ); // Increased for AI model processing
}

class AppStrings {
  static const String appName = 'Vision Mate';
  static const String welcomeMessage =
      'Camera is active. Swipe up to hear surroundings. Swipe right to ask a question.';
  static const String listeningMessage = 'Listening... Ask your question now.';
  static const String processingMessage = 'Processing your request...';
  static const String errorMessage = 'Something went wrong. Please try again.';
  static const String noInternetMessage =
      'No internet connection. Some features may not work.';
  static const String cameraPermissionMessage =
      'Camera permission is required to use this app.';
  static const String microphonePermissionMessage =
      'Microphone permission is required for voice commands.';
}

class AppConstants {
  static const double gestureThreshold = 100.0;
  static const Duration vibrationDuration = Duration(milliseconds: 200);
  static const Duration longVibrationDuration = Duration(milliseconds: 500);
  static const Duration speechRate = Duration(milliseconds: 500);
  static const double speechVolume = 1.0;
  static const double speechPitch = 1.0;
}
