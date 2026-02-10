import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show FontFeature;
import 'package:shared_preferences/shared_preferences.dart';
import 'alarm_success.dart';
import 'sunrise_logic.dart';

/// Full-screen, calm sunrise experience.
/// - Locks orientation (platform side recommended), uses gentle gradient animation
/// - Calls platform channel to keep screen on, acquire wake lock, set brightness gradually
class SunriseScreen extends StatefulWidget {
  final int alarmId;
  final String label;
  final Duration duration; // total sunrise duration
  final bool showClock;

  const SunriseScreen({
    super.key,
    required this.alarmId,
    required this.label,
    required this.duration,
    this.showClock = true,
  });

  @override
  State<SunriseScreen> createState() => _SunriseScreenState();
}

class _SunriseScreenState extends State<SunriseScreen>
    with SingleTickerProviderStateMixin {
  static const _ch = MethodChannel('serenity/sunrise');
  static const _alarmCh = MethodChannel('serenity/alarm_manager');
  late final AnimationController _controller;
  Timer? _tick;
  int _snoozeMins = 9;
  DateTime _now = DateTime.now();
  Timer? _clockTick;

  @override
  void initState() {
    super.initState();
    // Enter immersive full-screen mode for sunrise experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _preparePlatform();
    _controller.addListener(_onProgress);
    _controller.forward();
    // Small timer to nudge brightness at ~60fps without overloading
    _tick = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _onProgress();
    });
    _clockTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadSnooze();
  }

  Future<void> _preparePlatform() async {
    try {
      await _ch.invokeMethod('acquireWakeLock');
      await _ch.invokeMethod('turnScreenOn');
      await _ch.invokeMethod('startForegroundIfNeeded');
    } catch (_) {}
  }

  void _onProgress() {
    final t = _controller.value;
    final brightness = mapProgressToBrightness(t);
    _setBrightness(brightness);
  }

  Future<void> _setBrightness(double v) async {
    try {
      await _ch.invokeMethod('setBrightness', v);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    _clockTick?.cancel();
    _controller.removeListener(_onProgress);
    _controller.dispose();
    // Restore system UI after leaving sunrise screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Keep wake lock until platform explicitly releases on transition
    super.dispose();
  }

  Future<void> _loadSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getInt('snooze_minutes');
      if (mounted) setState(() => _snoozeMins = p ?? 9);
    } catch (_) {}
  }

  Future<void> _stopAlarm() async {
    try {
      await _alarmCh.invokeMethod('stopRinging', {'id': widget.alarmId});
      await _alarmCh.invokeMethod('finishActivity');
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AlarmSuccessScreen(label: widget.label)),
      );
    }
  }

  Future<void> _onSnooze() async {
    try {
      final when = DateTime.now().add(Duration(minutes: _snoozeMins));
      // Persist snooze until
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('snooze_until_${widget.alarmId}', when.millisecondsSinceEpoch);
      } catch (_) {}
      // Schedule exact snooze alarm with full-screen intent
      await _alarmCh.invokeMethod('scheduleExact', {
        'id': widget.alarmId,
        'label': widget.label,
        'whenMs': when.millisecondsSinceEpoch,
        'androidChannelId': 'serenity_alarm',
        'androidImportance': 'max',
        'fullScreenIntent': true,
        'allowWhileIdle': true,
        'sunrise': true,
      });
    } catch (_) {}
    await _stopAlarm();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: false,
          bottom: false,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_controller.value);
              final colors = _gradientColors(t);
              return Container(
                constraints: const BoxConstraints.expand(),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: colors,
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 36),
                    // Large clock at top
                    Text(
                      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.label.isEmpty ? 'Alarm' : widget.label,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 18),
                    ),
                    const Spacer(),
                    // Snooze/Stop pill control
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      child: _SnoozeStopPill(
                        snoozeLabel: 'Snooze',
                        stopLabel: 'Stop',
                        onSnooze: () async {
                          try { await HapticFeedback.heavyImpact(); } catch (_) {}
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('See you in ${_snoozeMins} minutes')),
                            );
                          }
                          await _onSnooze();
                        },
                        onStop: () async {
                          try { await HapticFeedback.heavyImpact(); } catch (_) {}
                          await _stopAlarm();
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Color> _gradientColors(double t) {
    // Interpolate three key colors
    Color a = const Color(0xFF1A0A02); // deeper dark amber
    Color b = const Color(0xFFFF9933); // vibrant orange/saffron
    Color c = const Color(0xFFFFFF00); // bright yellow glow

    Color lerp(Color x, Color y, double p) => Color.lerp(x, y, p)!;

    // Two-phase blend: a->b then b->c
    if (t < 0.5) {
      final p = t / 0.5;
      return [
        lerp(a, b, p.clamp(0, 1)),
        lerp(a, b, min(1, p + 0.2)),
      ];
    } else {
      final p = (t - 0.5) / 0.5;
      return [
        lerp(b, c, p.clamp(0, 1)),
        lerp(b, c, min(1, p + 0.2)),
      ];
    }
  }
}

class _Clock extends StatelessWidget {
  const _Clock();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return Text(
      '$hh:$mm',
      style: const TextStyle(
        color: Colors.black87,
        fontSize: 52,
        fontWeight: FontWeight.w300,
      ),
    );
  }
}

// Snooze/Stop pill control resembling the provided layout
class _SnoozeStopPill extends StatefulWidget {
  final String snoozeLabel;
  final String stopLabel;
  final VoidCallback onSnooze;
  final VoidCallback onStop;
  const _SnoozeStopPill({
    Key? key,
    required this.snoozeLabel,
    required this.stopLabel,
    required this.onSnooze,
    required this.onStop,
  }) : super(key: key);

  @override
  State<_SnoozeStopPill> createState() => _SnoozeStopPillState();
}

class _SnoozeStopPillState extends State<_SnoozeStopPill> {
  double _pos = 0.0; // -1 left snooze, 1 right stop

  void _reset() => setState(() => _pos = 0.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        setState(() {
          _pos = (_pos + d.delta.dx / 100).clamp(-1.0, 1.0);
        });
      },
      onHorizontalDragEnd: (_) {
        if (_pos <= -0.5) {
          widget.onSnooze();
        } else if (_pos >= 0.5) {
          widget.onStop();
        }
        _reset();
      },
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: widget.onSnooze,
                    child: Text(widget.snoozeLabel, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 64),
                Expanded(
                  child: TextButton(
                    onPressed: widget.onStop,
                    child: Text(widget.stopLabel, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment(_pos.isFinite ? _pos : 0.0, 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.alarm, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
