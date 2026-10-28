import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper over flutter_local_notifications. Everything is scheduled on
/// the device; no push service, no server, no account.
class Notifier {
  Notifier._();
  static final Notifier instance = Notifier._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const AndroidNotificationDetails _details = AndroidNotificationDetails(
    'pranaya_reminders',
    'Pranaya reminders',
    channelDescription: 'Medicine, water, budget and task reminders',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {}
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: android,
    );
    try {
      await _plugin.initialize(settings);
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> showNow(int id, String title, String body) async {
    await init();
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(android: _details),
      );
    } catch (_) {}
  }

  Future<void> scheduleDaily(
    int id,
    String title,
    String body,
    int hour,
    int minute,
  ) async {
    await init();
    try {
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (when.isBefore(now)) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        const NotificationDetails(android: _details),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }
}

int reminderId(String key) => key.hashCode & 0x7fffffff;

Future<void> scheduleReminder({
  required String key,
  required String title,
  required String body,
  required TimeOfDay time,
}) async {
  await Notifier.instance.scheduleDaily(
    reminderId(key),
    title,
    body,
    time.hour,
    time.minute,
  );
}

Future<void> cancelReminder(String key) async {
  await Notifier.instance.cancel(reminderId(key));
}
