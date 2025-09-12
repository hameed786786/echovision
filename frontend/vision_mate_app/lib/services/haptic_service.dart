import 'package:vibration/vibration.dart';
import '../config/constants.dart';

class HapticService {
  static Future<void> lightVibration() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(
          duration: AppConstants.vibrationDuration.inMilliseconds,
        );
      }
    } catch (e) {
      print('Error with light vibration: $e');
    }
  }

  static Future<void> heavyVibration() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(
          duration: AppConstants.longVibrationDuration.inMilliseconds,
        );
      }
    } catch (e) {
      print('Error with heavy vibration: $e');
    }
  }

  static Future<void> mediumVibration() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(duration: 200); // Medium duration
      }
    } catch (e) {
      print('Error with medium vibration: $e');
    }
  }

  static Future<void> successPattern() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        // Short-short-long pattern for success
        await Vibration.vibrate(pattern: [0, 100, 100, 100, 100, 300]);
      }
    } catch (e) {
      print('Error with success vibration pattern: $e');
    }
  }

  static Future<void> errorPattern() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        // Long-long pattern for error
        await Vibration.vibrate(pattern: [0, 300, 200, 300]);
      }
    } catch (e) {
      print('Error with error vibration pattern: $e');
    }
  }

  static Future<void> cancel() async {
    try {
      await Vibration.cancel();
    } catch (e) {
      print('Error canceling vibration: $e');
    }
  }

  // Navigation guidance haptics
  static Future<void> slightLeft() async {
    _pattern([0, 40, 60, 40]); // two short pulses
  }

  static Future<void> slightRight() async {
    _pattern([0, 40, 40, 40]); // tighter spacing
  }

  static Future<void> turnLeft() async {
    _pattern([0, 120, 80, 60]); // long then short
  }

  static Future<void> turnRight() async {
    _pattern([0, 60, 60, 120]); // short then long
  }

  static Future<void> hardTurn() async {
    _pattern([0, 180, 90, 180]); // two strong pulses
  }

  static Future<void> centerAhead() async {
    _pattern([0, 30]); // single light pulse
  }

  static Future<void> _pattern(List<int> pattern) async {
    try {
      final hasVibrator = await Vibration.hasVibrator() == true;
      if (hasVibrator) {
        await Vibration.vibrate(pattern: pattern);
      }
    } catch (e) {
      print('Error running haptic pattern: $e');
    }
  }
}
