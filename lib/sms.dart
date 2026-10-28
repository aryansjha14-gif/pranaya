import 'package:flutter/services.dart';

/// Reads the Android SMS inbox through a small platform channel implemented in
/// MainActivity.kt. If the user denies the permission, or the platform is not
/// Android, this returns an empty list and the UI falls back to paste-entry.
class SmsReader {
  static const MethodChannel _channel = MethodChannel('pranaya/sms');

  static Future<List<Map<String, dynamic>>> readInbox() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('readInbox');
      if (result is List) {
        return result
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => <String, dynamic>{
                  'address': (m['address'] ?? '').toString(),
                  'body': (m['body'] ?? '').toString(),
                  'date': (m['date'] ?? '0').toString(),
                })
            .toList();
      }
      return <Map<String, dynamic>>[];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
