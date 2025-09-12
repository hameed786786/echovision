import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';

class CameraService {
  static CameraController? _controller;
  static bool _isInitialized = false;
  static List<CameraDescription>? _cameras;
  static bool _isFlashlightOn = false;
  static bool _autoFlashlightEnabled = true; // Always enabled automatic flashlight
  static double _lastBrightnessLevel = 1.0;

  static Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Request camera permission
      PermissionStatus permission = await Permission.camera.request();
      if (permission != PermissionStatus.granted) {
        return false;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        return false;
      }

      // Initialize camera controller with back camera
      _controller = CameraController(
        _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras!.first,
        ),
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      _isInitialized = true;
      return true;
    } catch (e) {
      print('Error initializing camera: $e');
      return false;
    }
  }

  static Future<Uint8List?> captureImage({bool skipAutoFlashlight = false}) async {
    print('CameraService: captureImage() called');

    if (!_isInitialized || _controller == null) {
      print('CameraService: Camera not initialized, initializing now...');
      bool success = await initialize();
      if (!success) {
        print('CameraService: Failed to initialize camera');
        return null;
      }
    }

    try {
      if (_controller != null && _controller!.value.isInitialized) {
        print('CameraService: Camera is ready, taking picture...');

        // Ensure camera is ready to take picture
        await Future.delayed(Duration(milliseconds: 500));

        XFile image = await _controller!.takePicture();
        print('CameraService: Picture taken, reading bytes...');

        Uint8List bytes = await image.readAsBytes();
        print('CameraService: Image bytes read, size: ${bytes.length}');

        // Check lighting conditions and auto-adjust flashlight (but not during the analysis itself)
        if (!skipAutoFlashlight && _autoFlashlightEnabled) {
          // Run this in background to avoid blocking the current capture
          Future.delayed(Duration(milliseconds: 100), () {
            checkAndAdjustFlashlight();
          });
        }

        return bytes;
      } else {
        print('CameraService: Controller not ready');
        return null;
      }
    } catch (e) {
      print('CameraService Error capturing image: $e');
      return null;
    }
  }

  static CameraController? get controller => _controller;
  static bool get isInitialized => _isInitialized;
  static bool get isFlashlightOn => _isFlashlightOn;
  static bool get autoFlashlightEnabled => _autoFlashlightEnabled;
  static double get lastBrightnessLevel => _lastBrightnessLevel;

  // Analyze image brightness to determine if flashlight is needed
  static double _calculateImageBrightness(Uint8List imageBytes) {
    try {
      // Simple brightness calculation based on image data
      // This is a basic implementation - in a real app you might want more sophisticated analysis
      int totalBrightness = 0;
      int sampleSize = imageBytes.length ~/ 100; // Sample every 100th pixel for performance
      
      for (int i = 0; i < imageBytes.length; i += sampleSize) {
        totalBrightness += imageBytes[i];
      }
      
      double averageBrightness = totalBrightness / (imageBytes.length / sampleSize);
      return averageBrightness / 255.0; // Normalize to 0-1 range
    } catch (e) {
      print('CameraService: Error calculating brightness: $e');
      return 0.5; // Default to medium brightness if calculation fails
    }
  }

  // Check and automatically adjust flashlight based on lighting conditions
  static Future<void> checkAndAdjustFlashlight() async {
    if (!_autoFlashlightEnabled || !_isInitialized || _controller == null) {
      return;
    }

    try {
      // Capture a quick image to analyze brightness (skip recursive auto-flashlight check)
      Uint8List? imageBytes = await captureImage(skipAutoFlashlight: true);
      if (imageBytes != null) {
        double brightness = _calculateImageBrightness(imageBytes);
        _lastBrightnessLevel = brightness;
        
        // Threshold for low light detection (adjustable)
        const double lowLightThreshold = 0.25; // 25% brightness
        const double goodLightThreshold = 0.55; // 55% brightness
        
        print('CameraService: Current brightness level: ${(brightness * 100).toStringAsFixed(1)}%');
        
        if (brightness < lowLightThreshold && !_isFlashlightOn) {
          // Turn on flashlight in low light
          await turnOnFlashlight();
          print('CameraService: 💡 Auto-enabled flashlight due to low light');
        } else if (brightness > goodLightThreshold && _isFlashlightOn) {
          // Turn off flashlight in good light (but only if it was auto-enabled)
          await turnOffFlashlight();
          print('CameraService: 🔆 Auto-disabled flashlight due to sufficient light');
        }
      }
    } catch (e) {
      print('CameraService: Error in auto flashlight adjustment: $e');
    }
  }

  // Flashlight control methods
  static Future<bool> toggleFlashlight() async {
    if (!_isInitialized || _controller == null) {
      print('CameraService: Camera not initialized for flashlight control');
      return false;
    }

    try {
      if (_isFlashlightOn) {
        await _controller!.setFlashMode(FlashMode.off);
        _isFlashlightOn = false;
        print('CameraService: Flashlight turned OFF');
      } else {
        await _controller!.setFlashMode(FlashMode.torch);
        _isFlashlightOn = true;
        print('CameraService: Flashlight turned ON');
      }
      return true;
    } catch (e) {
      print('CameraService Error toggling flashlight: $e');
      return false;
    }
  }

  static Future<bool> turnOnFlashlight() async {
    if (!_isInitialized || _controller == null) {
      print('CameraService: Camera not initialized for flashlight control');
      return false;
    }

    try {
      await _controller!.setFlashMode(FlashMode.torch);
      _isFlashlightOn = true;
      print('CameraService: Flashlight turned ON');
      return true;
    } catch (e) {
      print('CameraService Error turning on flashlight: $e');
      return false;
    }
  }

  static Future<bool> turnOffFlashlight() async {
    if (!_isInitialized || _controller == null) {
      print('CameraService: Camera not initialized for flashlight control');
      return false;
    }

    try {
      await _controller!.setFlashMode(FlashMode.off);
      _isFlashlightOn = false;
      print('CameraService: Flashlight turned OFF');
      return true;
    } catch (e) {
      print('CameraService Error turning off flashlight: $e');
      return false;
    }
  }

  static Future<void> dispose() async {
    try {
      // Turn off flashlight before disposing
      if (_isFlashlightOn && _controller != null) {
        await _controller!.setFlashMode(FlashMode.off);
        _isFlashlightOn = false;
      }
      
      await _controller?.dispose();
      _controller = null;
      _isInitialized = false;
    } catch (e) {
      print('Error disposing camera: $e');
    }
  }

  static Future<bool> hasPermission() async {
    try {
      PermissionStatus status = await Permission.camera.status;
      return status == PermissionStatus.granted;
    } catch (e) {
      return false;
    }
  }
}
