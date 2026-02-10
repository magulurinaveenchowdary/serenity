import 'package:flutter/animation.dart';

/// Computes the start time for the sunrise pre-alarm given the main alarm time
/// and the configured lead minutes (e.g., 5, 10, 15, 20).
/// If [leadMinutes] is <= 0, returns the original [alarmTime].
DateTime computeSunriseStart(DateTime alarmTime, int leadMinutes) {
  if (leadMinutes <= 0) return alarmTime;
  return alarmTime.subtract(Duration(minutes: leadMinutes));
}

/// Maps an animation progress [t] in [0..1] to a brightness value in [0.05..0.85].
/// Uses a curve to keep it gentle at the start and end.
double mapProgressToBrightness(double t) {
  final clamped = t.clamp(0.0, 1.0);
  // Ease-in-out cubic for smoothness
  final eased = Curves.easeInOut.transform(clamped);
  return 0.05 + (0.85 - 0.05) * eased;
}
