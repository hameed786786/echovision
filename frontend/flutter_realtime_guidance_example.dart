// Real-time guidance integration example for Flutter
// This demonstrates how to connect to the enhanced WebSocket guidance endpoint

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';

class RealtimeGuidanceService {
  WebSocketChannel? _channel;
  FlutterTts? _flutterTts;
  String _lastInstruction = '';
  DateTime _lastInstructionTime = DateTime.now();

  // Connection settings
  static const String wsUrl = 'ws://172.17.16.212:8000/ws/guide';
  static const Duration throttleDelay = Duration(milliseconds: 300);

  Future<void> initialize() async {
    _flutterTts = FlutterTts();
    await _flutterTts?.setLanguage("en-US");
    await _flutterTts?.setSpeechRate(0.8);
    await _flutterTts?.setVolume(1.0);
    await _flutterTts?.setPitch(1.0);
  }

  Future<void> connectWebSocket() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      print('✅ Connected to real-time guidance WebSocket');

      _channel?.stream.listen(
        _handleGuidanceMessage,
        onError: (error) {
          print('❌ WebSocket error: $error');
          _reconnectWebSocket();
        },
        onDone: () {
          print('🔌 WebSocket connection closed');
          _reconnectWebSocket();
        },
      );
    } catch (e) {
      print('❌ Failed to connect WebSocket: $e');
      Future.delayed(Duration(seconds: 3), _reconnectWebSocket);
    }
  }

  void _reconnectWebSocket() {
    Future.delayed(Duration(seconds: 2), () {
      if (_channel == null) {
        connectWebSocket();
      }
    });
  }

  Future<void> sendFrame(XFile imageFile, String question) async {
    try {
      // Read and compress image
      final bytes = await imageFile.readAsBytes();
      final compressedBytes = await _compressImage(bytes);
      final base64Image = base64Encode(compressedBytes);

      // Prepare message
      final message = {'image': base64Image, 'question': question.trim()};

      // Send to WebSocket
      _channel?.sink.add(jsonEncode(message));
    } catch (e) {
      print('❌ Error sending frame: $e');
    }
  }

  Future<Uint8List> _compressImage(Uint8List originalBytes) async {
    // Simple compression - resize to max 480px and reduce quality
    // In production, use image compression package

    // For now, just limit size (you can add actual compression here)
    if (originalBytes.length > 50000) {
      // Placeholder: implement actual image compression
      // For example, using flutter_image_compress package
    }
    return originalBytes;
  }

  void _handleGuidanceMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      // Handle different message types
      if (data['error'] != null) {
        print('⚠️ Server error: ${data['error']}');
        return;
      }

      if (data['status'] == 'throttled') {
        // Frame was throttled, continue sending
        return;
      }

      // Extract guidance information
      final instruction = data['instruction'] ?? '';
      final direction = data['direction'] ?? 'unknown';
      final target = data['target'];
      final sceneDescription = data['scene_description'] ?? '';
      final objects = data['objects'] ?? [];
      final distance = data['distance'] ?? 'unknown';
      final confidence = data['confidence'];
      final obstacles = data['obstacles'] ?? [];

      print('🎯 Direction: $direction');
      print('📍 Target: ${target ?? 'none'}');
      print('🗺️ Scene: $sceneDescription');
      print('📦 Objects detected: ${objects.length}');
      print('📏 Distance: $distance');
      if (confidence != null) {
        print('🔢 Confidence: ${confidence.toStringAsFixed(2)}');
      }
      if (obstacles.isNotEmpty) {
        print(
          '🚧 Obstacles: ' +
              obstacles
                  .map(
                    (o) =>
                        '${o['name']}(${o['distance']}/${o['position']}/${o['threat']})',
                  )
                  .join(', '),
        );
      }

      // Speak instruction if it's new and not empty
      if (instruction.isNotEmpty && instruction != _lastInstruction) {
        _speakInstruction(instruction);
        _lastInstruction = instruction;
        _lastInstructionTime = DateTime.now();
      }

      // You can also update UI with this information
      _updateUI(data);
    } catch (e) {
      print('❌ Error parsing guidance message: $e');
    }
  }

  Future<void> _speakInstruction(String instruction) async {
    try {
      print('🔊 Speaking: $instruction');
      await _flutterTts?.speak(instruction);
    } catch (e) {
      print('❌ TTS Error: $e');
    }
  }

  void _updateUI(Map<String, dynamic> data) {
    // Update your Flutter UI with:
    // - direction indicator
    // - target information
    // - obstacle warnings
    // - scene description
    // - object overlay on camera preview

    // Example UI updates:
    // onDirectionChanged?.call(data['direction']);
    // onTargetFound?.call(data['target']);
    // onObstaclesDetected?.call(data['obstacles']);
  }

  void dispose() {
    _channel?.sink.close();
    _flutterTts?.stop();
  }
}

// Usage example in a Flutter widget:
class RealtimeGuidanceScreen extends StatefulWidget {
  @override
  _RealtimeGuidanceScreenState createState() => _RealtimeGuidanceScreenState();
}

class _RealtimeGuidanceScreenState extends State<RealtimeGuidanceScreen> {
  CameraController? _cameraController;
  RealtimeGuidanceService? _guidanceService;
  String _currentQuestion = '';
  bool _isProcessing = false;
  DateTime _lastFrameSent = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Initialize guidance service
    _guidanceService = RealtimeGuidanceService();
    await _guidanceService?.initialize();
    await _guidanceService?.connectWebSocket();

    // Initialize camera
    final cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController?.initialize();

      // Start frame capture loop
      _startFrameCapture();
    }
  }

  void _startFrameCapture() {
    Timer.periodic(Duration(milliseconds: 400), (timer) async {
      if (!mounted || _isProcessing) return;

      try {
        _isProcessing = true;
        final image = await _cameraController?.takePicture();
        if (image != null && _currentQuestion.isNotEmpty) {
          await _guidanceService?.sendFrame(image, _currentQuestion);
        }
      } catch (e) {
        print('Error capturing frame: $e');
      } finally {
        _isProcessing = false;
      }
    });
  }

  void _setNavigationTarget(String target) {
    setState(() {
      _currentQuestion = "navigate me to the $target";
    });
    print('🎯 Navigation target set: $_currentQuestion');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Real-time Navigation')),
      body: Stack(
        children: [
          // Camera preview
          if (_cameraController?.value.isInitialized ?? false)
            CameraPreview(_cameraController!),

          // Navigation controls
          Positioned(
            bottom: 50,
            left: 20,
            right: 20,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'What are you looking for?',
                    fillColor: Colors.white.withOpacity(0.8),
                    filled: true,
                  ),
                  onSubmitted: _setNavigationTarget,
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () => _setNavigationTarget('door'),
                      child: Text('Find Door'),
                    ),
                    ElevatedButton(
                      onPressed: () => _setNavigationTarget('chair'),
                      child: Text('Find Chair'),
                    ),
                    ElevatedButton(
                      onPressed: () => _setNavigationTarget('exit'),
                      child: Text('Find Exit'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _guidanceService?.dispose();
    super.dispose();
  }
}

// Enhanced guidance response model
class GuidanceResponse {
  final String? target;
  final String direction;
  final String distance;
  final String instruction;
  final String sceneDescription;
  final List<DetectedObject> objects;
  final List<Obstacle> obstacles;
  final double confidence;
  final double timestamp;

  GuidanceResponse({
    this.target,
    required this.direction,
    required this.distance,
    required this.instruction,
    required this.sceneDescription,
    required this.objects,
    required this.obstacles,
    required this.confidence,
    required this.timestamp,
  });

  factory GuidanceResponse.fromJson(Map<String, dynamic> json) {
    return GuidanceResponse(
      target: json['target'],
      direction: json['direction'] ?? 'unknown',
      distance: json['distance'] ?? 'unknown',
      instruction: json['instruction'] ?? '',
      sceneDescription: json['scene_description'] ?? '',
      objects: (json['objects'] as List<dynamic>? ?? [])
          .map((obj) => DetectedObject.fromJson(obj))
          .toList(),
      obstacles: (json['obstacles'] as List<dynamic>? ?? [])
          .map((obs) => Obstacle.fromJson(obs))
          .toList(),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      timestamp: (json['ts'] ?? 0.0).toDouble(),
    );
  }
}

class DetectedObject {
  final String name;
  final double confidence;
  final int x;
  final int y;
  final int w;
  final int h;

  DetectedObject({
    required this.name,
    required this.confidence,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory DetectedObject.fromJson(Map<String, dynamic> json) => DetectedObject(
    name: json['name'] ?? '',
    confidence: (json['confidence'] ?? 0.0).toDouble(),
    x: (json['x'] ?? 0).toInt(),
    y: (json['y'] ?? 0).toInt(),
    w: (json['w'] ?? 0).toInt(),
    h: (json['h'] ?? 0).toInt(),
  );
}

class Obstacle {
  final String name;
  final String distance;
  final String position;
  final String threat;
  final double confidence;

  Obstacle({
    required this.name,
    required this.distance,
    required this.position,
    required this.threat,
    required this.confidence,
  });

  factory Obstacle.fromJson(Map<String, dynamic> json) {
    return Obstacle(
      name: json['name'] ?? '',
      distance: json['distance'] ?? 'unknown',
      position: json['position'] ?? 'center',
      threat: json['threat'] ?? 'low',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
    );
  }
}
