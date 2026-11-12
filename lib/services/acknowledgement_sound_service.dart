import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays the brief acknowledgement used after a device-confirmed save.
///
/// Android uses the native tone implementation so its duration is predictable.
/// Other platforms use Flutter's built-in system sound and require no assets.
class AcknowledgementSoundService {
  const AcknowledgementSoundService();

  static const MethodChannel _channel = MethodChannel(
    'com.example.ulink_batterylab/acknowledgement_sound',
  );

  Future<void> play() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod<void>('playAcknowledgement');
        return;
      }
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Sound feedback must never turn a confirmed save into an error state.
    }
  }
}
