import 'dart:async';
import 'dart:convert';
// Removed unused imports
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';
import 'camera_service.dart';
import 'audio_service.dart';
import 'haptic_service.dart';

class GuidanceUpdate {
  final String direction;
  final String distance;
  final String instruction;
  final String? target;
  final double? confidence;
  final List<Map<String, dynamic>> obstacles;
  final List<Map<String, dynamic>> objects;
  final String sceneDescription;
  GuidanceUpdate({
    required this.direction,
    required this.distance,
    required this.instruction,
    required this.target,
    required this.confidence,
    required this.obstacles,
    required this.objects,
    required this.sceneDescription,
  });
}

class GuidanceService {
  WebSocketChannel? _channel;
  Timer? _frameTimer;
  bool _running = false;
  String _question = 'navigate me to the door';
  DateTime _lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastInstruction = '';
  final _controller = StreamController<GuidanceUpdate>.broadcast();
  Stream<GuidanceUpdate> get stream => _controller.stream;

  Future<void> start({required String question}) async {
    if (_running) return;
    _question = question;
    _running = true;

    // Ensure camera is ready
    if (!CameraService.isInitialized) {
      await CameraService.initialize();
    }

    final wsUrl = '${ApiConfig.baseUrl.replaceFirst('http', 'ws')}/ws/guide';
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _channel!.stream.listen(
      (raw) {
        try {
          final data = jsonDecode(raw);
          if (data['status'] == 'throttled') return;
          final instr = data['instruction'] ?? '';
          final update = GuidanceUpdate(
            direction: data['direction'] ?? 'unknown',
            distance: data['distance'] ?? 'unknown',
            instruction: instr,
            target: data['target'],
            confidence: (data['confidence'] is num)
                ? (data['confidence'] as num).toDouble()
                : null,
            obstacles:
                (data['obstacles'] as List?)?.cast<Map<String, dynamic>>() ??
                const [],
            objects:
                (data['objects'] as List?)?.cast<Map<String, dynamic>>() ??
                const [],
            sceneDescription: data['scene_description'] ?? '',
          );
          _controller.add(update);

          // Speak only when instruction is non-empty, changed, and not too frequent
          if (instr.isNotEmpty &&
              instr != _lastInstruction &&
              DateTime.now().difference(_lastSpoken).inMilliseconds > 1500) {
            _lastInstruction = instr;
            _lastSpoken = DateTime.now();
            AudioService.speak(instr);
            // Haptic feedback by direction
            switch (update.direction) {
              case 'center':
                HapticService.centerAhead();
                break;
              case 'slightly left':
                HapticService.slightLeft();
                break;
              case 'left':
                HapticService.turnLeft();
                break;
              case 'hard left':
                HapticService.hardTurn();
                break;
              case 'slightly right':
                HapticService.slightRight();
                break;
              case 'right':
                HapticService.turnRight();
                break;
              case 'hard right':
                HapticService.hardTurn();
                break;
            }
          }
        } catch (_) {}
      },
      onError: (e) {
        stop();
      },
      onDone: () {
        stop();
      },
    );

    // Periodically capture frame
    _frameTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (!_running) return;
      var controller = CameraService.controller;
      if (controller == null || !controller.value.isInitialized) return;
      try {
        final pic = await controller.takePicture();
        final bytes = await pic.readAsBytes();
        final b64 = base64Encode(bytes);
        _channel?.sink.add(jsonEncode({'image': b64, 'question': _question}));
      } catch (_) {}
    });

    AudioService.speak('Real time guidance started');
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _frameTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    AudioService.speak('Guidance stopped');
  }

  bool get isRunning => _running;
}
