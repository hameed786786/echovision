import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:collection';
import 'dart:async';
import '../config/constants.dart';

class AudioService {
  static final FlutterTts _flutterTts = FlutterTts();
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _isInitialized = false;
  
  // Audio queue management
  static final Queue<String> _speechQueue = Queue<String>();
  static bool _isSpeaking = false;
  static bool _isProcessingQueue = false;
  static Completer<void>? _currentSpeechCompleter;

  // Test method to check speech recognition status
  static Future<bool> testSpeechRecognition() async {
    try {
      bool available = await _speech.initialize(
        debugLogging: true,
        onError: (error) {
          print('🔍 Speech Test Error: ${error.errorMsg}');
          print('🔍 Permanent: ${error.permanent}');
        },
      );
      
      print('🔍 Speech Test Available: $available');
      print('🔍 Has Permission: ${await _speech.hasPermission}');
      print('🔍 Is Available: ${_speech.isAvailable}');
      print('🔍 Is Listening: ${_speech.isListening}');
      
      return available;
    } catch (e) {
      print('🔍 Speech Test Exception: $e');
      return false;
    }
  }

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize TTS with completion handler
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setPitch(AppConstants.speechPitch);
      await _flutterTts.setVolume(AppConstants.speechVolume);
      await _flutterTts.setSpeechRate(0.5); // Slower speech for better comprehension

      // Set completion handler to manage queue
      _flutterTts.setCompletionHandler(() {
        print('AudioService: Speech completed');
        _isSpeaking = false;
        _currentSpeechCompleter?.complete();
        _currentSpeechCompleter = null;
        _processNextInQueue();
      });

      _flutterTts.setErrorHandler((msg) {
        print('AudioService: TTS Error: $msg');
        _isSpeaking = false;
        _currentSpeechCompleter?.complete();
        _currentSpeechCompleter = null;
        _processNextInQueue();
      });

      // Initialize STT with better configuration
      bool available = await _speech.initialize(
        onStatus: (val) {
          print('STT status: $val');
          if (val == 'listening') {
            print('🎙️ Microphone is active - ready for speech');
          } else if (val == 'notListening') {
            print('🔇 Speech recognition stopped');
          }
        },
        onError: (val) {
          print('STT error: $val');
          if (val.errorMsg == 'error_no_match') {
            print('⚠️ No speech detected - make sure to speak clearly');
          } else if (val.errorMsg == 'error_speech_timeout') {
            print('⏰ Speech timeout - no speech detected in time limit');
          }
        },
      );

      if (!available) {
        print('⚠️ Speech recognition not available on this device');
      } else {
        print('✅ Speech recognition initialized successfully');
        
        // Get available locales for debugging
        try {
          List<stt.LocaleName> locales = await _speech.locales();
          print('Available speech locales: ${locales.take(5).map((l) => l.localeId).join(', ')}...');
        } catch (e) {
          print('Could not get locales: $e');
        }
      }

      _isInitialized = true;
      print('AudioService: Initialized successfully with queue management');
    } catch (e) {
      print('Error initializing audio service: $e');
    }
  }

  static Future<void> speak(String text, {bool priority = false}) async {
    if (!_isInitialized) await initialize();

    print('AudioService: Adding to queue: "$text" (Priority: $priority)');

    try {
      if (priority) {
        // High priority - stop current speech and clear queue
        await stopImmediate();
        _speechQueue.clear();
        _speechQueue.addFirst(text);
      } else {
        // Normal priority - add to end of queue
        _speechQueue.add(text);
      }

      // Start processing queue if not already processing
      if (!_isProcessingQueue) {
        _processQueue();
      }
    } catch (e) {
      print('Error queueing speech: $e');
    }
  }

  static Future<void> _processQueue() async {
    if (_isProcessingQueue || _speechQueue.isEmpty) return;

    _isProcessingQueue = true;
    print('AudioService: Started processing speech queue (${_speechQueue.length} items)');

    while (_speechQueue.isNotEmpty) {
      String text = _speechQueue.removeFirst();
      await _speakDirectly(text);
    }

    _isProcessingQueue = false;
    print('AudioService: Finished processing speech queue');
  }

  static void _processNextInQueue() {
    if (_speechQueue.isNotEmpty && !_isSpeaking) {
      String nextText = _speechQueue.removeFirst();
      _speakDirectly(nextText);
    }
  }

  static Future<void> _speakDirectly(String text) async {
    if (_isSpeaking) {
      print('AudioService: Already speaking, waiting...');
      return;
    }

    _isSpeaking = true;
    _currentSpeechCompleter = Completer<void>();
    
    print('AudioService: Speaking: "$text"');

    try {
      await _flutterTts.speak(text);
      // Wait for completion handler to be called
      await _currentSpeechCompleter!.future.timeout(
        Duration(seconds: text.length ~/ 2 + 10), // Estimate max time needed
        onTimeout: () {
          print('AudioService: Speech timeout, continuing...');
          _isSpeaking = false;
          _currentSpeechCompleter?.complete();
          _currentSpeechCompleter = null;
        },
      );
    } catch (e) {
      print('Error in direct speech: $e');
      _isSpeaking = false;
      _currentSpeechCompleter?.complete();
      _currentSpeechCompleter = null;
    }
  }

  static Future<void> stop() async {
    try {
      print('AudioService: Stopping audio and clearing queue');
      _speechQueue.clear();
      await _flutterTts.stop();
      await _speech.stop();
      _isSpeaking = false;
      _isProcessingQueue = false;
      _currentSpeechCompleter?.complete();
      _currentSpeechCompleter = null;
    } catch (e) {
      print('Error stopping audio: $e');
    }
  }

  static Future<void> stopImmediate() async {
    try {
      await _flutterTts.stop();
      _isSpeaking = false;
      _currentSpeechCompleter?.complete();
      _currentSpeechCompleter = null;
    } catch (e) {
      print('Error stopping immediate audio: $e');
    }
  }

  // Enhanced speak methods for different priorities
  static Future<void> speakImportant(String text) async {
    await speak(text, priority: true);
  }

  static Future<void> speakAnnouncement(String text) async {
    await speak(text, priority: false);
  }

  static Future<void> speakInstruction(String text) async {
    await speak("Instruction: $text", priority: false);
  }

  static Future<void> speakStatus(String text) async {
    await speak(text, priority: false);
  }

  static int get queueLength => _speechQueue.length;
  static bool get isBusy => _isSpeaking || _isProcessingQueue || _speechQueue.isNotEmpty;

  static Future<String?> listen({Duration? timeout}) async {
    print('AudioService: listen() called with timeout: ${timeout?.inSeconds ?? 10}s');

    if (!_isInitialized) {
      print('AudioService: Not initialized, initializing now...');
      await initialize();
    }

    try {
      // Force complete cleanup and reinitialize speech recognition
      print('AudioService: Performing complete speech recognition reset...');
      
      // Force stop TTS to avoid conflicts with STT
      if (_isSpeaking || _isProcessingQueue || _speechQueue.isNotEmpty) {
        print('AudioService: Force stopping TTS before STT...');
        await stopImmediate();
        _speechQueue.clear();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Stop any existing speech recognition session with extended wait
      if (_speech.isListening) {
        print('AudioService: Stopping existing listening session...');
        await _speech.stop();
        await Future.delayed(const Duration(milliseconds: 1000)); // Longer wait
      }

      // Force reinitialize the speech recognizer completely
      print('AudioService: Reinitializing speech recognizer...');
      
      // First run a speech test to validate functionality
      print('🧪 Running speech recognition test...');
      bool testResult = await testSpeechRecognition();
      if (!testResult) {
        print('❌ Speech recognition test failed - device may not support speech recognition');
      }
      
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('AudioService: STT Status: $status');
          if (status == 'listening') {
            print('🎙️ Microphone is active - ready for speech');
          } else if (status == 'notListening') {
            print('🔇 Speech recognition stopped');
          } else if (status == 'done') {
            print('✅ Speech recognition session completed');
          }
        },
        onError: (error) {
          print('AudioService: STT Error: ${error.errorMsg}');
          print('AudioService: Error permanent: ${error.permanent}');
          if (error.errorMsg == 'error_no_match') {
            print('! No speech detected - make sure to speak clearly');
          } else if (error.errorMsg == 'error_speech_timeout') {
            print('! Speech timeout - try speaking sooner');
          } else if (error.errorMsg == 'error_audio') {
            print('! Audio error - check microphone permissions');
          }
        },
        debugLogging: true,
      );

      if (!available) {
        print('❌ Speech recognition not available');
        print('💡 Checking microphone permissions...');
        
        // Try to check permissions
        bool hasPermission = await _speech.hasPermission;
        if (!hasPermission) {
          print('❌ Microphone permission denied');
          print('💡 Please grant microphone permission in device settings');
        } else {
          print('✅ Microphone permission granted');
          print('❌ Speech recognition service unavailable');
        }
        return null;
      }

      print('✅ Speech recognition initialized successfully');

      // Double-check that speech recognition is ready
      if (!_speech.isAvailable) {
        print('❌ Speech recognition still not available after initialization');
        return null;
      }

      String? finalResult;
      bool sessionComplete = false;
      Completer<void> listeningCompleter = Completer<void>();

      print('\n🎙️ STARTING FRESH SPEECH RECOGNITION SESSION 🎙️');
      print('You have ${timeout?.inSeconds ?? 30} seconds to speak...');
      print('The app will wait 6 seconds after you stop speaking...');
      print('Speak clearly now!\n');

      // Add a small delay before actually starting to listen
      await Future.delayed(const Duration(milliseconds: 500)); // Increased delay

      // Simple listen call with improved parameters for better recognition
      await _speech.listen(
        onResult: (result) {
          print('🎤 Result: "${result.recognizedWords}"');
          print('   Final: ${result.finalResult}');
          print('   Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%');
          
          if (result.finalResult) {
            finalResult = result.recognizedWords;
            sessionComplete = true;
            if (!listeningCompleter.isCompleted) {
              listeningCompleter.complete();
            }
          } else {
            // Update partial result
            finalResult = result.recognizedWords;
          }
        },
        listenFor: timeout ?? const Duration(seconds: 30), // Total listening time
        pauseFor: const Duration(seconds: 3), // Reduced pause - too long might cause timeout
        partialResults: true,
        cancelOnError: false,
        localeId: 'en_US', // Explicit locale
        onSoundLevelChange: (level) {
          // Log sound levels to help debug microphone issues
          if (level > 0.1) {
            print('🔊 Sound detected: level ${level.toStringAsFixed(2)}');
          }
        },
      );

      // Wait for completion or timeout
      try {
        await listeningCompleter.future.timeout(
          timeout ?? const Duration(seconds: 35), // Timeout buffer
          onTimeout: () {
            print('⏰ Speech recognition timeout');
            sessionComplete = true;
          },
        );
      } catch (e) {
        print('❌ Listening timeout: $e');
      }

      // Force stop and cleanup
      if (_speech.isListening) {
        print('AudioService: Force stopping speech recognition...');
        await _speech.stop();
      }

      // Additional cleanup wait
      await Future.delayed(const Duration(milliseconds: 500));

      print('\n📝 SPEECH RECOGNITION RESULT:');
      print('Final text: "${finalResult ?? 'NONE'}"');
      print('Session complete: $sessionComplete');

      if (finalResult != null && finalResult!.trim().isNotEmpty) {
        String cleanResult = finalResult!.trim();
        print('✅ SUCCESS: "$cleanResult"');
        return cleanResult;
      } else {
        print('❌ NO SPEECH DETECTED');
        print('💡 Troubleshooting tips:');
        print('   - Speak louder and more clearly');
        print('   - Get closer to the device microphone');
        print('   - Try speaking immediately after the beep');
        print('   - Check if microphone permissions are granted');
        print('   - Ensure you\'re in a quiet environment');
        return null;
      }

    } catch (e) {
      print('❌ Speech recognition error: $e');
      
      // Force cleanup on error
      try {
        if (_speech.isListening) {
          await _speech.stop();
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (stopError) {
        print('Error stopping speech: $stopError');
      }
      
      return null;
    }
  }

  static bool get isListening => _speech.isListening;

  static Future<bool> hasPermission() async {
    try {
      return await _speech.hasPermission;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> checkMicrophonePermission() async {
    try {
      if (!_isInitialized) await initialize();
      
      bool hasPermission = await _speech.hasPermission;
      print('AudioService: Microphone permission status: $hasPermission');
      
      if (!hasPermission) {
        print('AudioService: Attempting to request microphone permission...');
        bool granted = await _speech.initialize(
          onStatus: (val) => print('Permission STT status: $val'),
          onError: (val) => print('Permission STT error: $val'),
        );
        print('AudioService: Permission request result: $granted');
        return granted;
      }
      
      return true;
    } catch (e) {
      print('AudioService: Error checking microphone permission: $e');
      return false;
    }
  }
}
