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
  }) async {
    await _ensurePermissions();
    await _ch.invokeMethod('scheduleExact', {
      'id': id,
      'label': label,
      'whenMs': when.millisecondsSinceEpoch,
    });
    await _mirrorToPrefs(id: id, label: label, when: when);
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

    try {
      final opt = await Permission.ignoreBatteryOptimizations.status;
      if (!opt.isGranted) {
        final res = await Permission.ignoreBatteryOptimizations.request();
        if (!res.isGranted) {
          await _ch.invokeMethod('openBatteryOptimizationSettings');
        }
      }
    } catch (_) {}
  }

  static Future<void> _mirrorToPrefs({
    required int id,
    required String label,
    required DateTime when,
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
      'isAm': isAm,
      'label': label,
    });

    await prefs.setString('alarms', jsonEncode(arr));
  }

  static Future<void> _removeFromPrefs(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString('alarms') ?? '[]';
    final arr = (jsonDecode(current) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    arr.removeWhere((e) => e['id'] == id);
    await prefs.setString('alarms', jsonEncode(arr));
  }
}
