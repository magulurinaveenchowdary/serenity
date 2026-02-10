import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlarmIntegration {
  static const _ch = MethodChannel('serenity/alarm_manager');

  static Future<void> schedule({
    required int id,
    required String label,
    required DateTime when,
    String? soundUri,
    String type = 'alarm',
    int challengeType = 0,
    bool sunrise = false,
  }) async {
    await _ensurePermissions();
    String? uri = soundUri;
    try {
      if (uri == null) {
        final prefs = await SharedPreferences.getInstance();
        final s = prefs.getString('alarm_sound_$id');
        if (s != null && s.isNotEmpty) uri = s;
      }
    } catch (_) {}

    await _ch.invokeMethod('scheduleExact', {
      'id': id,
      'label': label,
      'whenMs': when.millisecondsSinceEpoch,
      'soundUri': uri ?? '',
      'type': type,
      'androidChannelId': 'serenity_alarm',
      'androidImportance': 'max',
      'fullScreenIntent': true,
      'allowWhileIdle': true,
      'challengeType': challengeType,
      'sunrise': sunrise,
      'onTapMethod': 'tap',
      'onTapRoute': (type == 'reminder' ? 'reminder_trigger' : 'success') + '?label=' + Uri.encodeComponent(label),
      'actions': [
        {
          'id': 'stop',
          'title': 'Dismiss',
          'onActionMethod': 'stop',
        }
      ],
    });
    await _mirrorToPrefs(id: id, label: label, when: when, type: type, challengeType: challengeType, sunrise: sunrise);
  }

  /// Schedule alarm plus sunrise pre-alarm if [sunriseLeadMinutes] > 0.
  static Future<void> scheduleWithSunrise({
    required int id,
    required String label,
    required DateTime when,
    required int sunriseLeadMinutes,
    int challengeType = 0,
    bool sunrise = true,
  }) async {
    await schedule(id: id, label: label, when: when, challengeType: challengeType, sunrise: sunrise);
    if (sunriseLeadMinutes > 0) {
      try {
        await _ch.invokeMethod('scheduleSunrise', {
          'id': id,
          'label': label,
          'whenMs': when.millisecondsSinceEpoch,
          'leadMinutes': sunriseLeadMinutes,
        });
      } catch (_) {}
    }
  }

  static Future<void> cancel(int id) async {
    await _ch.invokeMethod('cancel', id);
  }

  static Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;

    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final res = await Permission.notification.request();
        if (!res.isGranted) {
          await _ch.invokeMethod('openNotificationSettings');
        }
      }
    } catch (_) {}

    try {
      final allowed = await _ch.invokeMethod<bool>('isExactAlarmAllowed') ?? false;
      if (!allowed) {
        await _ch.invokeMethod('openExactAlarmSettings');
      }
    } catch (_) {}
  }

  static Future<void> _mirrorToPrefs({
    required int id,
    required String label,
    required DateTime when,
    String type = 'alarm',
    int challengeType = 0,
    bool sunrise = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString('alarms') ?? '[]';
    final arr = (jsonDecode(current) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final hour12 = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final isAm = when.hour < 12;

    arr.removeWhere((e) => e['id'] == id);
    arr.add({
      'id': id,
      'hour': hour12,
      'minute': when.minute,
      'second': when.second,
      'isAm': isAm,
      'label': label,
      'type': type,
      'challengeType': challengeType,
      'sunrise': sunrise,
      'enabled': true,
    });

    await prefs.setString('alarms', jsonEncode(arr));
  }
}
