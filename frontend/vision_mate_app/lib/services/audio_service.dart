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
    print(
      'AudioService: listen() called with timeout: ${timeout?.inSeconds ?? 10}s',
    );

    if (!_isInitialized) {
      print('AudioService: Not initialized, initializing now...');
      await initialize();
    }

    try {
      // Re-initialize speech recognition with proper error handling
      print('AudioService: Re-initializing speech recognition...');
      bool available = await _speech.initialize(
        onStatus: (val) {
          print('AudioService: STT status: $val');
          if (val == 'listening') {
            print('🎙️ MICROPHONE IS NOW ACTIVE - SPEAK NOW!');
          }
        },
        onError: (val) {
          print('AudioService: STT error: $val');
          if (val.errorMsg == 'error_no_match') {
            print('🔇 NO SPEECH DETECTED - Try speaking louder or closer to microphone');
          }
        },
      );

      if (!available) {
        print('AudioService: Speech recognition not available on this device');
        return null;
      }

      print('AudioService: Speech recognition initialized successfully');

      // Check available locales
      List<stt.LocaleName> locales = await _speech.locales();
      print('AudioService: Available locales: ${locales.map((l) => '${l.localeId} (${l.name})').join(', ')}');

      // Find best English locale
      stt.LocaleName? englishLocale = locales.firstWhere(
        (locale) => locale.localeId.toLowerCase().startsWith('en'),
        orElse: () => locales.isNotEmpty ? locales.first : stt.LocaleName('en-US', 'English (US)'),
      );
      print('AudioService: Selected locale: ${englishLocale.localeId} (${englishLocale.name})');

      // Check microphone permission
      bool hasPermission = await _speech.hasPermission;
      print('AudioService: Has microphone permission: $hasPermission');

      if (!hasPermission) {
        print('AudioService: Requesting microphone permission...');
        // Try to initialize again to request permissions
        bool permissionGranted = await _speech.initialize(
          onStatus: (val) => print('AudioService: Permission STT status: $val'),
          onError: (val) => print('AudioService: Permission STT error: $val'),
        );
        if (!permissionGranted) {
          print('AudioService: Microphone permission denied');
          return null;
        }
        print('AudioService: Microphone permission granted');
      }

      String? recognizedText;
      bool isComplete = false;

      // 🎙️ LISTENING START BANNER
      print('\n${'🎙️' * 35}');
      print('🎙️ STARTING SPEECH RECOGNITION');
      print('🎙️ Timeout: ${timeout?.inSeconds ?? 15} seconds');
      print('🎙️ Locale: ${englishLocale.localeId}');
      print('🎙️ Please speak clearly and loudly...');
      print('🎙️' * 35 + '\n');

      print('AudioService: Starting to listen...');

      // Enhanced listening with better parameters
      await _speech.listen(
        onResult: (val) {
          recognizedText = val.recognizedWords;

          // 🎤 CLEAR SPEECH TEXT DISPLAY IN TERMINAL
          print('=' * 60);
          print('🎤 SPEECH RECOGNIZED:');
          print('   Text: "${recognizedText ?? 'No text'}"');
          print('   Type: ${val.finalResult ? 'FINAL' : 'PARTIAL'}');
          print('   Confidence: ${(val.confidence * 100).toStringAsFixed(1)}%');
          print('   Has alternatives: ${val.alternates.isNotEmpty}');
          if (val.alternates.isNotEmpty) {
            print('   Alternatives: ${val.alternates.map((alt) => '"${alt.recognizedWords}" (${(alt.confidence * 100).toStringAsFixed(1)}%)').join(', ')}');
          }
          print('=' * 60);

          // Additional debugging info
          print('AudioService: Partial result: "$recognizedText"');
          print('AudioService: Is final result: ${val.finalResult}');
          print('AudioService: Confidence: ${val.confidence}');

          if (val.finalResult) {
            isComplete = true;
            print('AudioService: Final result received!');

            // 🎯 FINAL SPEECH RESULT BANNER
            print('\n${'🎯' * 30}');
            print('🎯 FINAL SPEECH RESULT:');
            print('🎯 "${recognizedText ?? 'No text recognized'}"');
            print('🎯' * 30 + '\n');
          }
        },
        onSoundLevelChange: (level) {
          // Only log significant sound levels to avoid spam
          if (level > 0.1) {
            print('AudioService: Sound level: ${level.toStringAsFixed(2)} (Good!)');
          } else if (level > 0.01) {
            print('AudioService: Sound level: ${level.toStringAsFixed(3)} (Quiet)');
          }
        },
        localeId: englishLocale.localeId,
        listenFor: timeout ?? const Duration(seconds: 20), // Increased timeout
        pauseFor: const Duration(seconds: 2), // Reduced pause duration
        partialResults: true, // Enable partial results for better feedback
        cancelOnError: false, // Don't cancel on error, continue listening
        listenMode: stt.ListenMode.confirmation, // Use confirmation mode for better accuracy
      );

      print('AudioService: Listening started, waiting for speech...');

      // Wait for listening to complete or timeout
      int waitTime = 0;
      int maxWaitTime = (timeout?.inMilliseconds ?? 20000);

      while (!isComplete && _speech.isListening && waitTime < maxWaitTime) {
        await Future.delayed(const Duration(milliseconds: 300));
        waitTime += 300;

        // Log progress every 3 seconds with tips
        if (waitTime % 3000 == 0) {
          int secondsElapsed = waitTime ~/ 1000;
          print('AudioService: Still listening... ${secondsElapsed}s elapsed');
          print('AudioService: Is listening: ${_speech.isListening}');
          print('AudioService: Current text: "$recognizedText"');
          
          if (secondsElapsed == 6 && (recognizedText == null || recognizedText!.isEmpty)) {
            print('💡 TIP: Speak clearly and loudly. Make sure you\'re close to the microphone.');
          } else if (secondsElapsed == 12 && (recognizedText == null || recognizedText!.isEmpty)) {
            print('💡 TIP: Try speaking a simple phrase like "What is this?" or "Describe this scene"');
          }
        }
      }

      // Stop listening if still active
      if (_speech.isListening) {
        print('AudioService: Stopping speech recognition...');
        await _speech.stop();
      }

      print('AudioService: Listening session completed');

      // 📋 FINAL SPEECH SUMMARY
      print('\n${'📋' * 40}');
      print('📋 SPEECH RECOGNITION SUMMARY:');
      print('📋 Final Text: "${recognizedText ?? 'NONE'}"');
      print('📋 Text Length: ${recognizedText?.length ?? 0} characters');
      print('📋 Session Status: ${isComplete ? 'COMPLETED' : 'TIMEOUT/INCOMPLETE'}');
      print('📋' * 40 + '\n');

      print('AudioService: Final recognized text: "$recognizedText"');
      print('AudioService: Text length: ${recognizedText?.length ?? 0}');

      // Return result if we have meaningful text
      if (recognizedText != null && recognizedText!.trim().isNotEmpty) {
        // ✅ SUCCESS BANNER
        print('\n${'✅' * 35}');
        print('✅ SPEECH SUCCESSFULLY RECOGNIZED!');
        print('✅ Returning: "${recognizedText!.trim()}"');
        print('✅' * 35 + '\n');

        print('AudioService: Returning recognized text: "$recognizedText"');
        return recognizedText!.trim();
      } else {
        // ❌ NO SPEECH BANNER
        print('\n${'❌' * 35}');
        print('❌ NO SPEECH RECOGNIZED');
        print('❌ Reason: Empty or null text');
        print('❌ Troubleshooting tips:');
        print('❌ 1. Check microphone permissions');
        print('❌ 2. Speak louder and clearer');
        print('❌ 3. Reduce background noise');
        print('❌ 4. Hold device closer to mouth');
        print('❌' * 35 + '\n');

        print('AudioService: No meaningful text recognized');
        return null;
      }
    } catch (e) {
      print('AudioService: Error during listening: $e');
      print('AudioService: Error type: ${e.runtimeType}');

      // Try to stop listening if there was an error
      try {
        if (_speech.isListening) {
          await _speech.stop();
        }
      } catch (stopError) {
        print('AudioService: Error stopping speech: $stopError');
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
