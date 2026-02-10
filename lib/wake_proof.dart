import 'dart:async';
import 'dart:math';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'alarm_success.dart';
import 'sunrise_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_provider.dart';

class WakeProofScreen extends StatefulWidget {
  final int alarmId;
  final String label;
  final int challengeType;
  final Duration holdDuration;
  final Duration emergencyBypassAfter;
  final bool accessibilityMode;
  final bool sunrise;

  const WakeProofScreen({
    super.key,
    required this.alarmId,
    required this.label,
    this.challengeType = 0,
    this.holdDuration = const Duration(seconds: 4),
    this.emergencyBypassAfter = const Duration(minutes: 2),
    this.accessibilityMode = false,
    this.sunrise = false,
  });

  @override
  State<WakeProofScreen> createState() => _WakeProofScreenState();
}

class _WakeProofScreenState extends State<WakeProofScreen>
  with TickerProviderStateMixin {
  static const _ch = MethodChannel('serenity/alarm_manager');
  static const _sunriseCh = MethodChannel('serenity/sunrise');
  static const _hapticsCh = MethodChannel('serenity/haptics');
  // Sunrise brightness ramp during ringing
  late final AnimationController _sunAnim;
  late final AnimationController _bgAnim;
  late final AnimationController _pulseAnim;
  Timer? _sunTick;
  Timer? _clockTimer;
  Timer? _hapticsTimer;
  DateTime _now = DateTime.now();
  int _snoozeMins = 5;
  String _userName = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Enter immersive full-screen so UI overlays are hidden during alarm
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    _sunAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..addListener(_onBrightProgress);
    _bgAnim = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
    _pulseAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    _prepareSunrisePlatform();
    _sunAnim.forward();
    _sunTick = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _onBrightProgress();
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadSnooze();
    _loadUserName();
    _startHapticsPattern();
    _startEmergencyTimer();
    AdProvider.showInterstitial();
  }

  Future<void> _prepareSunrisePlatform() async {
    try {
      await _sunriseCh.invokeMethod('acquireWakeLock');
      await _sunriseCh.invokeMethod('turnScreenOn');
      await _sunriseCh.invokeMethod('startForegroundIfNeeded');
    } catch (_) {}
  }

  Future<void> _loadSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getInt('snooze_minutes');
      if (mounted) setState(() => _snoozeMins = p ?? 9);
    } catch (_) {}
  }

  Future<void> _loadUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = prefs.getString('user_name');
      if (mounted && n != null) setState(() => _userName = n);
    } catch (_) {}
  }
  void _startHapticsPattern() {
    _hapticsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try { await HapticFeedback.mediumImpact(); } catch (_) {}
    });
  }

  Timer? _emergencyTimer;
  bool _showEmergencyBypass = false;

  void _startEmergencyTimer() {
    _emergencyTimer = Timer(widget.emergencyBypassAfter, () {
      if (mounted) setState(() => _showEmergencyBypass = true);
    });
  }

  void _onBrightProgress() {
    final t = _sunAnim.value;
    final v = mapProgressToBrightness(t);
    _setBrightness(v);
  }

  Future<void> _setBrightness(double v) async {
    try {
      await _sunriseCh.invokeMethod('setBrightness', v);
    } catch (_) {}
  }

  @override
  void dispose() {
    // Restore system UI when leaving
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    _hapticsTimer?.cancel();
    _emergencyTimer?.cancel();
    // Catch async MissingPluginException from unimplemented native method
    _hapticsCh.invokeMethod('stopPattern').catchError((_) {});
    _sunAnim.dispose();
    _bgAnim.dispose();
    _pulseAnim.dispose();
    super.dispose();
  }

  Future<void> _stopAlarm({bool showSuccess = true}) async {
    try {
      await _ch.invokeMethod('stopRinging', {'id': widget.alarmId});
      await _ch.invokeMethod('finishActivity');
    } catch (_) {}
    if (mounted) {
      if (showSuccess) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AlarmSuccessScreen(label: widget.label),
          ),
        );
      } else {
        // Just leave without success screen (e.g. for snooze or early dismissal)
         SystemNavigator.pop();
      }
    }
  }

  Future<void> _onSnooze() async {
    try {
      final mins = _snoozeMins;
      final when = DateTime.now().add(Duration(minutes: mins));
      // Persist snooze state so it survives restarts
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('snooze_until_${widget.alarmId}', when.millisecondsSinceEpoch);
      } catch (_) {}
      // Schedule snooze as a high-priority exact alarm with full-screen intent
      await _ch.invokeMethod('scheduleExact', {
        'id': widget.alarmId,
        'label': widget.label,
        'whenMs': when.millisecondsSinceEpoch,
        'androidChannelId': 'serenity_alarm',
        'androidImportance': 'max',
        'fullScreenIntent': true,
        'allowWhileIdle': true,
        'challengeType': widget.challengeType,
        'sunrise': widget.sunrise,
      });
    } catch (_) {}
    await _stopAlarm(showSuccess: false);
  }


  // Greeting + themed visuals based on current local time
  (String, _ThemeKind) _greeting() {
    final h = _now.hour;
    if (h >= 5 && h <= 11) return ('Good Morning', _ThemeKind.morning);
    if (h >= 12 && h <= 16) return ('Good Afternoon', _ThemeKind.afternoon);
    if (h >= 17 && h <= 20) return ('Good Evening', _ThemeKind.evening);
    return ('Good Night', _ThemeKind.night);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // block back
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _sunAnim,
            builder: (context, _) {
              // Warm sunrise gradient animating with brightness
              final t = Curves.easeInOut.transform(_sunAnim.value);
              final (greet, kind) = _greeting();
              // Base gradient palette per time block
              Color a, b, c;
              if (widget.sunrise) {
                // Sunrise Glow: Dark to bright yellow
                a = const Color(0xFF0F0800); // deep dark amber
                b = const Color(0xFFD4A017); // orange-yellow
                c = const Color(0xFFFFF700); // glowing yellow
              } else {
                switch (kind) {
                  case _ThemeKind.morning:
                    a = const Color(0xFFFFF1B6); // light yellow
                    b = const Color(0xFFFFD97A);
                    c = const Color(0xFFFFC857);
                    break;
                  case _ThemeKind.afternoon:
                    a = const Color(0xFFB3E5FC); // sky blue
                    b = const Color(0xFF81D4FA);
                    c = const Color(0xFF4FC3F7);
                    break;
                  case _ThemeKind.evening:
                    a = const Color(0xFFFFB199); // sunset
                    b = const Color(0xFFFF8C82);
                    c = const Color(0xFF7E57C2); // purple
                    break;
                  case _ThemeKind.night:
                    a = const Color(0xFF0B1026); // deep indigo
                    b = const Color(0xFF151A3A);
                    c = const Color(0xFF1E2550);
                    break;
                }
              }
              Color lerp(Color x, Color y, double p) => Color.lerp(x, y, p)!;
              final colors = t < 0.5
                  ? [lerp(a, b, t / 0.5), lerp(a, b, (t / 0.5 + 0.2).clamp(0, 1))]
                  : [lerp(b, c, (t - 0.5) / 0.5), lerp(b, c, ((t - 0.5) / 0.5 + 0.2).clamp(0, 1))];

              return Stack(
                children: [
                  // Gradient background
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: colors,
                      ),
                    ),
                  ),
                  // Subtle animated visuals: clouds or stars (ensure full size to avoid NaN)
                  if (!widget.sunrise)
                    SizedBox.expand(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _BgPainter(kind: kind, progress: _bgAnim.value),
                        ),
                      ),
                    ),
                  // Foreground content
                  Column(
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        _userName.isEmpty ? '$greet' : '$greet, $_userName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 4,
                              color: Colors.black45,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.label.isEmpty ? 'Alarm' : widget.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 4,
                              color: Colors.black45,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Large clock
                      Text(
                        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 64, // Slightly smaller to fit seconds
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                          letterSpacing: 1,
                          shadows: [
                            Shadow(offset: Offset(0, 2), blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // If there's a challenge, show it here
                      if (widget.challengeType > 0) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: widget.challengeType == 1
                                ? _MathChallengeInner(onSuccess: _stopAlarm)
                                : _PatternChallengeInner(onSuccess: _stopAlarm),
                          ),
                        ),
                      ],

                      const Spacer(),
                      
                      // Snooze/Stop pill control
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: widget.challengeType > 0 
                          ? _SnoozeOnlyPill(
                              label: 'Snooze',
                              onSnooze: _busy ? null : _onSnoozeWithFeedback,
                            )
                          : _SnoozeDismissButtons(
                              snoozeLabel: 'Snooze',
                              dismissLabel: 'Dismiss',
                              onSnooze: _busy ? null : _onSnoozeWithFeedback,
                              onStop: _stopAlarm,
                            ),
                      ),
                      const Spacer(),
                      
                      if (_showEmergencyBypass)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: TextButton(
                            onPressed: _stopAlarm,
                            child: const Text('Emergency Stop', style: TextStyle(color: Colors.white60)),
                          ),
                        ),

                      const BannerAdWidget(),
                      const SizedBox(height: 8),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onSnoozeWithFeedback() async {
    setState(() => _busy = true);
    try { await HapticFeedback.heavyImpact(); } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('See you in ${_snoozeMins} minutes')),
      );
    }
    try {
      await _onSnooze();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// Minimal snooze-only pill for when a challenge is active
class _SnoozeOnlyPill extends StatelessWidget {
  final String label;
  final VoidCallback? onSnooze;
  const _SnoozeOnlyPill({required this.label, this.onSnooze});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSnooze,
      child: Container(
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// Theme bucket for greeting visuals
enum _ThemeKind { morning, afternoon, evening, night }

// Subtle animated background painter: clouds for morning/afternoon, stars for evening/night
class _BgPainter extends CustomPainter {
  final _ThemeKind kind;
  final double progress; // 0..1 repeating
  _BgPainter({required this.kind, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // Guard against zero/invalid sizes to prevent NaN Offsets
    if (!size.width.isFinite || !size.height.isFinite || size.width == 0 || size.height == 0) {
      return;
    }
    final p = Paint()..isAntiAlias = true;
    if (kind == _ThemeKind.morning || kind == _ThemeKind.afternoon) {
      // Simple drifting clouds
      final y = size.height * 0.25;
      for (int i = 0; i < 3; i++) {
        final x = (size.width + 120) * ((progress + i * 0.33) % 1) - 60;
        _cloud(canvas, Offset(x, y + i * 40), 28 + i * 6, p..color = Colors.white.withValues(alpha: 0.2));
      }
    } else {
      // Twinkling stars
      for (int i = 0; i < 40; i++) {
        final x = (i * 97) % size.width;
        final y = (i * 173) % size.height * 0.6;
        final twinkle = (sin(progress * 2 * pi + i) + 1) * 0.5;
        p.color = Colors.white.withValues(alpha: 0.12 + twinkle * 0.18);
        canvas.drawCircle(Offset(x.toDouble(), y.toDouble()), 1.2, p);
      }
    }
  }

  void _cloud(Canvas canvas, Offset c, double r, Paint p) {
    canvas.drawCircle(c, r, p);
    canvas.drawCircle(c + const Offset(20, -6), r * 0.8, p);
    canvas.drawCircle(c + const Offset(-18, -8), r * 0.7, p);
    final rect = Rect.fromCenter(center: c + const Offset(0, 10), width: r * 2.6, height: r * 1.0);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r * 0.4)), p);
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => old.kind != kind || old.progress != progress;
}

// Simplified Snooze/Dismiss buttons
class _SnoozeDismissButtons extends StatelessWidget {
  final String snoozeLabel;
  final String dismissLabel;
  final VoidCallback? onSnooze;
  final VoidCallback onStop;

  const _SnoozeDismissButtons({
    required this.snoozeLabel,
    required this.dismissLabel,
    required this.onSnooze,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onSnooze,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text(snoozeLabel, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: GestureDetector(
            onTap: onStop,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Center(
                child: Text(dismissLabel, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------- CHALLENGE INNER WIDGETS ----------------

class _MathChallengeInner extends StatefulWidget {
  final VoidCallback onSuccess;
  const _MathChallengeInner({required this.onSuccess});
  @override
  State<_MathChallengeInner> createState() => _MathChallengeInnerState();
}

class _MathChallengeInnerState extends State<_MathChallengeInner> {
  late int a, b, answer;
  String input = '';
  int count = 0;
  static const int target = 3;

  @override
  void initState() { super.initState(); _generate(); }

  void _generate() {
    final r = Random();
    a = r.nextInt(50) + 10;
    b = r.nextInt(50) + 10;
    answer = a + b;
    input = '';
  }

  void _onKey(String key) {
    HapticFeedback.lightImpact();
    if (key == 'C') { setState(() => input = ''); return; }
    if (input.length >= 4) return;
    
    setState(() => input += key);
    
    if (input.length == answer.toString().length) {
      if (int.tryParse(input) == answer) {
        // Success
        count++;
        if (count >= target) {
          widget.onSuccess();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Correct! Next problem...'), duration: Duration(milliseconds: 800))
          );
          setState(() {
            _generate();
          });
        }
      } else {
        // Wrong - small delay then clear
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => input = '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
           children: [
             const Icon(Icons.calculate_outlined, color: Colors.white70, size: 20),
             const SizedBox(width: 8),
             Text('Solve to dismiss: ${count + 1}/$target', style: const TextStyle(color: Colors.white70, fontSize: 16)),
           ],
        ),
        const SizedBox(height: 12),
        Text('$a + $b = ?', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          height: 50, width: 140, alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(input, style: const TextStyle(color: Colors.blueAccent, fontSize: 28, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.8,
          children: [
            for (var i = 1; i <= 9; i++) _btn(i.toString()),
            _btn('C'), _btn('0'), const SizedBox(),
          ],
        ),
      ],
    );
  }

  Widget _btn(String label) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKey(label),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18)),
        ),
      ),
    );
  }
}

class _PatternChallengeInner extends StatefulWidget {
  final VoidCallback onSuccess;
  const _PatternChallengeInner({required this.onSuccess});
  @override
  State<_PatternChallengeInner> createState() => _PatternChallengeInnerState();
}

class _PatternChallengeInnerState extends State<_PatternChallengeInner> {
  final List<int> sequence = [];
  final List<int> userSequence = [];
  bool showing = true;
  int count = 0;
  static const int target = 2;
  int? litIndex;

  @override
  void initState() { super.initState(); _start(); }

  void _start() async {
    sequence.clear(); userSequence.clear();
    final r = Random();
    for (int i = 0; i < 4; i++) { sequence.add(r.nextInt(9)); }
    if (!mounted) return;
    setState(() => showing = true);
    await Future.delayed(const Duration(milliseconds: 800));
    for (int i = 0; i < sequence.length; i++) {
      if (!mounted) return;
      setState(() => litIndex = sequence[i]);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() => litIndex = null);
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (mounted) setState(() => showing = false);
  }

  void _onTap(int index) {
    if (showing) return;
    HapticFeedback.lightImpact();
    setState(() { 
      userSequence.add(index); 
      litIndex = index;
    });
    
    // Brief highlight for user tap
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted && litIndex == index) setState(() => litIndex = null);
    });

    if (userSequence.last != sequence[userSequence.length - 1]) {
      // Failed
      setState(() { 
        userSequence.clear(); 
        litIndex = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Try again!'), duration: Duration(seconds: 1))
      );
      _start();
      return;
    }

    if (userSequence.length == sequence.length) {
      count++;
      if (count >= target) {
        widget.onSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pattern matched! Next one...'), duration: Duration(milliseconds: 800))
        );
        _start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pattern_outlined, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
             Text('Match to dismiss: ${count + 1}/$target', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10,
          children: List.generate(9, (i) {
            final isLit = litIndex == i;
            return GestureDetector(
              onTap: () => _onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isLit ? Colors.blueAccent : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isLit ? Colors.white : Colors.white10),
                ),
                child: Center(
                  child: !showing && userSequence.contains(i) ? const Icon(Icons.check, color: Colors.green, size: 20) : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
