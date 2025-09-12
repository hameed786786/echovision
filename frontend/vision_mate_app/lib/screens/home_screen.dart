import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import '../providers/vision_mate_provider.dart';
import '../services/camera_service.dart';
import '../services/audio_service.dart';
import '../config/constants.dart';
import '../models/api_models.dart';
import '../widgets/bbox_overlay.dart';

class VisionMateHomePage extends StatefulWidget {
  const VisionMateHomePage({super.key});

  @override
  State<VisionMateHomePage> createState() => _VisionMateHomePageState();
}

class _VisionMateHomePageState extends State<VisionMateHomePage> {
  int _tapCount = 0;
  Timer? _tapTimer;
  String _selectedTarget = 'door';
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VisionMateProvider>().initialize();
      // Announce available gestures when app starts
      Future.delayed(Duration(seconds: 2), () {
        context.read<VisionMateProvider>().announceGestureHelp();
      });
    });
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    CameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _handleTap(context),
          onPanEnd: (details) => _handleSwipeGesture(details, context),
          onDoubleTap: () => _handleDoubleTap(context),
          onLongPress: () => _handleLongPress(context),
          child: Consumer<VisionMateProvider>(
            builder: (context, provider, child) {
              return Stack(
                children: [
                  // Camera preview (if available)
                  _buildCameraPreview(),

                  // Bounding box overlay for detected objects
                  if (provider.lastGuidance != null &&
                      CameraService.controller != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: BBoxOverlay(
                          objects: provider.lastGuidance!.objects
                              .map(
                                (m) => ObjectDetection(
                                  name: m['name'] ?? '',
                                  confidence: (m['confidence'] ?? 0).toDouble(),
                                  x: (m['x'] ?? 0).toInt(),
                                  y: (m['y'] ?? 0).toInt(),
                                  w: (m['w'] ?? 0).toInt(),
                                  h: (m['h'] ?? 0).toInt(),
                                ),
                              )
                              .toList(),
                          previewWidth: 640,
                          previewHeight: 640,
                        ),
                      ),
                    ),

                  // Main content overlay
                  _buildMainContent(provider),

                  // Status indicator
                  _buildStatusIndicator(provider),
                  
                  // Debug button for speech recognition testing
                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: ElevatedButton(
                      onPressed: () => _testSpeechRecognition(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text('Test Speech', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (CameraService.isInitialized && CameraService.controller != null) {
      return Positioned.fill(child: CameraPreview(CameraService.controller!));
    }
    return Container(color: Colors.black);
  }

  Widget _buildMainContent(VisionMateProvider provider) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withOpacity(0.7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App title
          const Text(
            AppStrings.appName,
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            semanticsLabel: AppStrings.appName,
          ),

          const SizedBox(height: 40),

          // Status text
          Text(
            _getStatusText(provider.currentState),
            style: const TextStyle(color: Colors.white70, fontSize: 18),
            textAlign: TextAlign.center,
            semanticsLabel: _getStatusText(provider.currentState),
          ),

          const SizedBox(height: 60),

          // Gesture instructions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    print('Manual button: Describe scene');
                    context.read<VisionMateProvider>().describeScene();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TAP: Test Describe Scene',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    print('Manual button: Ask question');
                    context.read<VisionMateProvider>().askQuestion();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TAP: Test Ask Question',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    print('Manual button: Find specific object');
                    context.read<VisionMateProvider>().findSpecificObject();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TAP: Find Specific Object',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    print('Manual button: Navigate to destination');
                    context.read<VisionMateProvider>().navigateToDestination();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TAP: Navigate To Place',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    print('Manual button: Emergency SOS');
                    context.read<VisionMateProvider>().emergencyMode();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TAP: Test Emergency SOS',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final t in ['door', 'chair', 'exit'])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ChoiceChip(
                          label: Text(
                            t,
                            style: const TextStyle(color: Colors.white),
                          ),
                          selectedColor: Colors.blueAccent,
                          backgroundColor: Colors.grey.withOpacity(0.3),
                          selected: _selectedTarget == t,
                          onSelected: (sel) {
                            if (sel) setState(() => _selectedTarget = t);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    if (provider.guidanceRunning) {
                      provider.stopNavigation();
                    } else {
                      provider.startNavigation(_selectedTarget);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color:
                          (provider.guidanceRunning
                                  ? Colors.orange
                                  : Colors.purple)
                              .withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      provider.guidanceRunning
                          ? 'TAP: Stop Navigation'
                          : 'Start Navigation (${_selectedTarget.toUpperCase()})',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (provider.lastGuidance != null) ...[
                  Text(
                    'Dir: ${provider.lastGuidance!.direction}  Dist: ${provider.lastGuidance!.distance}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    provider.lastGuidance!.instruction,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
                // Light level indicator
                if (CameraService.isInitialized) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Light Level: ${(CameraService.lastBrightnessLevel * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: CameraService.lastBrightnessLevel < 0.3 
                          ? Colors.orange 
                          : Colors.green,
                      fontSize: 14,
                    ),
                  ),
                  if (CameraService.autoFlashlightEnabled)
                    Text(
                      '🤖 Automatic flashlight: ${CameraService.isFlashlightOn ? "ON" : "OFF"}',
                      style: const TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                ],
                const Text(
                  '↑ Swipe Up: Describe surroundings',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  semanticsLabel: 'Swipe up to describe surroundings',
                ),
                const SizedBox(height: 16),
                const Text(
                  '→ Swipe Right: Ask a question',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  semanticsLabel: 'Swipe right to ask a question',
                ),
                const SizedBox(height: 16),
                const Text(
                  '← Swipe Left: Stop audio',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  semanticsLabel: 'Swipe left to stop audio',
                ),
                const SizedBox(height: 16),
                const Text(
                  '↗ Swipe Up-Right: Find specific object',
                  style: TextStyle(color: Colors.orange, fontSize: 16),
                  semanticsLabel: 'Swipe diagonally up and right to find specific object',
                ),
                const SizedBox(height: 16),
                const Text(
                  '↙ Swipe Down-Left: Navigate to place',
                  style: TextStyle(color: Colors.purple, fontSize: 16),
                  semanticsLabel: 'Swipe diagonally down and left to navigate to a place',
                ),
                const SizedBox(height: 16),
                const Text(
                  '↘ Swipe Down-Right: Real-time navigation',
                  style: TextStyle(color: Colors.cyan, fontSize: 16),
                  semanticsLabel: 'Swipe diagonally down and right for continuous real-time navigation',
                ),
                const SizedBox(height: 16),
                const Text(
                  '↓ Swipe Down: Repeat last message',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  semanticsLabel: 'Swipe down to repeat the last message',
                ),
                const SizedBox(height: 16),
                const Text(
                  '← Swipe Left: Stop audio',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  semanticsLabel: 'Swipe left to stop audio',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Double Tap: Stop audio',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  semanticsLabel: 'Double tap to stop audio',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Long Press: Emergency mode',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  semanticsLabel: 'Long press for emergency mode',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(VisionMateProvider provider) {
    Color indicatorColor;
    switch (provider.currentState) {
      case AppState.analyzing:
        indicatorColor = Colors.blue;
        break;
      case AppState.listening:
        indicatorColor = Colors.green;
        break;
      case AppState.processing:
        indicatorColor = Colors.orange;
        break;
      case AppState.speaking:
        indicatorColor = Colors.purple;
        break;
      default:
        indicatorColor = provider.isConnected ? Colors.green : Colors.red;
    }

    return Positioned(
      top: 20,
      right: 20,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: indicatorColor,
          shape: BoxShape.circle,
        ),
        child: Semantics(
          label: 'Status indicator: ${_getStatusText(provider.currentState)}',
          child: const SizedBox(),
        ),
      ),
    );
  }

  void _testSpeechRecognition(BuildContext context) async {
    try {
      print('🧪 Starting speech recognition test...');
      context.read<VisionMateProvider>().announceCurrentAction('Testing speech recognition...');
      
      // Run the test
      bool result = await AudioService.testSpeechRecognition();
      
      String message = result 
        ? 'Speech recognition test passed! Your device supports voice input.'
        : 'Speech recognition test failed. Check microphone permissions.';
        
      context.read<VisionMateProvider>().announceCurrentAction(message);
      print('🧪 Test result: $result');
      
    } catch (e) {
      print('🧪 Test error: $e');
      context.read<VisionMateProvider>().announceCurrentAction('Speech test failed with error: $e');
    }
  }

  void _handleTap(BuildContext context) {
    _tapCount++;
    
    _tapTimer?.cancel();
    _tapTimer = Timer(Duration(milliseconds: 400), () {
      if (_tapCount == 3) {
        print('HomeScreen: Triple tap detected - reading gesture help');
        context.read<VisionMateProvider>().announceGestureHelp();
      } else if (_tapCount == 1) {
        print('HomeScreen: Single tap detected - brief status');
        final provider = context.read<VisionMateProvider>();
        provider.announceCurrentAction('Vision Mate ready. Use gestures to interact.');
      }
      _tapCount = 0;
    });
  }

  void _handleSwipeGesture(DragEndDetails details, BuildContext context) {
    final provider = context.read<VisionMateProvider>();

    // Calculate velocity to determine swipe direction
    final velocity = details.velocity.pixelsPerSecond;
    print(
      'HomeScreen: Gesture detected - velocity: dx=${velocity.dx.toStringAsFixed(1)}, dy=${velocity.dy.toStringAsFixed(1)}',
    );

    // Make gesture detection more sensitive (reduced threshold from 500 to 300)
    const double threshold = 300.0;

    // Swipe up - describe scene (negative dy = upward)
    if (velocity.dy < -threshold) {
      print('HomeScreen: ✅ SWIPE UP detected - describing scene');
      context.read<VisionMateProvider>().announceCurrentAction('Analyzing surroundings');
      provider.describeScene();
    }
    // Swipe right - ask question (positive dx = rightward)
    else if (velocity.dx > threshold) {
      print('HomeScreen: ✅ SWIPE RIGHT detected - asking question');
      context.read<VisionMateProvider>().announceCurrentAction('Ready for your question');
      provider.askQuestion();
    }
    // Diagonal swipe (up-right) - find specific object
    else if (velocity.dx > threshold * 0.7 && velocity.dy < -threshold * 0.7) {
      print('HomeScreen: ✅ DIAGONAL SWIPE (UP-RIGHT) detected - finding specific object');
      context.read<VisionMateProvider>().announceCurrentAction('What object should I find?');
      provider.findSpecificObject();
    }
    // Diagonal swipe (down-left) - navigate to destination
    else if (velocity.dx < -threshold * 0.7 && velocity.dy > threshold * 0.7) {
      print('HomeScreen: ✅ DIAGONAL SWIPE (DOWN-LEFT) detected - navigating to destination');
      context.read<VisionMateProvider>().announceCurrentAction('Where would you like to go?');
      provider.navigateToDestination();
    }
    // Diagonal swipe (down-right) - real-time navigation
    else if (velocity.dx > threshold * 0.7 && velocity.dy > threshold * 0.7) {
      print('HomeScreen: ✅ DIAGONAL SWIPE (DOWN-RIGHT) detected - starting real-time navigation');
      context.read<VisionMateProvider>().announceCurrentAction('Starting real-time navigation');
      provider.startRealTimeNavigation();
    }
    // Swipe down - repeat last message
    else if (velocity.dy > threshold) {
      print('HomeScreen: ✅ SWIPE DOWN detected - repeating last message');
      context.read<VisionMateProvider>().announceCurrentAction('Repeating last message');
      provider.repeatLastMessage();
    }
    // Swipe left - stop audio or real-time navigation
    else if (velocity.dx < -threshold) {
      print('HomeScreen: ✅ SWIPE LEFT detected - stopping audio/navigation');
      final provider = context.read<VisionMateProvider>();
      if (provider.isRealTimeNavigationActive) {
        provider.announceCurrentAction('Stopping real-time navigation');
        provider.stopRealTimeNavigation();
      } else {
        provider.stopAudio();
      }
    } else {
      print(
        'HomeScreen: ❌ Gesture not recognized - velocity too low (threshold: $threshold)',
      );
      print('HomeScreen: Try swiping faster or with more distance');
    }
  }

  void _handleDoubleTap(BuildContext context) {
    print('HomeScreen: Double tap detected - stopping audio');
    final provider = context.read<VisionMateProvider>();
    provider.stopAudio();
  }

  void _handleLongPress(BuildContext context) {
    print('HomeScreen: Long press detected - emergency mode');
    final provider = context.read<VisionMateProvider>();
    provider.emergencyMode();
  }

  String _getStatusText(AppState state) {
    switch (state) {
      case AppState.analyzing:
        return 'Analyzing scene...';
      case AppState.listening:
        return 'Listening for your question...';
      case AppState.processing:
        return 'Processing your request...';
      case AppState.speaking:
        return 'Speaking response...';
      default:
        return 'Ready to assist';
    }
  }
}
