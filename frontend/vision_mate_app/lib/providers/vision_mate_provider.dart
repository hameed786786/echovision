import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import '../models/api_models.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/camera_service.dart';
import '../services/enhanced_camera_service.dart';
import '../services/haptic_service.dart';
import '../services/guidance_service.dart';
import '../config/constants.dart';

enum AppState { idle, analyzing, listening, processing, speaking }

class VisionMateProvider extends ChangeNotifier {
  AppState _currentState = AppState.idle;
  List<ObjectDetection> _lastDetectedObjects = [];
  String _lastSceneDescription = '';
  String _lastAnswer = '';
  bool _isConnected = false;
  bool _lidarAvailable = false;
  Map<String, dynamic> _deviceCapabilities = {};
  final GuidanceService _guidanceService = GuidanceService();
  GuidanceUpdate? _lastGuidance;

  // Getters
  AppState get currentState => _currentState;
  List<ObjectDetection> get lastDetectedObjects => _lastDetectedObjects;
  String get lastSceneDescription => _lastSceneDescription;
  String get lastAnswer => _lastAnswer;
  bool get isConnected => _isConnected;
  bool get lidarAvailable => _lidarAvailable;
  Map<String, dynamic> get deviceCapabilities => _deviceCapabilities;
  bool get guidanceRunning => _guidanceService.isRunning;
  GuidanceUpdate? get lastGuidance => _lastGuidance;

  Future<void> initialize() async {
    try {
      print('VisionMateProvider: Starting initialization...');

      // Initialize all services
      print('VisionMateProvider: Initializing AudioService...');
      await AudioService.initialize();

      print('VisionMateProvider: Initializing CameraService...');
      bool cameraInitialized = await CameraService.initialize();
      if (!cameraInitialized) {
        print('VisionMateProvider: Camera initialization failed');
        return;
      }

      // Initialize enhanced camera service with LiDAR support
      print('VisionMateProvider: Initializing Enhanced Camera Service...');
      bool enhancedCameraReady = await EnhancedCameraService.initialize();
      _lidarAvailable = EnhancedCameraService.hasLiDAR;
      
      // Get detailed capabilities
      _deviceCapabilities = await EnhancedCameraService.getCapabilities();
      
      print('VisionMateProvider: Enhanced camera ready: $enhancedCameraReady');
      print('VisionMateProvider: LiDAR available: $_lidarAvailable');
      print('VisionMateProvider: Device capabilities: $_deviceCapabilities');

      // Check API connection with detailed logging
      print('VisionMateProvider: Checking API connection...');
      print('VisionMateProvider: API URL: ${ApiConfig.baseUrl}');

      _isConnected = await ApiService.checkHealth();

      // 🌐 API CONNECTION STATUS
      print('\n${'🌐' * 40}');
      print('🌐 API CONNECTION CHECK:');
      print('🌐 URL: ${ApiConfig.baseUrl}');
      print('🌐 Status: ${_isConnected ? 'CONNECTED ✅' : 'FAILED ❌'}');
      if (!_isConnected) {
        print('🌐 Check: 1. Backend server running?');
        print('🌐 Check: 2. Same WiFi network?');
        print('🌐 Check: 3. Firewall blocking port 8000?');
      }
      print('🌐' * 40 + '\n');

      print('VisionMateProvider: API connected: $_isConnected');

      // Welcome message
      print('VisionMateProvider: Playing welcome message...');
      await AudioService.speakImportant(AppStrings.welcomeMessage);
      await HapticService.lightVibration();

      print('VisionMateProvider: Initialization complete!');
      notifyListeners();
    } catch (e) {
      print('Error initializing app: $e');
      await AudioService.speakImportant(AppStrings.errorMessage);
      await HapticService.errorPattern();
    }
  }

  Future<void> describeScene() async {
    print('VisionMateProvider: describeScene() called');
    if (_currentState != AppState.idle) {
      print('VisionMateProvider: Not idle, current state: $_currentState');
      return;
    }

    try {
      print('VisionMateProvider: Setting state to analyzing');
      _currentState = AppState.analyzing;
      notifyListeners();

      await HapticService.lightVibration();
      await AudioService.speakStatus('Taking photo and analyzing surroundings...');

      // Ensure camera is initialized first
      print('VisionMateProvider: Checking camera initialization...');
      bool cameraReady = await CameraService.initialize();
      if (!cameraReady) {
        throw Exception('Camera not available or permission denied');
      }
      print('VisionMateProvider: Camera is ready');

      // Capture image
      print('VisionMateProvider: Capturing image...');
      Uint8List? imageBytes = await CameraService.captureImage();
      if (imageBytes == null) {
        throw Exception('Failed to capture image - camera returned null');
      }
      print(
        'VisionMateProvider: Image captured successfully, size: ${imageBytes.length} bytes',
      );

      // Check API connection before sending
      print('VisionMateProvider: Checking API connection...');
      bool apiReady = await ApiService.checkHealth();
      if (!apiReady) {
        throw Exception('Backend server not responding');
      }
      print('VisionMateProvider: API connection confirmed');

      // Analyze scene (both detection and description)
      print('VisionMateProvider: Sending image to AI model for analysis...');
      AnalyzeResponse response = await ApiService.analyzeScene(imageBytes);
      print('VisionMateProvider: AI analysis complete');

      _lastDetectedObjects = response.objects;
      _lastSceneDescription = response.sceneDescription;

      print(
        'VisionMateProvider: Scene description: ${response.sceneDescription}',
      );
      print('VisionMateProvider: Objects detected: ${response.objects.length}');

      // Create a more detailed description with safety information
      String detailedDescription = _createDetailedDescription(
        response.sceneDescription,
        response.objects,
        response.extractedText,
      );

      print('VisionMateProvider: Speaking description: $detailedDescription');
      await AudioService.speakAnnouncement(detailedDescription);
      await HapticService.successPattern();
    } catch (e) {
      print('Error describing scene: $e');
      String errorMessage = 'Error analyzing scene';

      // Provide more specific error messages
      if (e.toString().contains('timeout') ||
          e.toString().contains('SocketException')) {
        errorMessage = 'Server connection timeout. Please try again.';
      } else if (e.toString().contains('Failed to capture image')) {
        errorMessage = 'Camera error. Please try again.';
      } else {
        errorMessage = 'Analysis failed. Please try again.';
      }

      await AudioService.speakImportant(errorMessage);
      await HapticService.errorPattern();
    } finally {
      _currentState = AppState.idle;
      notifyListeners();
    }
  }

  Future<void> askQuestion() async {
    print('VisionMateProvider: askQuestion() called');
    if (_currentState != AppState.idle) {
      print('VisionMateProvider: Not idle, current state: $_currentState');
      await AudioService.speak('Please wait, I am busy.');
      return;
    }

    try {
      print('VisionMateProvider: Setting state to listening');
      _currentState = AppState.listening;
      notifyListeners();

      // Check microphone permissions first
      print('VisionMateProvider: Checking microphone permissions...');
      bool hasPermission = await AudioService.checkMicrophonePermission();
      if (!hasPermission) {
        print('VisionMateProvider: Microphone permission denied');
        await AudioService.speakImportant(
          'I need microphone permission to hear your questions. Please grant microphone access in settings.',
        );
        await HapticService.errorPattern();
        _currentState = AppState.idle;
        notifyListeners();
        return;
      }

      // Provide clear audio feedback
      await AudioService.speakStatus('I am listening. Take your time and ask your question clearly. You have 30 seconds.');
      await HapticService.lightVibration();

      // Longer delay to ensure TTS finishes before starting STT
      await Future.delayed(const Duration(milliseconds: 2000));

      // Add a simple microphone test
      print('VisionMateProvider: Testing microphone availability...');
      bool micAvailable = await AudioService.hasPermission();
      print('VisionMateProvider: Microphone available: $micAvailable');

      // Listen for question with enhanced debugging
      print('VisionMateProvider: Starting voice recognition...');
      String? question = await AudioService.listen(
        timeout: const Duration(seconds: 30), // Increased timeout to give more time for questions
      );
      print('VisionMateProvider: Voice recognition completed');
      print('VisionMateProvider: Recognized question: "$question"');

      if (question == null || question.trim().isEmpty) {
        print('VisionMateProvider: No question received');
        await AudioService.speakImportant(
          'I did not hear any question. Please try again by swiping right. Speak clearly and loudly.',
        );
        await HapticService.errorPattern();
        return;
      }

      print('VisionMateProvider: Processing question: "$question"');
      _currentState = AppState.processing;
      notifyListeners();

      await AudioService.speakStatus('I heard your question. Let me think about it.');

      // Check if we have recent scene data, if not capture new scene
      bool needNewScene =
          _lastSceneDescription.isEmpty || _lastDetectedObjects.isEmpty;
      print('VisionMateProvider: Need new scene data: $needNewScene');

      if (needNewScene) {
        print('VisionMateProvider: Capturing new scene for context...');
        await AudioService.speakStatus(
          'Let me look around first to answer your question.',
        );

        Uint8List? imageBytes = await CameraService.captureImage();
        if (imageBytes != null) {
          print('VisionMateProvider: Analyzing scene for context...');
          AnalyzeResponse response = await ApiService.analyzeScene(imageBytes);
          _lastDetectedObjects = response.objects;
          _lastSceneDescription = response.sceneDescription;
          print('VisionMateProvider: Scene context updated');
        } else {
          print('VisionMateProvider: Failed to capture scene for context');
        }
      }

      // Prepare question request with context
      QuestionRequest request = QuestionRequest(
        question: question,
        sceneDescription: _lastSceneDescription,
        objects: _lastDetectedObjects,
      );

      print('VisionMateProvider: Sending question to AI...');
      print('VisionMateProvider: Question: "${request.question}"');
      print('VisionMateProvider: Scene context: "${request.sceneDescription}"');
      print('VisionMateProvider: Objects count: ${request.objects.length}');

      AnswerResponse response = await ApiService.askQuestion(request);
      _lastAnswer = response.answer;

      print('VisionMateProvider: Received AI answer: "${response.answer}"');

      _currentState = AppState.speaking;
      notifyListeners();

      // Speak the answer
      await AudioService.speakAnnouncement(response.answer);
      await HapticService.successPattern();

      print('VisionMateProvider: Question answered successfully');
    } catch (e) {
      print('VisionMateProvider: Error processing question: $e');
      String errorMessage = 'Sorry, I could not process your question.';

      // Provide specific error messages
      if (e.toString().contains('timeout') ||
          e.toString().contains('SocketException')) {
        errorMessage =
            'Network error. Please check your connection and try again.';
      } else if (e.toString().contains('Camera')) {
        errorMessage = 'Camera error. I could not see your surroundings.';
      } else if (e.toString().contains('Failed to get answer')) {
        errorMessage =
            'AI service error. Please try asking your question again.';
      }

      await AudioService.speakImportant(errorMessage);
      await HapticService.errorPattern();
    } finally {
      _currentState = AppState.idle;
      notifyListeners();
      print('VisionMateProvider: askQuestion() completed, state reset to idle');
    }
  }

  Future<void> stopAudio() async {
    await AudioService.stop();
    if (_currentState == AppState.speaking) {
      _currentState = AppState.idle;
      notifyListeners();
    }
  }

  Future<void> emergencyMode() async {
    try {
      print('VisionMateProvider: Emergency mode activated!');
      await HapticService.errorPattern();
      await AudioService.speakImportant(
        'Emergency mode activated. Calling emergency contact now.',
      );

      // Make emergency call with multiple attempts and formats
      const String emergencyNumber = '+917603871561';
      const String emergencyNumberWithoutPlus = '917603871561';
      const String emergencyNumberLocal = '7603871561';

      print('VisionMateProvider: Attempting to call $emergencyNumber');

      // Try multiple phone number formats for maximum compatibility
      List<String> phoneNumbers = [
        emergencyNumber, // +917603871561 (international format)
        emergencyNumberWithoutPlus, // 917603871561 (without plus)
        emergencyNumberLocal, // 7603871561 (local format)
        '091$emergencyNumberLocal', // 09117603871561 (trunk prefix)
      ];

      // Try multiple URI schemes and formats
      List<Uri> phoneUris = [];

      for (String number in phoneNumbers) {
        phoneUris.addAll([
          Uri(scheme: 'tel', path: number),
          Uri.parse('tel:$number'),
          Uri.parse('tel://$number'),
          Uri.parse('callto:$number'),
        ]);
      }

      bool callSuccessful = false;

      for (Uri phoneUri in phoneUris) {
        try {
          print('VisionMateProvider: Trying URI format: $phoneUri');

          bool canLaunch = await canLaunchUrl(phoneUri);
          print('VisionMateProvider: Can launch $phoneUri: $canLaunch');

          if (canLaunch) {
            bool launched = await launchUrl(
              phoneUri,
              mode: LaunchMode.externalApplication,
            );
            print('VisionMateProvider: Launch result: $launched');

            if (launched) {
              callSuccessful = true;
              await AudioService.speakImportant(
                'Emergency call initiated successfully.',
              );
              break;
            }
          }
        } catch (e) {
          print('VisionMateProvider: Error with URI format $phoneUri: $e');
          continue;
        }
      }

      if (!callSuccessful) {
        print('VisionMateProvider: All call attempts failed');
        await AudioService.speakImportant(
          'Cannot make automatic call. Emergency number is $emergencyNumber. Please dial manually immediately.',
        );

        // Try opening the dialer with different number formats as fallback
        List<String> fallbackNumbers = [
          emergencyNumber,
          emergencyNumberWithoutPlus,
          emergencyNumberLocal,
        ];

        for (String number in fallbackNumbers) {
          try {
            print('VisionMateProvider: Trying dialer fallback with: $number');
            final Uri dialerUri = Uri.parse('tel:$number');
            bool opened = await launchUrl(
              dialerUri,
              mode: LaunchMode.externalApplication,
            );
            if (opened) {
              print(
                'VisionMateProvider: Dialer opened successfully with $number',
              );
              break;
            }
          } catch (e) {
            print('VisionMateProvider: Dialer fallback failed for $number: $e');
            continue;
          }
        }
      }

      // Capture image for emergency record
      print('VisionMateProvider: Capturing emergency photo...');
      Uint8List? imageBytes = await CameraService.captureImage();
      if (imageBytes != null) {
        print(
          'VisionMateProvider: Emergency photo captured (${imageBytes.length} bytes)',
        );
        await AudioService.speakAnnouncement('Emergency photo captured for your safety.');
      } else {
        print('VisionMateProvider: Failed to capture emergency photo');
      }
    } catch (e) {
      print('VisionMateProvider: Emergency mode error: $e');
      await AudioService.speakImportant(
        'Emergency mode failed. Please call +917603871561 manually immediately.',
      );
    }
  }

  Future<void> startNavigation(String target) async {
    if (_guidanceService.isRunning) return;
    final q = 'navigate me to the $target';
    _guidanceService.stream.listen((g) {
      _lastGuidance = g;
      notifyListeners();
    });
    await _guidanceService.start(question: q);
    notifyListeners();
  }

  Future<void> stopNavigation() async {
    await _guidanceService.stop();
    notifyListeners();
  }

  String _createDetailedDescription(
    String baseDescription,
    List<ObjectDetection> objects,
    String? extractedText,
  ) {
    List<String> safetyAlerts = [];
    List<String> objectList = [];

    for (ObjectDetection obj in objects) {
      if (obj.confidence > 0.7) {
        objectList.add(obj.toString());

        // Add safety alerts for specific objects
        switch (obj.name.toLowerCase()) {
          case 'car':
          case 'truck':
          case 'bus':
            safetyAlerts.add('Vehicle detected. Be cautious.');
            break;
          case 'person':
            safetyAlerts.add('Person nearby.');
            break;
          case 'bicycle':
          case 'motorcycle':
            safetyAlerts.add('Moving vehicle detected. Stay alert.');
            break;
          case 'stop sign':
            safetyAlerts.add('Stop sign detected.');
            break;
          case 'traffic light':
            safetyAlerts.add('Traffic light ahead.');
            break;
        }
      }
    }

    String result = baseDescription;

    if (objectList.isNotEmpty) {
      result += ' Objects detected: ${objectList.take(5).join(', ')}.';
    }

    if (safetyAlerts.isNotEmpty) {
      result += ' Safety alerts: ${safetyAlerts.take(3).join(' ')}.';
    }

    // Add extracted text if available
    if (extractedText != null && extractedText.trim().isNotEmpty) {
      result += ' Text detected: $extractedText.';
    }

    return result;
  }

  Future<void> findSpecificObject() async {
    print('VisionMateProvider: findSpecificObject() called');
    if (_currentState != AppState.idle) {
      print('VisionMateProvider: Not idle, current state: $_currentState');
      return;
    }

    try {
      _currentState = AppState.listening;
      notifyListeners();

      await HapticService.lightVibration();
      await AudioService.speakStatus('What object are you looking for? Take your time, you have 30 seconds.');

      // Listen for user's voice command with extended timeout
      String? voiceCommand = await AudioService.listen(timeout: Duration(seconds: 30));
      if (voiceCommand?.trim().isEmpty ?? true) {
        await AudioService.speakImportant('No voice command received. Please try again.');
        return;
      }

      print('VisionMateProvider: Voice command received: "$voiceCommand"');
      
      _currentState = AppState.analyzing;
      notifyListeners();

      await AudioService.speakStatus('Got it! Searching for $voiceCommand...');
      await Future.delayed(Duration(milliseconds: 800)); // Give time for speech

      // Capture image
      await AudioService.speakStatus('Taking a picture...');
      Uint8List? imageBytes = await CameraService.captureImage();
      if (imageBytes == null) {
        throw Exception('Failed to capture image');
      }

      // Send to backend for specific object detection
      _currentState = AppState.processing;
      notifyListeners();

      await AudioService.speakStatus('Analyzing the image for your object...');

      final response = await ApiService.findObject(imageBytes, voiceCommand!);
      
      if (response != null) {
        _currentState = AppState.speaking;
        notifyListeners();

        String message = response['message'] ?? 'Search completed';
        await AudioService.speakAnnouncement(message);
        
        if (response['status'] == 'found') {
          await HapticService.successPattern();
          
          // Provide enhanced positioning information
          if (response['precise_position'] != null) {
            Map<String, dynamic> precisePos = response['precise_position'];
            
            // Wait a moment then provide navigation details
            await Future.delayed(Duration(milliseconds: 1200));
            
            // Announce turn-by-turn navigation with proper pacing
            if (precisePos['navigation_steps'] != null) {
              List<dynamic> steps = precisePos['navigation_steps'];
              await AudioService.speakInstruction('Here are your navigation steps:');
              
              for (int i = 0; i < steps.length && i < 3; i++) {
                await Future.delayed(Duration(milliseconds: 1000)); // Better pacing
                await AudioService.speakInstruction('Step ${i + 1}: ${steps[i].toString()}');
              }
            }
            
            // Provide distance guidance with better timing
            if (precisePos['distance_guidance'] != null) {
              await Future.delayed(Duration(milliseconds: 1000));
              await AudioService.speakInstruction('Distance guidance: ${precisePos['distance_guidance']}');
            }
          }
          
          // Legacy support for basic positioning
          else if (response['position'] != null && response['distance'] != null) {
            String position = response['position'] ?? '';
            String distance = response['distance'] ?? '';
            if (position.isNotEmpty && distance.isNotEmpty) {
              await Future.delayed(Duration(milliseconds: 500));
              await AudioService.speakAnnouncement('The object is $distance and positioned $position relative to your view.');
            }
          }
        } else {
          await HapticService.mediumVibration();
          
          // Suggest alternatives if available
          List<dynamic> allDetected = response['all_detected'] ?? [];
          if (allDetected.isNotEmpty) {
            await Future.delayed(Duration(milliseconds: 500));
            String alternatives = allDetected
                .take(3)
                .map((obj) => obj['name'])
                .join(', ');
            await AudioService.speakAnnouncement('However, I can see: $alternatives');
          }
          
          // Announce suggestions if available
          if (response['suggestions'] != null) {
            List<dynamic> suggestions = response['suggestions'];
            if (suggestions.isNotEmpty) {
              await Future.delayed(Duration(milliseconds: 600));
              await AudioService.speakAnnouncement('Did you mean: ${suggestions.join(', ')}?');
            }
          }
        }
      } else {
        throw Exception('No response from server');
      }

    } catch (e) {
      print('VisionMateProvider Error in findSpecificObject: $e');
      _currentState = AppState.speaking;
      notifyListeners();

      String errorMessage = 'Could not search for object. Please try again.';
      if (e.toString().contains('timeout')) {
        errorMessage = 'Server connection timeout. Please try again.';
      }

      await AudioService.speakImportant(errorMessage);
      await HapticService.errorPattern();
    } finally {
      _currentState = AppState.idle;
      notifyListeners();
    }
  }

  Future<void> navigateToDestination() async {
    print('VisionMateProvider: navigateToDestination() called');
    if (_currentState != AppState.idle) {
      print('VisionMateProvider: Not idle, current state: $_currentState');
      return;
    }

    try {
      _currentState = AppState.listening;
      notifyListeners();

      await HapticService.lightVibration();
      await AudioService.speakStatus('Where would you like to go? Describe the place or object.');

      // Listen for user's destination
      String? destination = await AudioService.listen(timeout: Duration(seconds: 10));
      if (destination?.trim().isEmpty ?? true) {
        await AudioService.speakImportant('No destination received. Please try again.');
        return;
      }

      print('VisionMateProvider: Destination received: "$destination"');
      
      _currentState = AppState.analyzing;
      notifyListeners();

      await AudioService.speakStatus('Finding path to $destination...');

      // Capture image
      Uint8List? imageBytes = await CameraService.captureImage();
      if (imageBytes == null) {
        throw Exception('Failed to capture image');
      }

      // Send to backend for navigation guidance
      _currentState = AppState.processing;
      notifyListeners();

      final response = await ApiService.navigateTo(imageBytes, destination!);
      
      if (response != null) {
        _currentState = AppState.speaking;
        notifyListeners();

        String message = response['response'] ?? 'Navigation completed';
        await AudioService.speakAnnouncement(message);
        
        if (response['found'] == true) {
          await HapticService.successPattern();
          
          // Provide enhanced turn-by-turn navigation
          if (response['step_by_step_navigation'] != null) {
            List<dynamic> steps = response['step_by_step_navigation'];
            
            await Future.delayed(Duration(milliseconds: 800));
            await AudioService.speakInstruction('Turn by turn navigation:');
            
            for (int i = 0; i < steps.length && i < 4; i++) {
              await Future.delayed(Duration(milliseconds: 700));
              await AudioService.speakInstruction(steps[i].toString());
            }
          }
          
          // Provide enhanced directional guidance with precise angles
          if (response['direction'] != null) {
            Map<String, dynamic> direction = response['direction'];
            
            await Future.delayed(Duration(milliseconds: 800));
            
            // Announce precise heading instruction
            if (direction['heading_instruction'] != null) {
              await AudioService.speakInstruction('Heading: ${direction['heading_instruction']}');
            }
            
            // Announce movement instruction
            if (direction['movement_instruction'] != null) {
              await Future.delayed(Duration(milliseconds: 600));
              await AudioService.speakInstruction('Movement: ${direction['movement_instruction']}');
            }
            
            // Announce estimated time if available
            if (response['navigation'] != null && response['navigation']['estimated_time'] != null) {
              await Future.delayed(Duration(milliseconds: 600));
              await AudioService.speakAnnouncement('Estimated time: ${response['navigation']['estimated_time']}');
            }
          }
          
          // Legacy support for basic directional guidance
          else if (response['direction'] != null) {
            Map<String, dynamic> direction = response['direction'];
            List<String> guidance = [];
            
            if (direction['horizontal'] != null && direction['horizontal'] != 'Continue straight') {
              guidance.add(direction['horizontal']);
            }
            if (direction['vertical'] != null) {
              guidance.add(direction['vertical']);
            }
            
            if (guidance.isNotEmpty) {
              await Future.delayed(Duration(milliseconds: 800));
              await AudioService.speakAnnouncement('Direction: ${guidance.join(', ')}');
            }
            
            // Provide distance information
            if (direction['distance'] != null) {
              await Future.delayed(Duration(milliseconds: 500));
              await AudioService.speakAnnouncement('Distance: ${direction['distance']}');
            }
          }
        } else {
          await HapticService.mediumVibration();
          
          // Provide enhanced environmental context and recommendations
          if (response['recommended_action'] != null) {
            await Future.delayed(Duration(milliseconds: 600));
            await AudioService.speakAnnouncement('Recommendation: ${response['recommended_action']}');
          }
          
          // Provide environmental context
          if (response['environment'] != null) {
            await Future.delayed(Duration(milliseconds: 500));
            await AudioService.speakAnnouncement('Current environment: ${response['environment']}');
          }
          
          // Mention obstacles with precise positioning
          if (response['obstacles'] != null) {
            List<dynamic> obstacles = response['obstacles'];
            if (obstacles.isNotEmpty) {
              await Future.delayed(Duration(milliseconds: 500));
              String obstacleText = obstacles.take(2).join(', ');
              await AudioService.speakAnnouncement('Nearby objects: $obstacleText');
            }
          }
          
          // Provide exploration suggestions
          if (response['exploration_suggestions'] != null) {
            List<dynamic> suggestions = response['exploration_suggestions'];
            if (suggestions.isNotEmpty) {
              await Future.delayed(Duration(milliseconds: 700));
              await AudioService.speakAnnouncement('Try: ${suggestions[0]}');
            }
          }
        }
      } else {
        throw Exception('No response from server');
      }

    } catch (e) {
      print('VisionMateProvider Error in navigateToDestination: $e');
      _currentState = AppState.speaking;
      notifyListeners();

      String errorMessage = 'Could not provide navigation. Please try again.';
      if (e.toString().contains('timeout')) {
        errorMessage = 'Server connection timeout. Please try again.';
      }

      await AudioService.speakImportant(errorMessage);
      await HapticService.errorPattern();
    } finally {
      _currentState = AppState.idle;
      notifyListeners();
    }
  }

  // Add accessibility methods with proper audio sequencing
  Future<void> announceGestureHelp() async {
    String helpText = '''
Welcome to Vision Mate. Here are your gesture commands:
Swipe up to describe your surroundings.
Swipe right to ask a question about what you see.
Swipe left to stop current audio.
Swipe down to repeat the last message.
Diagonal swipe up and right to find a specific object.
Diagonal swipe down and left to navigate to a place.
Double tap to stop audio.
Long press for emergency mode.
Triple tap to hear this help again.
Note: Flashlight turns on automatically in low light conditions.
''';
    await AudioService.speakImportant(helpText);
  }

  Future<void> announceCurrentAction(String action) async {
    await AudioService.speakStatus(action);
    await HapticService.lightVibration();
  }

  Future<void> repeatLastMessage() async {
    if (_lastSceneDescription.isNotEmpty) {
      await AudioService.speakAnnouncement(_lastSceneDescription);
    } else if (_lastAnswer.isNotEmpty) {
      await AudioService.speakAnnouncement(_lastAnswer);
    } else {
      await AudioService.speakStatus('No previous message to repeat.');
    }
  }

  @override
  void dispose() {
    _guidanceService.stop();
    CameraService.dispose();
    super.dispose();
  }
}
