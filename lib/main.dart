
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show FontFeature;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/cupertino.dart'; // Needed for CupertinoDatePicker
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_provider.dart';
import 'alarm_integration.dart';
import 'sunrise_experience.dart';
import 'wake_proof.dart';
import 'alarm_success.dart';
// import 'post_call_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdProvider.init();
  AdProvider.loadInterstitial();
  AdProvider.loadAppOpen();
  // Initialize timezone database and set local location
  try {
    tzdata.initializeTimeZones();
    final dynamic localInfo = await FlutterTimezone.getLocalTimezone();
    final String tzid = (localInfo is String)
        ? localInfo
        : ((localInfo as dynamic).name as String?) ?? 'UTC';
    tz.setLocalLocation(tz.getLocation(tzid));
  } catch (e) {
    // Fallback to UTC if timezone init fails
    tz.setLocalLocation(tz.getLocation('UTC'));
  }
  
  await _requestPermissions();

  // Listen for native full-screen alarm activity and notification intents
  const MethodChannel('serenity/current_alarm').setMethodCallHandler((call) async {
    final alarmCh = const MethodChannel('serenity/alarm_manager');
    if (call.method == 'push' || call.method == 'ring') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final id = (args['alarm_id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final type = (args['type'] as String?) ?? 'alarm';
      final label = (args['label'] as String?) ?? (type == 'reminder' ? 'Reminder' : 'Alarm');
      final challengeType = (args['challengeType'] as num?)?.toInt() ?? 0;
      final sunrise = args['sunrise'] == true;

      if (type == 'reminder') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ReminderTriggerScreen(
              reminder: Reminder(
                id: id,
                title: label,
                dateTime: DateTime.now(),
                recurrenceType: RecurrenceType.none,
                priority: Priority.high,
                soundEnabled: true,
                vibrateEnabled: true,
              ),
            ),
          ),
        );
      } else {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => RingingScreen(alarmId: id, label: label, challengeType: challengeType, sunrise: sunrise)),
        );
      }
    }
    // When user taps the alarm notification, stop and open success screen
    if (call.method == 'tap' || call.method == 'clicked') {
      final args = (call.arguments is Map)
          ? Map<String, dynamic>.from(call.arguments as Map)
          : <String, dynamic>{};
      final id = (args['alarm_id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final label = (args['label'] as String?) ?? 'Alarm';
      try { await alarmCh.invokeMethod('stopRinging', {'id': id}); } catch (_) {}
      try { await alarmCh.invokeMethod('finishActivity'); } catch (_) {}
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => AlarmSuccessScreen(label: label)),
      );
    }
    // Handle Stop action button on the notification
    if (call.method == 'stop') {
      final args = (call.arguments is Map)
          ? Map<String, dynamic>.from(call.arguments as Map)
          : <String, dynamic>{};
      final id = (args['alarm_id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final label = (args['label'] as String?) ?? 'Alarm';
      try { await alarmCh.invokeMethod('stopRinging', {'id': id}); } catch (_) {}
      try { await alarmCh.invokeMethod('finishActivity'); } catch (_) {}
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => AlarmSuccessScreen(label: label)),
      );
    }
    if (call.method == 'sunrise') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final id = (args['alarm_id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final label = (args['label'] as String?) ?? 'Alarm';
      final lead = (args['leadMinutes'] as num?)?.toInt() ?? 10;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => SunriseScreen(
            alarmId: id,
            label: label,
            duration: Duration(minutes: lead),
          ),
        ),
      );
    }
    return null;
  });
  runApp(const SerenityApp());
}

Future<void> _requestPermissions() async {
  // Request critical permissions for call detection
  await [
// Permission.phone,
    // Permission.contacts, // Sometimes needed for lookup
    Permission.notification,
  ].request();
}

// ---------------- APP ROOT ----------------
class SerenityApp extends StatefulWidget {
  const SerenityApp({super.key});
  @override
  State<SerenityApp> createState() => _SerenityAppState();
}

class _SerenityAppState extends State<SerenityApp> with WidgetsBindingObserver {
  ThemeMode mode = ThemeMode.system;
  bool is24h = false;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AdProvider.showAppOpen();
      // Hide floating icon when app is open
      _manageFloatingIcon(false);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Show floating icon when app is in background
      _manageFloatingIcon(true);
    }
  }

  Future<void> _manageFloatingIcon(bool show) async {
    try {
      final p = await SharedPreferences.getInstance();
      final enabled = p.getBool('floating_enabled') ?? false;
      if (!enabled) return;

      const ch = MethodChannel('serenity/alarm_manager');
      if (show) {
        // Only start if we have overlay permission
        final hasPermission = await ch.invokeMethod<bool>('canDrawOverlays') ?? false;
        if (hasPermission) {
          await ch.invokeMethod('startFloatingIcon');
        }
      } else {
        await ch.invokeMethod('stopFloatingIcon');
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      mode = ThemeMode.values[p.getInt('theme') ?? ThemeMode.system.index];
      is24h = p.getBool('is24h') ?? false;
    });
    // If an alarm is actively ringing, route to success immediately
    try {
      final id = p.getInt('alarm_active_id') ?? -1;
      final label = p.getString('alarm_active_label') ?? 'Alarm';
      if (id != -1) {
        // Ask native to stop service/notification, then navigate
        const MethodChannel('serenity/alarm_manager').invokeMethod('stopRinging', {'id': id}).catchError((_) {});
        const MethodChannel('serenity/alarm_manager').invokeMethod('finishActivity').catchError((_) {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute(builder: (_) => AlarmSuccessScreen(label: label)),
          );
        });
      }
    } catch (_) {}
  }

  Future<void> saveTheme(ThemeMode m) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme', m.index);
    setState(() => mode = m);
  }

  Future<void> save24(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('is24h', v);
    setState(() => is24h = v);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gentle Wake Alarm Clock Timer',
      navigatorKey: navigatorKey,
      themeMode: mode,
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/ringing') || name.startsWith('ringing')) {
          final uri = Uri.parse(name.startsWith('/') ? name : '/$name');
          final idStr = uri.queryParameters['alarm_id'];
          final id = int.tryParse(idStr ?? '') ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final label = uri.queryParameters['label'] ?? 'Alarm';
          final challengeType = int.tryParse(uri.queryParameters['challengeType'] ?? '') ?? 0;
          final sunrise = uri.queryParameters['sunrise'] == 'true';
          return MaterialPageRoute(builder: (_) => RingingScreen(alarmId: id, label: label, challengeType: challengeType, sunrise: sunrise));
        }
        if (name.startsWith('/sunrise') || name.startsWith('sunrise')) {
          final uri = Uri.parse(name.startsWith('/') ? name : '/$name');
          final idStr = uri.queryParameters['alarm_id'];
          final id = int.tryParse(idStr ?? '') ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final label = uri.queryParameters['label'] ?? 'Alarm';
          return MaterialPageRoute(
            builder: (_) => SunriseScreen(
              alarmId: id,
              label: label,
              duration: const Duration(minutes: 10),
              showClock: true,
            ),
          );
        }
        if (name.startsWith('/success') || name.startsWith('success')) {
          final uri = Uri.parse(name.startsWith('/') ? name : '/$name');
          final label = uri.queryParameters['label'] ?? 'Alarm';
          return MaterialPageRoute(builder: (_) => AlarmSuccessScreen(label: label));
        }
        if (name.startsWith('/reminder_trigger') || name.startsWith('reminder_trigger')) {
          final uri = Uri.parse(name.startsWith('/') ? name : '/$name');
          final idStr = uri.queryParameters['alarm_id'];
          final id = int.tryParse(idStr ?? '') ?? DateTime.now().millisecondsSinceEpoch;
          final label = uri.queryParameters['label'] ?? 'Reminder';
          return MaterialPageRoute(
            builder: (_) => ReminderTriggerScreen(
              reminder: Reminder(
                id: id,
                title: label,
                dateTime: DateTime.now(),
                recurrenceType: RecurrenceType.none,
                priority: Priority.high,
                soundEnabled: true,
                vibrateEnabled: true,
              ),
            ),
          );
        }
        /*if (name.startsWith('/post_call') || name.startsWith('post_call')) {
          final uri = Uri.parse(name.startsWith('/') ? name : '/$name');
          final phone = uri.queryParameters['phone'];
          final cname = uri.queryParameters['name'];
          final duration = uri.queryParameters['duration'];
          return MaterialPageRoute(
            builder: (_) => PostCallScreen(
              phoneNumber: phone,
              contactName: cname,
              callDuration: duration,
            ),
          );
        }*/
        return null; // fallback to default
      },

      theme: ThemeData(
        useMaterial3: false,
        brightness: Brightness.light,
        scaffoldBackgroundColor: kLightBg,
        primaryColor: kPrimary,
        cardColor: kLightCard,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(14),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: kPrimary),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kLightBg,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w300,
            color: Colors.black,
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: false,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kDarkBg,
        primaryColor: kPrimary,
        cardColor: kDarkCard,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kDarkSurface,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(14),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: kPrimary),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kDarkBg,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w300,
            color: Colors.white,
          ),
        ),
      ),
      home: _showSplash 
        ? SplashScreen(onFinished: () => setState(() => _showSplash = false))
        : Shell(is24h: is24h, onTheme: saveTheme, on24h: save24, mode: mode),
    );
  }
}

// ---------------- SPLASH SCREEN ----------------
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  Future<void> _startFlow() async {
    // Wait a bit for the ad to load if it hasn't already
    await Future.delayed(const Duration(seconds: 2));
    
    // Try to show App Open Ad
    if (AdProvider.isAppOpenAdAvailable) {
      await AdProvider.showAppOpen();
    }
    
    // Finish splash
    if (mounted) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDarkBg : kLightBg,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/Frame 12809.png',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Serenity',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 50),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(height: 20),
                  BannerAdWidget(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const kDarkBg = Color(0xFF0B0F17);
const kDarkSurface = Color(0xFF141A24);
const kDarkCard = Color(0xFF1C2330);

const kLightBg = Color(0xFFF6F8FB);
const kLightSurface = Colors.white;
const kLightCard = Color(0xFFEDEFF5);

const kPrimary = Color(0xFF4C8DFF);
// Global UI constants
const double kRadius = 20;
const double kSheetRadius = 24;
const double kPad = 16;

// Theme-aware helpers for consistent light/dark colors
Color mutedText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : Colors.black54;
Color mediumText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : Colors.black87;
Color subtleText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white38
        : Colors.black38;
Color chipBg(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? kDarkCard : kLightCard;
Color dividerColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.12);

// Theme-aware modal scrim for bottom sheets (white-tinted in light mode)
Color modalScrim(BuildContext context) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.dark) {
    return Colors.black.withValues(alpha: 0.6);
  }
  // Light mode: use scaffold background tint instead of black scrim
  return theme.scaffoldBackgroundColor.withValues(alpha: 0.5);
}

// ---------------- SHELL ----------------
class Shell extends StatefulWidget {
  final bool is24h;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<bool> on24h;
  const Shell({
    super.key,
    required this.is24h,
    required this.onTheme,
    required this.on24h,
    required this.mode,
  });

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  Timer? _reminderChecker;

  @override
  void initState() {
    super.initState();
    // Check for reminders every 10 seconds
    // Check for reminders every 10 seconds (DISABLED in favor of Native Alarms)
    // _reminderChecker = Timer.periodic(const Duration(seconds: 10), (_) => _checkReminders());
  }

  @override
  void dispose() {
    _reminderChecker?.cancel();
    super.dispose();
  }

  Future<void> _checkReminders() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('reminders');
    if (s == null || s.isEmpty) return;

    List<Reminder> list = [];
    try {
      list = (jsonDecode(s) as List<dynamic>)
          .map((e) => Reminder.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) { return; }

    bool changed = false;
    final now = DateTime.now();

    for (var r in list) {
        if (r.isEnabled && !r.isCompleted && now.isAfter(r.dateTime)) {
            // Trigger!
            r.isCompleted = true; // Mark as done for single-shot, or update for recurring
            
            // Handle recurrence logic simply for now:
            if (r.recurrenceType != RecurrenceType.none) {
                // If recurring, schedule next instance instead of marking completed
                r.isCompleted = false; // Keep active
                // Update dateTime to next occurrence
                r.dateTime = _nextOccurrence(r.dateTime, r.recurrenceType);
            } else {
                r.isEnabled = false; 
                r.isCompleted = true;
            }

            changed = true;
            
            if (mounted) {
                 Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ReminderTriggerScreen(reminder: r),
                        fullscreenDialog: true,
                    ),
                );
            }
        }
    }

    if (changed) {
        final newJson = jsonEncode(list.map((e) => e.toMap()).toList());
        await p.setString('reminders', newJson);
        // Force refresh if on reminder screen?
        // Ideally use a stream or state management, but for now this saves the backend state
    }
  }

  DateTime _nextOccurrence(DateTime current, RecurrenceType type) {
      // Simple logic to add interval
      switch (type) {
          case RecurrenceType.daily: return current.add(const Duration(days: 1));
          case RecurrenceType.weekly: return current.add(const Duration(days: 7));
          // Approximate monthly/yearly for simplicity
          case RecurrenceType.monthly: return DateTime(current.year, current.month + 1, current.day, current.hour, current.minute);
          case RecurrenceType.annually: return DateTime(current.year + 1, current.month, current.day, current.hour, current.minute);
          case RecurrenceType.hourly: return current.add(const Duration(hours: 1));
          default: return current;
      }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      AlarmScreen(is24h: widget.is24h),
      ReminderScreen(is24h: widget.is24h),
      TimerScreen(is24h: widget.is24h),
      const StopwatchScreen(),
      WorldClockScreen(is24h: widget.is24h),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _showExitDialog(context);
      },
      child: Scaffold(
        body: pages[index],
        drawer: SettingsDrawer(
          is24h: widget.is24h,
          mode: widget.mode,
          on24h: widget.on24h,
          onTheme: widget.onTheme,
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              indicatorColor: kPrimary.withValues(alpha: 0.15),
              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BannerAdWidget(),
              NavigationBar(
                height: 72,
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => index = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.alarm_outlined),
                    label: 'Alarm',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.notifications_active_outlined),
                    label: 'Reminder',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.timer_outlined),
                    label: 'Timer',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.av_timer_outlined),
                    label: 'Stopwatch',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.public_outlined),
                    label: 'World',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const DragHandle(),
              const SizedBox(height: 16),
              const Text(
                'Exit Gentle Wake Alarm Clock Timer?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to close the app?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const Spacer(),
              const Center(child: BannerAdWidget(size: AdSize.mediumRectangle)),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('CANCEL'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => SystemNavigator.pop(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('EXIT'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- ALARM ----------------
enum RecurrenceType { none, daily, weekly, monthly, annually, hourly, minutely }

enum ChallengeType { none, math, pattern }

class Alarm {
  int id;
  int hour;
  int minute;
  int second;
  bool isAm;
  String label;
  List<int> repeatDays; // Legacy: 1=Mon...7=Sun for Weekly
  RecurrenceType recurrenceType;
  int recurrenceInterval; // e.g. every 2 hours
  bool sunrise;
  bool enabled;
  ChallengeType challengeType;

  Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.second,
    required this.isAm,
    required this.label,
    required this.repeatDays,
    this.recurrenceType = RecurrenceType.none,
    this.recurrenceInterval = 1,
    required this.sunrise,
    this.enabled = true,
    this.challengeType = ChallengeType.none,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'second': second,
        'isAm': isAm,
        'label': label,
        'repeatDays': repeatDays,
        'recurrenceType': recurrenceType.index,
        'recurrenceInterval': recurrenceInterval,
        'sunrise': sunrise,
        'enabled': enabled,
        'challengeType': challengeType.index,
      };

  static Alarm fromMap(Map<String, dynamic> m) => Alarm(
        id: m['id'] as int,
        hour: m['hour'] as int,
        minute: m['minute'] as int,
        second: m['second'] as int? ?? 0,
        isAm: m['isAm'] as bool,
        label: (m['label'] ?? '') as String,
        repeatDays:
            (m['repeatDays'] as List<dynamic>? ?? const []).map((e) => e as int).toList(),
        recurrenceType: RecurrenceType.values[m['recurrenceType'] as int? ?? 0],
        recurrenceInterval: m['recurrenceInterval'] as int? ?? 1,
        sunrise: (m['sunrise'] ?? false) as bool,
        enabled: (m['enabled'] ?? true) as bool,
        challengeType: ChallengeType.values[m['challengeType'] as int? ?? 0],
      );
}

class AlarmScreen extends StatefulWidget {
  final bool is24h;
  const AlarmScreen({super.key, required this.is24h});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final List<Alarm> alarms = [];
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _checkOverlayPermission();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _now = DateTime.now();
      });
    });
    _loadAlarms();
  }

  Future<void> _checkOverlayPermission() async {
    if (!Platform.isAndroid) return;
    const ch = MethodChannel('serenity/alarm_manager');
    try {
      final canDraw = await ch.invokeMethod<bool>('canDrawOverlays') ?? true;
      if (!canDraw && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Full Screen Alarms'),
            content: const Text('To show the alarm full-screen even when another app is open, please enable "Display over other apps".'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ch.invokeMethod('openOverlaySettings');
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat(widget.is24h ? 'HH:mm' : 'h:mm a');
    final now = _now;

    return SafeArea(
      child: Column(
        children: [
          AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: const Text('Alarm'),
            actions: [
              IconButton(icon: const Icon(Icons.add), onPressed: () { AppFeedback.tap(); _addAlarm(); }),
            ],
          ),

          // ===== LIVE CLOCK =====
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              timeFmt.format(now),
              style: Theme.of(context).textTheme.displayLarge,
            ),
          ),

          // ===== CONTENT =====
          Expanded(child: alarms.isEmpty ? _emptyState() : _alarmList()),

          // ===== ADD BUTTON =====
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () { 
                AppFeedback.tap(); 
                
                _addAlarm(); 
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Alarm'),
            ),
          ),
          
        ],
      ),
    );
  }

  // ================= HELPERS =================

  Future<void> _loadAlarms() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('alarms');
    if (s == null || s.isEmpty) return;
    try {
      final list = (jsonDecode(s) as List<dynamic>)
          .map((e) => Alarm.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        alarms
          ..clear()
          ..addAll(list);
      });
    } catch (_) {}
  }

  Future<void> _saveAlarms() async {
    final p = await SharedPreferences.getInstance();
    final s = jsonEncode(alarms.map((a) => a.toMap()).toList());
    await p.setString('alarms', s);
  }

  Future<void> _addAlarm() async {
    final alarm = await showModalBottomSheet<Alarm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: modalScrim(context),
      builder: (_) => NewAlarmSheet(is24h: widget.is24h),
    );

    if (alarm != null) {
      setState(() => alarms.add(alarm));
      await _saveAlarms();
      if (alarm.enabled) {
        final when = _computeNextDateFor(alarm);
        await AlarmIntegration.schedule(
          id: alarm.id,
          label: alarm.label.isEmpty ? 'Alarm' : alarm.label,
          when: when,
          challengeType: alarm.challengeType.index,
          sunrise: alarm.sunrise,
        );
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text('The alarm will go off in ${AlarmUtils.getTimeUntil(when)}'),
               behavior: SnackBarBehavior.floating,
             ),
           );
        }
      }
    }
  }

  Widget _emptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 45,
          backgroundColor: chipBg(context),
          child: const Icon(Icons.notifications_none, size: 42),
        ),
        const SizedBox(height: 16),
        const Text('No alarms yet', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 6),
        Text(
          'Create your first alarm to get started',
          style: TextStyle(color: mutedText(context)),
        ),
      ],
    );
  }

  Widget _alarmList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: alarms.length,
      itemBuilder: (context, i) {
        final alarm = alarms[i];

        return Dismissible(
          key: ValueKey(alarm),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete, color: Colors.red),
          ),
          onDismissed: (_) async {
            final removed = alarms.removeAt(i);
            setState(() {});
            try { await AlarmIntegration.cancel(removed.id); } catch (_) {}
            await _saveAlarms();
          },
          child: GestureDetector(
            onTap: () { AppFeedback.tap(); _editAlarm(alarm, i); },
            child: _AlarmCard(alarm: alarm, is24h: widget.is24h),
          ),
        );
      },
    );
  }

  Future<void> _editAlarm(Alarm alarm, int index) async {
    final updated = await showModalBottomSheet<Alarm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: modalScrim(context),
      builder: (_) => EditAlarmSheet(alarm: alarm, is24h: widget.is24h),
    );

    if (updated != null) {
      // Keep the same id
      updated.id = alarm.id;
      alarms[index] = updated;
      setState(() {});
      await _saveAlarms();
      // Reschedule or cancel based on enabled
      try { await AlarmIntegration.cancel(updated.id); } catch (_) {}
      if (updated.enabled) {
        final when = _computeNextDateFor(updated);
        await AlarmIntegration.schedule(
          id: updated.id,
          label: updated.label.isEmpty ? 'Alarm' : updated.label,
          when: when,
          challengeType: updated.challengeType.index,
          sunrise: updated.sunrise,
        );
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text('The alarm will go off in ${AlarmUtils.getTimeUntil(when)}'),
               behavior: SnackBarBehavior.floating,
             ),
           );
        }
      }
    }
  }

  DateTime _computeNextDateFor(Alarm alarm) {
    return AlarmUtils.computeNextAlarmDate(
      hour: alarm.hour,
      minute: alarm.minute,
      second: alarm.second,
      isAm: alarm.isAm,
      repeatDays: alarm.repeatDays,
    );
  }
}

class _AlarmCard extends StatefulWidget {
  final Alarm alarm;
  final bool is24h;
  const _AlarmCard({required this.alarm, required this.is24h});

  @override
  State<_AlarmCard> createState() => _AlarmCardState();
}

class _AlarmCardState extends State<_AlarmCard> {
  late bool enabled;

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    String time;
    if (widget.is24h) {
      int h = alarm.hour % 12;
      if (!alarm.isAm) h += 12;
      time = '${h.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}:${alarm.second.toString().padLeft(2, '0')}';
    } else {
      time = '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}:${alarm.second.toString().padLeft(2, '0')} ${alarm.isAm ? 'AM' : 'PM'}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // ===== TIME =====
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(time, style: const TextStyle(fontSize: 28)),
              if (alarm.label.isNotEmpty)
                Text(
                  alarm.label,
                  style: TextStyle(color: mutedText(context)),
                ),
              const SizedBox(height: 4),
              Text(
                alarm.repeatDays.isEmpty
                    ? 'One time'
                    : _repeatText(alarm.repeatDays),
                style: TextStyle(fontSize: 12, color: mutedText(context)),
              ),
            ],
          ),

          const Spacer(),

          // ===== TOGGLE =====
          Switch(
            value: enabled,
            onChanged: (v) async {
              setState(() => enabled = v);
              alarm.enabled = v;
              // Persist and schedule/cancel
              final state = context.findAncestorStateOfType<_AlarmScreenState>();
              if (state != null) {
                await state._saveAlarms();
              }
              if (v) {
                final when = _nextDateFor(alarm);
                await AlarmIntegration.schedule(
                  id: alarm.id,
                  label: alarm.label.isEmpty ? 'Alarm' : alarm.label,
                  when: when,
                  challengeType: alarm.challengeType.index,
                  sunrise: alarm.sunrise,
                );
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(
                       content: Text('The alarm will go off in ${AlarmUtils.getTimeUntil(when)}'),
                       behavior: SnackBarBehavior.floating,
                     ),
                   );
                }
              } else {
                try { await AlarmIntegration.cancel(alarm.id); } catch (_) {}
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    enabled = widget.alarm.enabled;
  }

  String _repeatText(List<int> days) {
    const map = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => map[d - 1]).join(', ');
  }

  DateTime _nextDateFor(Alarm alarm) {
    return AlarmUtils.computeNextAlarmDate(
      hour: alarm.hour,
      minute: alarm.minute,
      second: alarm.second,
      isAm: alarm.isAm,
      repeatDays: alarm.repeatDays,
    );
  }
}

class NewAlarmSheet extends StatefulWidget {
  final bool is24h;
  const NewAlarmSheet({super.key, required this.is24h});

  @override
  State<NewAlarmSheet> createState() => _NewAlarmSheetState();
}

class EditAlarmSheet extends StatefulWidget {
  final Alarm alarm;
  final bool is24h;
  const EditAlarmSheet({super.key, required this.alarm, required this.is24h});

  @override
  State<EditAlarmSheet> createState() => _EditAlarmSheetState();
}

class _EditAlarmSheetState extends State<EditAlarmSheet> {
  late int hour;
  late int minute;
  late int second;
  late bool isAm;
  late bool sunrise;
  late String label;
  late Set<int> repeat;
  String? soundUri;
  String soundTitle = 'Default';
  late ChallengeType challengeType;

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    hour = a.hour;
    minute = widget.alarm.minute;
    second = widget.alarm.second;
    isAm = widget.alarm.isAm;
    sunrise = a.sunrise;
    label = a.label;
    repeat = a.repeatDays.toSet();
    challengeType = a.challengeType;
    // Load existing sound if present
    SharedPreferences.getInstance().then((prefs) {
      final s = prefs.getString('alarm_sound_${a.id}') ?? '';
      if (mounted) setState(() => soundUri = s.isNotEmpty ? s : null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Live preview of the next alarm time for current selection
    final preview = AlarmUtils.computeNextAlarmDate(
      hour: hour,
      minute: minute,
      second: second,
      isAm: isAm,
      repeatDays: repeat.toList(),
    );
    final previewFmt = DateFormat(widget.is24h ? 'EEE, MMM d • HH:mm:ss' : 'EEE, MMM d • h:mm:ss a');

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const DragHandle(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Edit Alarm', style: TextStyle(fontSize: 18)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () { AppFeedback.tap(); Navigator.pop(context); },
                ),
              ],
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TimeWheel(
                  value: widget.is24h ? (isAm ? (hour == 12 ? 0 : hour) : (hour == 12 ? 12 : hour + 12)) : hour,
                  max: widget.is24h ? 23 : 12,
                  onChanged: (v) => setState(() {
                    if (widget.is24h) {
                      isAm = v < 12;
                      hour = (v % 12 == 0) ? 12 : (v % 12);
                    } else {
                      hour = v;
                    }
                  }),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':', style: TextStyle(fontSize: 36)),
                ),
                TimeWheel(value: minute, max: 59, onChanged: (v) => setState(() => minute = v)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':', style: TextStyle(fontSize: 36)),
                ),
                TimeWheel(value: second, max: 59, onChanged: (v) => setState(() => second = v)),
                if (!widget.is24h) ...[
                  const SizedBox(width: 4),
                  Column(
                    children: [
                      AmPmChip(text: 'AM', active: isAm, onTap: () => setState(() => isAm = true)),
                      const SizedBox(height: 8),
                      AmPmChip(text: 'PM', active: !isAm, onTap: () => setState(() => isAm = false)),
                    ],
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),
            Text('Next alarm', style: TextStyle(color: mutedText(context))),
            const SizedBox(height: 4),
            Text(previewFmt.format(preview), style: const TextStyle(fontSize: 16)),

            const SizedBox(height: 24),

            TextField(
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'Alarm label',
              ),
              controller: TextEditingController(text: label),
              onChanged: (v) => label = v,
            ),

            const SizedBox(height: 20),

            Align(
              alignment: Alignment.centerLeft,
              child: Text('Repeat', style: TextStyle(color: mediumText(context))),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                // 1=Mon ... 7=Sun
                final labels = ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'];
                final day = i + 1;
                final selected = repeat.contains(day);
                return GestureDetector(
                  onTap: () => setState(() {
                    selected ? repeat.remove(day) : repeat.add(day);
                  }),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        selected ? kPrimary : chipBg(context),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: selected ? Colors.white : mediumText(context),
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 20),

            SectionCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: const Icon(Icons.wb_sunny),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sunrise Alarm'),
                        Text(
                          'Gradual screen brightness',
                          style: TextStyle(color: mutedText(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: sunrise,
                    onChanged: (v) => setState(() => sunrise = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            SectionCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.purple,
                        child: Icon(Icons.psychology),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Wake-Proof Challenge'),
                            Text(
                              challengeType == ChallengeType.none
                                  ? 'No challenge'
                                  : challengeType == ChallengeType.math
                                      ? 'Math problems'
                                      : 'Pattern matching',
                              style: TextStyle(color: mutedText(context), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: challengeType != ChallengeType.none,
                        onChanged: (v) => setState(() => challengeType = v ? ChallengeType.math : ChallengeType.none),
                      ),
                    ],
                  ),
                  if (challengeType != ChallengeType.none) ...[
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        FilterChip(
                          label: const Text('Math'),
                          selected: challengeType == ChallengeType.math,
                          onSelected: (v) { if (v) setState(() => challengeType = ChallengeType.math); },
                        ),
                        FilterChip(
                          label: const Text('Pattern'),
                          selected: challengeType == ChallengeType.pattern,
                          onSelected: (v) { if (v) setState(() => challengeType = ChallengeType.pattern); },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Sound selection
            SectionCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.volume_up),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sound'),
                        Text(
                          soundUri == null ? 'Default' : soundTitle,
                          style: TextStyle(color: mutedText(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      const ch = MethodChannel('serenity/ringtone');
                      try {
                        final res = await ch.invokeMethod<Map>('pick', {
                          'currentUri': soundUri ?? ''
                        });
                        if (res != null && mounted) {
                          setState(() {
                            soundUri = (res['uri'] as String?)?.isNotEmpty == true ? res['uri'] as String : null;
                            soundTitle = (res['title'] as String?) ?? 'Default';
                          });
                        }
                      } catch (_) {}
                    },
                    child: const Text('Choose'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            FilledButton(
              onPressed: () async {
                AdProvider.showInterstitial();
                AppFeedback.tap();
                // Persist sound choice for this alarm
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('alarm_sound_${widget.alarm.id}', soundUri ?? '');
                } catch (_) {}
                if (!mounted) return;
                Navigator.pop(
                  context,
                  Alarm(
                    id: widget.alarm.id,
                    hour: hour,
                    minute: minute,
                    second: second,
                    isAm: isAm,
                    label: label,
                    repeatDays: repeat.toList(),
                    sunrise: sunrise,
                    enabled: widget.alarm.enabled,
                    challengeType: challengeType,
                  ),
                );
              },
              child: const Text('Save Changes'),
            ),
            const SizedBox(height: 12),
            const BannerAdWidget(),
          ],
        ),
      ),
    );
  }

  
}
class _NewAlarmSheetState extends State<NewAlarmSheet> {
  int hour = 12;
  int minute = 0;
  int second = 0;
  bool isAm = true;
  bool sunrise = false;
  String label = '';
  String? soundUri;
  String soundTitle = 'Default';
  ChallengeType challengeType = ChallengeType.none;
  final Set<int> repeat = {};

  Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;
    const channel = MethodChannel('serenity/exact_alarm');
    try {
      await channel.invokeMethod('openExactAlarmSettings');
    } catch (e) {
      debugPrint('Failed to open exact alarm settings: $e');
    }
  }

  // nextAlarmDate moved to top-level helper `computeNextAlarmDate`

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final res = await Permission.notification.request();
    if (res.isGranted) return true;
    const channel = MethodChannel('serenity/notification_settings');
    try {
      await channel.invokeMethod('openNotificationSettings');
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const DragHandle(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('New Alarm', style: TextStyle(fontSize: 18)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TimeWheel(
                  value: widget.is24h ? (isAm ? (hour == 12 ? 0 : hour) : (hour == 12 ? 12 : hour + 12)) : hour,
                  max: widget.is24h ? 23 : 12,
                  onChanged: (v) => setState(() {
                    if (widget.is24h) {
                      isAm = v < 12;
                      hour = (v % 12 == 0) ? 12 : (v % 12);
                    } else {
                      hour = v;
                    }
                  }),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':', style: TextStyle(fontSize: 36)),
                ),
                TimeWheel(value: minute, max: 59, onChanged: (v) => setState(() => minute = v)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':', style: TextStyle(fontSize: 36)),
                ),
                TimeWheel(value: second, max: 59, onChanged: (v) => setState(() => second = v)),
                if (!widget.is24h) ...[
                  const SizedBox(width: 4),
                  Column(
                    children: [
                      AmPmChip(text: 'AM', active: isAm, onTap: () => setState(() => isAm = true)),
                      const SizedBox(height: 4),
                      AmPmChip(text: 'PM', active: !isAm, onTap: () => setState(() => isAm = false)),
                    ],
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            TextField(
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'Alarm label',
              ),
              onChanged: (v) => label = v,
            ),

            const SizedBox(height: 20),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Repeat',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final labels = ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'];
                final day = i + 1;
                final selected = repeat.contains(day);
                return GestureDetector(
                  onTap: () => setState(() {
                    selected ? repeat.remove(day) : repeat.add(day);
                  }),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        selected ? kPrimary : chipBg(context),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: selected ? Colors.white : mediumText(context),
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 12),

            SectionCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.wb_sunny),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sunrise Alarm'),
                        Text(
                          'Gradual screen brightness',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: sunrise,
                    onChanged: (v) => setState(() => sunrise = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            SectionCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.purple,
                        child: Icon(Icons.psychology),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Wake-Proof Challenge'),
                            Text(
                              challengeType == ChallengeType.none
                                  ? 'No challenge'
                                  : challengeType == ChallengeType.math
                                      ? 'Math problems'
                                      : 'Pattern matching',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: challengeType != ChallengeType.none,
                        onChanged: (v) => setState(() => challengeType = v ? ChallengeType.math : ChallengeType.none),
                      ),
                    ],
                  ),
                  if (challengeType != ChallengeType.none) ...[
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        FilterChip(
                          label: const Text('Math'),
                          selected: challengeType == ChallengeType.math,
                          onSelected: (v) { if (v) setState(() => challengeType = ChallengeType.math); },
                        ),
                        FilterChip(
                          label: const Text('Pattern'),
                          selected: challengeType == ChallengeType.pattern,
                          onSelected: (v) { if (v) setState(() => challengeType = ChallengeType.pattern); },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Sound selection
            SectionCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.volume_up),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sound'),
                        Text(
                          soundTitle,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      const ch = MethodChannel('serenity/ringtone');
                      try {
                        final res = await ch.invokeMethod<Map>('pick', {
                          'currentUri': soundUri ?? ''
                        });
                        if (res != null && mounted) {
                          setState(() {
                            soundUri = (res['uri'] as String?)?.isNotEmpty == true ? res['uri'] as String : null;
                            soundTitle = (res['title'] as String?) ?? 'Default';
                          });
                        }
                      } catch (_) {}
                    },
                    child: const Text('Choose'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            // Summary
            // SectionCard(
            //   padding: const EdgeInsets.all(14),
            //   child: Row(
            //     children: [
            //       const Icon(Icons.info_outline),
            //       const SizedBox(width: 12),
            //       Expanded(
            //         child: Column(
            //           crossAxisAlignment: CrossAxisAlignment.start,
            //           children: [
            //             Text(label.isEmpty ? 'No label' : label),
            //             const SizedBox(height: 4),
            //             Text(
            //               repeat.isEmpty
            //                   ? 'One-time'
            //                   : repeat.map((d) {
            //                       const names = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
            //                       return names[d - 1];
            //                     }).join(' · '),
            //               style: TextStyle(color: mutedText(context), fontSize: 12),
            //             ),
            //             const SizedBox(height: 4),
            //             Text(
            //               'Sound: ' + soundTitle,
            //               style: TextStyle(color: mutedText(context), fontSize: 12),
            //             ),
            //             const SizedBox(height: 4),
            //             Text(
            //               sunrise ? 'Sunrise: Enabled' : 'Sunrise: Disabled',
            //               style: TextStyle(color: mutedText(context), fontSize: 12),
            //             ),
            //           ],
            //         ),
            //       ),
            //     ],
            //   ),
            // ),

            // const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
              onPressed: () async {
                AdProvider.showInterstitial();
                final nav = Navigator.of(context);
                final notifAllowed = await requestNotificationPermission();
                if (!notifAllowed) return;

                final alarmTime = AlarmUtils.computeNextAlarmDate(
                  hour: hour,
                  minute: minute,
                  second: second,
                  isAm: isAm,
                  repeatDays: repeat.toList(),
                );

                final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

                try {
                  // Persist sound first
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('alarm_sound_${id}', soundUri ?? '');

                  nav.pop(
                    Alarm(
                      id: id,
                      hour: hour,
                      minute: minute,
                      second: second,
                      isAm: isAm,
                      label: label,
                      repeatDays: repeat.toList(),
                      sunrise: sunrise,
                      enabled: true,
                      challengeType: challengeType,
                    ),
                  );
                } on PlatformException catch (e) {
                  if (e.code == 'exact_alarms_not_permitted') return;
                  rethrow;
                } catch (_) {
                   // Fallback for shared prefs errors
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Alarm'),
            ),
            ),
            const SizedBox(height: 12),
            const BannerAdWidget(),
          ],
        ),
      ),
    ));
  }

  
}

class AlarmUtils {
  /// Compute the next alarm date for given 12-hour time and optional repeat days.
  static DateTime computeNextAlarmDate({
    required int hour,
    required int minute,
    required int second,
    required bool isAm,
    required List<int> repeatDays,
  }) {
    int h = hour % 12;
    if (!isAm) h += 12;

    final now = DateTime.now();
    DateTime alarm = DateTime(now.year, now.month, now.day, h, minute, second);

    if (alarm.isBefore(now)) {
      alarm = alarm.add(const Duration(days: 1));
    }

    if (repeatDays.isNotEmpty) {
      while (!repeatDays.contains(alarm.weekday)) {
        alarm = alarm.add(const Duration(days: 1));
      }
    }

    return alarm;
  }

  static String getTimeUntil(DateTime when) {
    final now = DateTime.now();
    final diff = when.difference(now);
    if (diff.isNegative) return '0 minutes, 0 seconds';

    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    final secs = diff.inSeconds % 60;

    List<String> parts = [];
    if (hours > 0) parts.add('$hours hours');
    if (mins > 0 || hours > 0) parts.add('$mins minutes');
    parts.add('$secs seconds');

    return parts.join(', ');
  }
}

// ---------------- TIMER ----------------
class TimerScreen extends StatefulWidget {
  final bool is24h;
  const TimerScreen({super.key, required this.is24h});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  int totalSeconds = 0;
  int remainingSeconds = 0;
  Timer? _timer;
  bool isRunning = false;
  bool isPaused = false;

  // Selection state
  int selH = 0;
  int selM = 0;
  int selS = 0;

  // Settings
  bool soundEnabled = true;
  bool vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      soundEnabled = p.getBool('timer_sound') ?? true;
      vibrationEnabled = p.getBool('timer_vibration') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('timer_sound', soundEnabled);
    await p.setBool('timer_vibration', vibrationEnabled);
  }

  void startTimer(int seconds) {
    if (seconds <= 0) return;
    _timer?.cancel();
    setState(() {
      totalSeconds = seconds;
      remainingSeconds = seconds;
      isRunning = true;
      isPaused = false;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remainingSeconds <= 1) {
        t.cancel();
        _onComplete();
      } else {
        setState(() => remainingSeconds--);
      }
    });
  }

  void _onComplete() {
    setState(() {
      remainingSeconds = 0;
      isRunning = false;
    });

    if (vibrationEnabled) {
      HapticFeedback.vibrate();
      // Repeating vibration would be better, but simple vibrate for now
    }
    
    if (soundEnabled) {
      // Use the generic alarm sound if available, otherwise just system beep
      SystemSound.play(SystemSoundType.click);
    }

    // Show completion alert
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Timer Finished'),
        content: const Text('Your timer has completed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void pauseResume() {
    if (isPaused) {
      // Resume
      setState(() {
        isPaused = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (remainingSeconds <= 1) {
          t.cancel();
          _onComplete();
        } else {
          setState(() => remainingSeconds--);
        }
      });
    } else {
      // Pause
      _timer?.cancel();
      setState(() => isPaused = true);
    }
  }

  void cancelTimer() {
    _timer?.cancel();
    setState(() {
      totalSeconds = 0;
      remainingSeconds = 0;
      isRunning = false;
      isPaused = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: const Text('Timer'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (val) {
                  if (val == 'sound') {
                    setState(() => soundEnabled = !soundEnabled);
                  } else if (val == 'vibrate') {
                    setState(() => vibrationEnabled = !vibrationEnabled);
                  }
                  _saveSettings();
                },
                itemBuilder: (ctx) => [
                  CheckedPopupMenuItem(
                    value: 'sound',
                    checked: soundEnabled,
                    child: const Text('Sound'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'vibrate',
                    checked: vibrationEnabled,
                    child: const Text('Vibration'),
                  ),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),

          Expanded(
            child: isRunning ? _buildRunning() : _buildSetup(),
          ),
        ],
      ),
    );
  }

  Widget _buildSetup() {
    return Column(
      children: [
        const SizedBox(height: 60),
        
        // Picker Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _wheelWithLabel('Hours', selH, 23, (v) => setState(() => selH = v)),
            const _PickerSep(),
            _wheelWithLabel('Minutes', selM, 59, (v) => setState(() => selM = v)),
            const _PickerSep(),
            _wheelWithLabel('Seconds', selS, 59, (v) => setState(() => selS = v)),
          ],
        ),

        const Spacer(),

        // Circular Presets Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TimerPresetCircle(label: '00:10:00', onSelect: () => startTimer(600)),
            const SizedBox(width: 20),
            _TimerPresetCircle(label: '00:15:00', onSelect: () => startTimer(900)),
            const SizedBox(width: 20),
            _TimerPresetCircle(label: '00:30:00', onSelect: () => startTimer(1800)),
          ],
        ),

        const SizedBox(height: 60),

        // Start Button
        Padding(
          padding: const EdgeInsets.only(bottom: 60),
          child: SizedBox(
            width: 200,
            height: 58,
            child: FilledButton(
              onPressed: () {
                AppFeedback.tap();
                final total = (selH * 3600) + (selM * 60) + selS;
                if (total > 0) startTimer(total);
              },
              // style: FilledButton.styleFrom(
              //   // backgroundColor: const Color(0xFF5E5CE6),
              //   shape: const StadiumBorder(),
              // ),
              child: const Text('Start', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRunning() {
    final progress = totalSeconds == 0 ? 0.0 : (remainingSeconds / totalSeconds);
    
    final h = remainingSeconds ~/ 3600;
    final m = (remainingSeconds % 3600) ~/ 60;
    final s = remainingSeconds % 60;

    final timeStr = h > 0 
      ? '${h.toString()}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString()}:${s.toString().padLeft(2, '0')}';

    return Column(
      children: [
        const SizedBox(height: 40),
        
        // Progress Ring
        SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(300, 300),
                painter: _TimerRingPainter(1 - progress, chipBg(context).withValues(alpha: 0.5)),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (h > 0 || m > 0)
                    Text(
                      h > 0 ? '${h}h ${m}m' : '${m}m',
                      style: TextStyle(color: mutedText(context), fontSize: 16),
                    ),
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_active_outlined, size: 14, color: subtleText(context)),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat(widget.is24h ? 'HH:mm' : 'h:mm a').format(
                          DateTime.now().add(Duration(seconds: remainingSeconds)),
                        ),
                        style: TextStyle(color: subtleText(context), fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        const Spacer(),

        // Controls
        Padding(
          padding: const EdgeInsets.only(bottom: 60, left: 32, right: 32),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: () {
                      AppFeedback.tap();
                      AdProvider.showInterstitial();
                      cancelTimer();
                    },
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      side: BorderSide(color: mutedText(context).withValues(alpha: 0.2)),
                    ),
                    child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: FilledButton(
              onPressed: () { AppFeedback.tap(); pauseResume(); },
              style: FilledButton.styleFrom(
                backgroundColor: isPaused ? kPrimary : const Color(0xFFE53935),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: Text(isPaused ? 'Resume' : 'Pause'),
            ),
          ),
        ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wheelWithLabel(String label, int val, int max, ValueChanged<int> onCh) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        TimeWheel(value: val, max: max, onChanged: onCh, showHighlight: false),
      ],
    );
  }
}

class _PickerSep extends StatelessWidget {
  const _PickerSep();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 24, left: 4, right: 4),
      child: Text(':', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
    );
  }
}

class _TimerPresetCircle extends StatelessWidget {
  final String label;
  final VoidCallback onSelect;
  const _TimerPresetCircle({required this.label, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        width: 70,
        height: 70,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w400,color: Colors.white),
        ),
      ),
    );
  }
}


class _PresetButton extends StatelessWidget {
  final int min;
  final VoidCallback onTap;

  const _PresetButton({required this.min, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: chipBg(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          min == 60 ? '1 hour' : '$min min',
          style: TextStyle(fontSize: 14, color: mediumText(context)),
        ),
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  final Color bgColor;
  _TimerRingPainter(this.progress, this.bgColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 12;

    final bgPaint = Paint()
      ..color = bgColor
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke;

    final fgPaint = Paint()
      ..color = kPrimary
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final angle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      angle,
      false,
      fgPaint,
    );

    // Top dot
    final dotAngle = -pi / 2 + angle;
    final dotOffset = Offset(
      center.dx + radius * cos(dotAngle),
      center.dy + radius * sin(dotAngle),
    );

    canvas.drawCircle(dotOffset, 5, Paint()..color = fgPaint.color);
  }

  @override
  bool shouldRepaint(covariant _TimerRingPainter old) =>
      old.progress != progress;
}

// ---------------- STOPWATCH ----------------
class StopwatchScreen extends StatefulWidget {
  const StopwatchScreen({super.key});

  @override
  State<StopwatchScreen> createState() => _StopwatchScreenState();
}

class _StopwatchScreenState extends State<StopwatchScreen> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  final List<Duration> _laps = [];

  void _start() {
    _stopwatch.start();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 30),
      (_) => setState(() {}),
    );
  }

  void _stop() {
    _stopwatch.stop();
    _ticker?.cancel();
    setState(() {});
  }

  void _lap() {
    if (_stopwatch.isRunning) {
      setState(() {
        _laps.insert(0, _stopwatch.elapsed);
      });
    }
  }

  void _reset() {
    _stopwatch.reset();
    _laps.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$ms';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _stopwatch.elapsed;
    final isRunning = _stopwatch.isRunning;

    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (elapsed.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0');

    // Pre-calculate fastest/slowest for the lap list
    Duration? fastestLap;
    Duration? slowestLap;
    if (_laps.length >= 2) {
      fastestLap = _laps.reduce((a, b) => a < b ? a : b);
      slowestLap = _laps.reduce((a, b) => a > b ? a : b);
      if (fastestLap == slowestLap) {
        fastestLap = null;
        slowestLap = null;
      }
    }

    return SafeArea(
      child: Column(
        children: [
          AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: const Text('Stopwatch'),
          ),

          const SizedBox(height: 60),

          // ===== TIME DISPLAY =====
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$minutes:$seconds',
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -1,
                ),
              ),
              Text(
                '.$millis',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  color: mutedText(context),
                ),
              ),
            ],
          ),

          const SizedBox(height: 60),

          // ===== CONTROLS =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Lap / Reset Button
                _ControlCircle(
                  label: isRunning ? 'Lap' : 'Reset',
                  onPressed: isRunning 
                    ? () { AppFeedback.tap(); _lap(); } 
                    : (elapsed.inMilliseconds > 0 ? () { AppFeedback.tap(); _reset(); } : null),
                  color: chipBg(context),
                ),

                // Start / Stop Button
                _ControlCircle(
                  label: isRunning ? 'Stop' : 'Start',
                  onPressed: isRunning 
                    ? () { 
                        AppFeedback.tap(); 
                        AdProvider.showInterstitial();
                        _stop(); 
                      } 
                    : () { AppFeedback.tap(); _start(); },
                  color: Colors.blue,
                  textColor: Colors.white,
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ===== LAPS LIST =====
          if (_laps.isNotEmpty)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _laps.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: dividerColor(context)),
                itemBuilder: (context, index) {
                  final lapTime = _laps[index];
                  final lapNumber = _laps.length - index;

                  final isFastest = fastestLap != null && lapTime == fastestLap;
                  final isSlowest = slowestLap != null && lapTime == slowestLap;

                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  Color color = Theme.of(context).colorScheme.onSurface;
                  if (isFastest) {
                    color = isDark ? Colors.greenAccent : const Color(0xFF2E7D32);
                  } else if (isSlowest) {
                    color = isDark ? Colors.redAccent : const Color(0xFFC62828);
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lap $lapNumber',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          _format(lapTime),
                          style: TextStyle(
                            fontSize: 16,
                            color: color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlCircle extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color? textColor;

  const _ControlCircle({
    required this.label,
    required this.onPressed,
    required this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = onPressed == null ? 0.3 : 1.0;
    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 80,
          height: 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor ?? Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}


// ---------------- REMINDER ----------------
enum Priority { high, medium, low }

class Reminder {
  final int id;
  final String title;
  DateTime dateTime; // Must be mutable for recurrence
  bool isEnabled;
  bool isCompleted;
  RecurrenceType recurrenceType;
  int recurrenceInterval;
  Priority priority;
  bool soundEnabled;
  bool vibrateEnabled;

  Reminder({
    required this.id,
    required this.title,
    required this.dateTime,
    this.isEnabled = true,
    this.isCompleted = false,
    this.recurrenceType = RecurrenceType.none,
    this.recurrenceInterval = 1,
    this.priority = Priority.medium,
    this.soundEnabled = true,
    this.vibrateEnabled = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'dateTime': dateTime.toIso8601String(),
        'isEnabled': isEnabled,
        'isCompleted': isCompleted,
        'recurrenceType': recurrenceType.index,
        'recurrenceInterval': recurrenceInterval,
        'priority': priority.index,
        'soundEnabled': soundEnabled,
        'vibrateEnabled': vibrateEnabled,
      };

  static Reminder fromMap(Map<String, dynamic> m) => Reminder(
        id: m['id'] as int,
        title: m['title'] as String,
        dateTime: DateTime.parse(m['dateTime'] as String),
        isEnabled: m['isEnabled'] as bool? ?? true,
        isCompleted: m['isCompleted'] as bool? ?? false,
        recurrenceType: RecurrenceType.values[m['recurrenceType'] as int? ?? 0],
        recurrenceInterval: m['recurrenceInterval'] as int? ?? 1,
        priority: Priority.values[m['priority'] as int? ?? 1],
        soundEnabled: m['soundEnabled'] as bool? ?? true,
        vibrateEnabled: m['vibrateEnabled'] as bool? ?? true,
      );
}

class ReminderScreen extends StatefulWidget {
  final bool is24h;
  const ReminderScreen({super.key, required this.is24h});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  final List<Reminder> reminders = [];

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('reminders');
    if (s == null || s.isEmpty) return;
    try {
      final list = (jsonDecode(s) as List<dynamic>)
          .map((e) => Reminder.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        reminders
          ..clear()
          ..addAll(list);
      });
    } catch (_) {}
  }

  Future<void> _saveReminders() async {
    final p = await SharedPreferences.getInstance();
    final s = jsonEncode(reminders.map((r) => r.toMap()).toList());
    await p.setString('reminders', s);
  }

  Future<void> _addReminder() async {
    final reminder = await showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: modalScrim(context),
      builder: (_) => NewReminderSheet(is24h: widget.is24h),
    );

    if (reminder != null) {
      setState(() => reminders.add(reminder));
      await _saveReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () { AppFeedback.tap(); Scaffold.of(context).openDrawer(); },
              ),
            ),
            title: const Text('Reminders'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add), 
                onPressed: () { 
                  AppFeedback.tap(); 
                  AdProvider.showInterstitial();
                  _addReminder(); 
                }
              ),
            ],
          ),
          Expanded(
            child: reminders.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: reminders.length,
                    itemBuilder: (context, i) {
                      final r = reminders[i];
                      final timeFmt = DateFormat(widget.is24h ? 'HH:mm' : 'h:mm a');
                      final dateFmt = DateFormat('MMM d, yyyy');

                      return Dismissible(
                        key: ValueKey(r.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) {
                          AppFeedback.tap();
                          setState(() => reminders.removeAt(i));
                          _saveReminders();
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.red),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            leading: Checkbox(
                                value: r.isCompleted, 
                                onChanged: (v) {
                                    AppFeedback.tap();
                                    setState(() {
                                        r.isCompleted = v ?? false;
                                        if (r.isCompleted) r.isEnabled = false;
                                    });
                                    _saveReminders();
                                },
                                shape: const CircleBorder(),
                            ),
                            title: Text(
                                r.title, 
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    decoration: r.isCompleted ? TextDecoration.lineThrough : null,
                                    color: r.isCompleted ? mutedText(context) : null,
                                ),
                            ),
                            subtitle: Text('${dateFmt.format(r.dateTime)} • ${timeFmt.format(r.dateTime)}'),
                            // trailing: Switch(
                            //   activeColor: kPrimary,
                            //   value: r.isEnabled,
                            //   onChanged: (v) {
                            //     AppFeedback.tap();
                            //     setState(() => r.isEnabled = v);
                            //     _saveReminders();
                            //   },
                            // ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () { 
                AppFeedback.tap(); 
                AdProvider.showInterstitial();
                _addReminder(); 
              },
              icon: const Icon(Icons.add),
              label: const Text('New Reminder'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: chipBg(context),
            child: Icon(Icons.notifications_outlined, size: 36, color: mutedText(context)),
          ),
          const SizedBox(height: 16),
          const Text('No reminders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('Tap + to set a new reminder', style: TextStyle(color: mutedText(context))),
        ],
      ),
    );
  }
}

class NewReminderSheet extends StatefulWidget {
  final bool is24h;
  const NewReminderSheet({super.key, required this.is24h});

  @override
  State<NewReminderSheet> createState() => _NewReminderSheetState();
}

class _NewReminderSheetState extends State<NewReminderSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  RecurrenceType _recurrence = RecurrenceType.none;
  Priority _priority = Priority.medium;
  bool _sound = true;
  bool _vibrate = true;

  @override
  void initState() {
    super.initState();
    // Round up to next 5 min
    final now = DateTime.now();
    _selectedTime = TimeOfDay(hour: now.hour, minute: (now.minute ~/ 5 + 1) * 5);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Matches the provided 'New Alarm/Reminder' UI mockup
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const DragHandle(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () { AppFeedback.tap(); Navigator.pop(context); },
                child: Text('Cancel', style: TextStyle(color: mutedText(context), fontSize: 17)),
              ),
              const Text('New Reminder', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              TextButton(
                onPressed: () { AppFeedback.tap(); _save(); },
                child: Text('Save', style: TextStyle(color: kPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          Expanded(
            child: ListView(
              children: [
                // 1. Time Wheel Area
                SizedBox(
                  height: 200,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.dateAndTime,
                    use24hFormat: widget.is24h,
                    initialDateTime: DateTime(
                      _selectedDate.year, 
                      _selectedDate.month, 
                      _selectedDate.day, 
                      _selectedTime.hour, 
                      _selectedTime.minute
                    ),
                    onDateTimeChanged: (d) {
                      AppFeedback.tap();
                      setState(() {
                        _selectedDate = d;
                        _selectedTime = TimeOfDay.fromDateTime(d);
                      });
                    },
                  ),
                ),
                
                const SizedBox(height: 30),

                // 2. Settings Group
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildTile(
                        label: 'Title',
                        content: TextField(
                          controller: _titleCtrl,
                          textAlign: TextAlign.center, 
                          textAlignVertical: TextAlignVertical.center,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Meeting, Workout...',
                            hintStyle: TextStyle(
                              color: subtleText(context).withValues(alpha: 0.4),
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        ),
                      ),
                      _divider(),
                      _buildTile(
                        label: 'Repeat',
                        value: _recurrenceName(_recurrence),
                        onTap: () { AppFeedback.tap(); _showRecurrencePicker(); },
                        hasArrow: true,
                      ),
                      _divider(),
                      _buildTile(
                        label: 'Sound',
                        value: _sound ? 'Default' : 'None',
                        onTap: () { AppFeedback.tap(); setState(() => _sound = !_sound); },
                        hasArrow: true,
                      ),
                      // _divider(),
                      // _buildTile(
                      //   label: 'Priority',
                      //   value: _priority.name.toUpperCase(),
                      //   onTap: _cyclePriority,
                      //   hasArrow: true,
                      // ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 3. Toggles
                 Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Vibrate'),
                        value: _vibrate,
                        onChanged: (v) => setState(() => _vibrate = v),
                        secondary: const Icon(Icons.vibration),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const BannerAdWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required String label, 
    String? value, 
    Widget? content, 
    VoidCallback? onTap, 
    bool hasArrow = false
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) Text(value, style: TextStyle(color: subtleText(context), fontSize: 16)),
          if (content != null) SizedBox(height: 50,width: 150, child: content),
          if (hasArrow) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: subtleText(context).withValues(alpha: 0.5)),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
  
  Widget _divider() {
    return Divider(height: 1, indent: 16, color: Theme.of(context).dividerColor.withValues(alpha: 0.5));
  }

  void _save() {
      final fullDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      
      // Schedule Native Alarm for this reminder
      AlarmIntegration.schedule(
        id: fullDate.millisecondsSinceEpoch ~/ 1000,
        label: _titleCtrl.text.isEmpty ? 'Reminder' : _titleCtrl.text,
        when: fullDate,
        soundUri: _sound ? null : '',
        type: 'reminder',
      );

      Navigator.pop(
        context,
        Reminder(
          id: fullDate.millisecondsSinceEpoch ~/ 1000,
          title: _titleCtrl.text.isEmpty ? 'Reminder' : _titleCtrl.text,
          dateTime: fullDate,
          recurrenceType: _recurrence,
          priority: _priority,
          soundEnabled: _sound,
          vibrateEnabled: _vibrate,
        ),
      );
  }

  void _cyclePriority() {
    setState(() {
      final nextIndex = (_priority.index + 1) % Priority.values.length;
      _priority = Priority.values[nextIndex];
    });
  }

  void _showRecurrencePicker() async {
    final res = await showModalBottomSheet<RecurrenceType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const RecurrencePickerSheet(),
    );
    if (res != null) setState(() => _recurrence = res);
  }

  String _recurrenceName(RecurrenceType t) {
    switch (t) {
      case RecurrenceType.none: return 'Does not repeat';
      case RecurrenceType.daily: return 'Every Day';
      case RecurrenceType.weekly: return 'Every Weekly';
      case RecurrenceType.monthly: return 'Every Monthly';
      case RecurrenceType.annually: return 'Every Year';
      case RecurrenceType.hourly: return 'Every Hour';
      default: return '';
    }
  }
}

class RecurrencePickerSheet extends StatelessWidget {
  const RecurrencePickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // Style matches the dark blue 'Remind me about...' picker
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final textCol = isDark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option(context, 'Does not repeat', RecurrenceType.none, textCol),
          _sep(context),
          _option(context, 'Repeats annually', RecurrenceType.annually, textCol),
           _sep(context),
          _option(context, 'Repeats monthly', RecurrenceType.monthly, textCol),
           _sep(context),
          _option(context, 'Repeats weekly', RecurrenceType.weekly, textCol),
           _sep(context),
          _option(context, 'Every hour', RecurrenceType.hourly, textCol),
          // Additional complex logic 'Custom...' could go here
        ],
      ),
    );
  }

  Widget _option(BuildContext context, String txt, RecurrenceType val, Color col) {
    return InkWell(
      onTap: () => Navigator.pop(context, val),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Text(txt, style: TextStyle(color: col, fontSize: 16)),
      ),
    );
  }
  
  Widget _sep(BuildContext context) {
    return Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.1));
  }
}




class ReminderTriggerScreen extends StatefulWidget {
  final Reminder reminder;
  const ReminderTriggerScreen({super.key, required this.reminder});

  @override
  State<ReminderTriggerScreen> createState() => _ReminderTriggerScreenState();
}

class _ReminderTriggerScreenState extends State<ReminderTriggerScreen> {
  late Reminder _r;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _r = widget.reminder;
    _syncFromStorage();
    AdProvider.showInterstitial();
  }

  Future<void> _syncFromStorage() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('reminders');
    if (s != null) {
      final list = (jsonDecode(s) as List).map((e) => Reminder.fromMap(Map<String, dynamic>.from(e))).toList();
      final found = list.where((e) => e.id == widget.reminder.id).firstOrNull;
      if (found != null) {
        if (mounted) setState(() { _r = found; _loading = false; });
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _complete() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('reminders');
    List<Reminder> list = [];
    if (s != null) {
      list = (jsonDecode(s) as List).map((e) => Reminder.fromMap(Map<String, dynamic>.from(e))).toList();
    }
    
    // Find matching ID
    final idx = list.indexWhere((e) => e.id == _r.id);
    if (idx != -1) {
       final item = list[idx];
       if (item.recurrenceType != RecurrenceType.none) {
           // Reschedule
           final next = _nextOccurrence(item.dateTime, item.recurrenceType);
           item.dateTime = next;
           item.isCompleted = false;
           // Schedule Native
           AlarmIntegration.schedule(
             id: item.id,
             label: item.title,
             when: next,
             soundUri: item.soundEnabled ? null : '',
             type: 'reminder',
           );
       } else {
           item.isCompleted = true;
           item.isEnabled = false;
           // Cancel native just in case
           AlarmIntegration.cancel(item.id);
       }
       list[idx] = item;
       await p.setString('reminders', jsonEncode(list.map((e) => e.toMap()).toList()));
    }
    
    if (mounted) Navigator.pop(context);
  }

  // Need helper _nextOccurrence here or make it static/global. 
  // For now duplicate logic or make the one in Shell static.
  // I will duplicate logic for safety/speed.
  DateTime _nextOccurrence(DateTime current, RecurrenceType type) {
      // Basic implementation
      switch (type) {
          case RecurrenceType.daily: return current.add(const Duration(days: 1));
          case RecurrenceType.weekly: return current.add(const Duration(days: 7));
          case RecurrenceType.monthly: return DateTime(current.year, current.month + 1, current.day, current.hour, current.minute);
          case RecurrenceType.annually: return DateTime(current.year + 1, current.month, current.day, current.hour, current.minute);
          case RecurrenceType.hourly: return current.add(const Duration(hours: 1));
          default: return current;
      }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('h:mm a'); 
    final dateFmt = DateFormat('EEEE, MMMM d yyyy');

    // Use _r which might be updated from storage
    return Scaffold(
      backgroundColor: const Color(0xFFC8E6C9), 
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(
              fmt.format(_r.dateTime), 
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
               dateFmt.format(_r.dateTime), 
               style: const TextStyle(fontSize: 18, color: Colors.black54),
            ),
            
            const SizedBox(height: 48),
            
            Container(
                width: 200, height: 200,
                decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                ),
                child: const Icon(Icons.medication, size: 80, color: Color(0xFF66BB6A)),
            ),
            const SizedBox(height: 16),
             Text(
               _r.title,
               style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.black87),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () { AppFeedback.tap(); _complete(); },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5D4037), 
                  ),
                  child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            const BannerAdWidget(),
          ],
        ),
      ),
    );
  }
}
class AppFeedback {
  static Future<void> tap() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('haptics_enabled') ?? true) {
      await HapticFeedback.lightImpact();
    }
    if (p.getBool('sound_effects_enabled') ?? true) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}

// ---------------- WORLD ----------------

// ---------------- WORLD ----------------
class WorldCity {
  final String name;
  final String tzid; // IANA timezone ID, e.g., "America/New_York"

  WorldCity(this.name, this.tzid);
}

class WorldClockScreen extends StatefulWidget {
  final bool is24h;
  const WorldClockScreen({super.key, required this.is24h});

  @override
  State<WorldClockScreen> createState() => _WorldClockScreenState();
}

class _WorldClockScreenState extends State<WorldClockScreen> {
  // Backed by SharedPreferences key 'world_cities' (JSON: [{name, tzid}, ...])
  final List<WorldCity> cities = [];

  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCities();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  Future<void> _loadCities() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('world_cities');
      if (raw == null || raw.isEmpty) {
        // Seed with defaults on first run
        cities.addAll([
          WorldCity('New York', 'America/New_York'),
          WorldCity('Los Angeles', 'America/Los_Angeles'),
          WorldCity('Chicago', 'America/Chicago'),
          WorldCity('London', 'Europe/London'),
          WorldCity('Paris', 'Europe/Paris'),
          WorldCity('Berlin', 'Europe/Berlin'),
          WorldCity('Moscow', 'Europe/Moscow'),
          WorldCity('Dubai', 'Asia/Dubai'),
          WorldCity('Singapore', 'Asia/Singapore'),
          WorldCity('Tokyo', 'Asia/Tokyo'),
          WorldCity('Sydney', 'Australia/Sydney'),
        ]);
        await _saveCities();
      } else {
        final arr = (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        cities
          ..clear()
          ..addAll(arr.map((m) => WorldCity(m['name'] as String, m['tzid'] as String)));
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveCities() async {
    try {
      final p = await SharedPreferences.getInstance();
      final data = cities.map((c) => {'name': c.name, 'tzid': c.tzid}).toList();
      final jsonStr = jsonEncode(data);
      final success = await p.setString('world_cities', jsonStr);
      if (!success) {
        debugPrint('Failed to save world cities to SharedPreferences');
      }
    } catch (e) {
      debugPrint('Error saving world cities: $e');
    }
  }

  Future<String> _localTzName() async {
    try {
      final dynamic info = await FlutterTimezone.getLocalTimezone();
      if (info is String) return info;
      final name = (info as dynamic).name as String?;
      return name ?? 'Local';
    } catch (_) {
      return 'Local';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat(widget.is24h ? 'HH:mm' : 'h:mm a');
    final localNow = DateTime.now();
    final localUtc = tz.TZDateTime.now(tz.getLocation('UTC'));

    return SafeArea(
      child: Column(
        children: [
          AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: const Text('World Clock'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () async {
                  AppFeedback.tap();
                  AdProvider.showInterstitial();
                  final city = await showModalBottomSheet<WorldCity>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    barrierColor: modalScrim(context),
                    builder: (_) => AddCitySheet(
                      existing: cities.map((e) => e.name).toList(),
                    ),
                  );
                  if (city != null && mounted) {
                    setState(() => cities.add(city));
                    await _saveCities();
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text('Local Time', style: TextStyle(color: mutedText(context))),
          const SizedBox(height: 4),
          Text(fmt.format(localNow), style: Theme.of(context).textTheme.displayLarge),
          const SizedBox(height: 4),
          FutureBuilder<String>(
            future: _localTzName(),
            builder: (context, snap) {
              final name = snap.data ?? 'Local';
              return Text(name, style: TextStyle(color: subtleText(context)));
            },
          ),

          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              children: cities.map((city) {
                final loc = tz.getLocation(city.tzid);
                final cityTime = tz.TZDateTime.now(loc);
                final isDay = cityTime.hour >= 6 && cityTime.hour < 18;
                final off = cityTime.timeZoneOffset;
                final sign = off.inMinutes >= 0 ? '+' : '-';
                final h = off.inHours.abs();
                final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
                final offStr = 'UTC$sign$h${m == '00' ? '' : ':$m'}';

                return _WorldCityCard(
                  city: city,
                  time: fmt.format(cityTime),
                  offset: offStr,
                  isDay: isDay,
                  onDelete: () async {
                    if (mounted) {
                      AppFeedback.tap();
                      setState(() => cities.remove(city));
                      await _saveCities();
                    }
                  },
                );
              }).toList(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () async {
                AppFeedback.tap();
                AdProvider.showInterstitial();
                final city = await showModalBottomSheet<WorldCity>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  barrierColor: modalScrim(context),
                  builder: (_) => AddCitySheet(
                    existing: cities.map((e) => e.name).toList(),
                  ),
                );
                if (city != null && mounted) {
                  setState(() => cities.add(city));
                  await _saveCities();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add City'),
            ),
          ),
          
        ],
      ),
    );
  }
}



class _WorldCityCard extends StatelessWidget {
  final WorldCity city;
  final String time;
  final String offset;
  final bool isDay;
  final VoidCallback onDelete;

  const _WorldCityCard({
    required this.city,
    required this.time,
    required this.offset,
    required this.isDay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            isDay ? Icons.wb_sunny : Icons.nights_stay,
            color: isDay ? Colors.orange : Colors.purpleAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(city.name, style: const TextStyle(fontSize: 18)),
                Text(offset, style: TextStyle(color: mutedText(context))),
              ],
            ),
          ),
          Text(time, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class AddCitySheet extends StatefulWidget {
  final List<String> existing;
  const AddCitySheet({super.key, required this.existing});

  @override
  State<AddCitySheet> createState() => _AddCitySheetState();
}

class _AddCitySheetState extends State<AddCitySheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final dbLocations = tz.timeZoneDatabase.locations.keys.toList()..sort();
    
    final filtered = dbLocations
        .where((k) {
          if (query.isEmpty) return true;
          return k.toLowerCase().contains(query.toLowerCase());
        })
        .take(100)
        .map((k) {
          final displayName = k.split('/').last.replaceAll('_', ' ');
          return WorldCity(displayName, k);
        })
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const DragHandle(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Select time zone', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 12),

          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search for a city',
              prefixIcon: Icon(Icons.search),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          // Removed BannerAdWidget from here
          const SizedBox(height: 8),

          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final c = filtered[index];
                final loc = tz.getLocation(c.tzid);
                final time = tz.TZDateTime.now(loc);
                final timeStr = DateFormat('HH:mm').format(time);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  title: Text(
                    c.tzid,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
                  ),
                  trailing: Text(
                    timeStr,
                    style: const TextStyle(fontSize: 16, letterSpacing: 0.5),
                  ),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
          const BannerAdWidget(),
        ],
      ),
    );
  }
}


// ---------------- SETTINGS ----------------
class SettingsDrawer extends StatefulWidget {
  final bool is24h;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<bool> on24h;

  const SettingsDrawer({
    super.key,
    required this.is24h,
    required this.mode,
    required this.onTheme,
    required this.on24h,
  });

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  int snoozeMinutes = 5;
  int sunriseMinutes = 15;
  bool haptics = true;
  bool soundEffects = true;
  bool floatingEnabled = false;

  @override
  void initState() {
      super.initState();
      _loadSettings();
  }

  Future<void> _loadSettings() async {
      final p = await SharedPreferences.getInstance();
      setState(() {
          haptics = p.getBool('haptics_enabled') ?? true;
          soundEffects = p.getBool('sound_effects_enabled') ?? true;
          snoozeMinutes = p.getInt('snooze_minutes') ?? 5;
          floatingEnabled = p.getBool('floating_enabled') ?? false;
      });
  }

  Future<void> _toggleFloating(bool v) async {
    const ch = MethodChannel('serenity/alarm_manager');
    if (v) {
      final allowed = await ch.invokeMethod<bool>('canDrawOverlays') ?? false;
      if (!allowed) {
        await ch.invokeMethod('openOverlaySettings');
        return;
      }
      await ch.invokeMethod('startFloatingIcon');
    } else {
      await ch.invokeMethod('stopFloatingIcon');
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('floating_enabled', v);
    setState(() => floatingEnabled = v);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 16),
            const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

          // ===== APPEARANCE =====
          const _SectionTitle('Appearance'),
          SectionCard(
            child: Column(
              children: [
                _radioRow(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Light',
                  selected: widget.mode == ThemeMode.light,
                  onTap: () { AppFeedback.tap(); widget.onTheme(ThemeMode.light); },
                ),
                _divider(),
                _radioRow(
                  icon: Icons.nights_stay_outlined,
                  title: 'Dark',
                  selected: widget.mode == ThemeMode.dark,
                  onTap: () { AppFeedback.tap(); widget.onTheme(ThemeMode.dark); },
                ),
                _divider(),
                _radioRow(
                  icon: Icons.phone_android_outlined,
                  title: 'System',
                  selected: widget.mode == ThemeMode.system,
                  onTap: () { AppFeedback.tap(); widget.onTheme(ThemeMode.system); },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ===== TIME FORMAT =====
          const _SectionTitle('Time Format'),
          SectionCard(
            child: Column(
              children: [
                _radioRow(
                  icon: Icons.access_time,
                  title: '12-hour',
                  subtitle: '7:30 AM',
                  selected: !widget.is24h,
                  onTap: () { AppFeedback.tap(); widget.on24h(false); },
                ),
                _divider(),
                _radioRow(
                  icon: Icons.access_time,
                  title: '24-hour',
                  subtitle: '19:30',
                  selected: widget.is24h,
                  onTap: () { AppFeedback.tap(); widget.on24h(true); },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ===== DEFAULTS =====
          const _SectionTitle('Defaults'),
          SectionCard(
            child: Column(
              children: [
                _dropdownRow(
                  icon: Icons.snooze,
                  title: 'Default Snooze',
                  subtitle: 'Duration for snooze',
                  value: snoozeMinutes,
                  items: const [5, 10, 15],
                  suffix: 'min',
                  onChanged: (v) async {
                    setState(() => snoozeMinutes = v);
                    try {
                      final p = await SharedPreferences.getInstance();
                      await p.setInt('snooze_minutes', v);
                    } catch (_) {}
                  },
                ),
                _divider(),
                _dropdownRow(
                  icon: Icons.wb_sunny,
                  title: 'Default Sunrise',
                  subtitle: 'Duration for sunrise alarm',
                  value: sunriseMinutes,
                  items: const [5, 10, 15, 30],
                  suffix: 'min',
                  onChanged: (v) => setState(() => sunriseMinutes = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ===== FEEDBACK =====
          const _SectionTitle('Feedback'),
          SectionCard(
            child: Column(
              children: [
                SwitchListTile(
                  value: haptics,
                  onChanged: (v) async {
                      setState(() => haptics = v);
                      final p = await SharedPreferences.getInstance();
                      await p.setBool('haptics_enabled', v);
                      AppFeedback.tap();
                  },
                  secondary: const Icon(Icons.vibration),
                  title: const Text('Haptic Feedback'),
                  subtitle: const Text('Vibration on interactions'),
                ),
                _divider(),
                SwitchListTile(
                  value: soundEffects,
                  onChanged: (v) async {
                      setState(() => soundEffects = v);
                      final p = await SharedPreferences.getInstance();
                      await p.setBool('sound_effects_enabled', v);
                      AppFeedback.tap();
                  },
                  secondary: const Icon(Icons.volume_up),
                  title: const Text('Sound Effects'),
                  subtitle: const Text('Click sounds on interactions'),
                ),
                 _divider(),
                 _radioRow(
                    icon: Icons.do_not_disturb_on, 
                    title: 'Silent Mode', 
                    subtitle: 'Disable all sounds & haptics',
                    selected: !haptics && !soundEffects, 
                    onTap: () async {
                         setState(() {
                             haptics = false;
                             soundEffects = false;
                         });
                         final p = await SharedPreferences.getInstance();
                         await p.setBool('haptics_enabled', false);
                         await p.setBool('sound_effects_enabled', false);
                    },
                 ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ===== SHORTCUTS =====
          // const _SectionTitle('Shortcuts'),
          // SectionCard(
          //   child: Column(
          //     children: [
          //       SwitchListTile(
          //         value: floatingEnabled,
          //         onChanged: _toggleFloating,
          //         secondary: const Icon(Icons.ads_click),
          //         title: const Text('Floating Shortcut'),
          //         subtitle: const Text('One-touch access to app'),
          //       ),
          //     ],
          //   ),
          // ),

          // ===== FOOTER =====
          Column(
            children: [
              const Icon(Icons.wb_sunny, color: Colors.orange, size: 32),
              const SizedBox(height: 8),
              const Text('Serenity', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              Text('Version 1.0.0', style: TextStyle(color: mutedText(context))),
              const SizedBox(height: 6),
              Text(
                'A calm, reliable alarm companion',
                style: TextStyle(color: subtleText(context)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const BannerAdWidget(),
          

          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  }

  // ===== HELPERS =====

  Widget _divider() {
    return Divider(
      height: 1,
      color: Theme.of(context)
          .colorScheme
          .onSurface
          .withValues(alpha: 0.12),
    );
  }

  Widget _radioRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: selected ? kPrimary : mutedText(context)),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Radio<bool>(
        value: true,
        groupValue: selected ? true : false,
        onChanged: (_) => onTap(),
      ),

      onTap: onTap,
    );
  }

  Widget _dropdownRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required int value,
    required List<int> items,
    required String suffix,
    required ValueChanged<int> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox(),
        items: items
            .map((v) => DropdownMenuItem(value: v, child: Text('$v $suffix')))
            .toList(),
        onChanged: (v) => onChanged(v!),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(color: mutedText(context), fontSize: 14),
      ),
    );
  }
}

class RingingScreen extends StatelessWidget {
  final int alarmId;
  final String label;
  final int challengeType;
  final bool sunrise;
  const RingingScreen({super.key, required this.alarmId, required this.label, this.challengeType = 0, this.sunrise = false});

  @override
  Widget build(BuildContext context) {
    // Replace with wake-proof interaction screen (press & hold) while retaining Snooze inside that screen
    return WakeProofScreen(alarmId: alarmId, label: label, challengeType: challengeType, sunrise: sunrise);
  }
}

// ---------------- SHARED UI ----------------
class DragHandle extends StatelessWidget {
  const DragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class AmPmChip extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  const AmPmChip({super.key, required this.text, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? kPrimary : chipBg(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text),
      ),
    );
  }
}

class TimeWheel extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  final bool showHighlight;
  const TimeWheel({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.showHighlight = true,
  });

  @override
  Widget build(BuildContext context) {
    const itemExtent = 50.0;
    final count = max == 12 ? 12 : max + 1;
    final children = List.generate(
      count,
      (i) => Center(
        child: Text(
          (max == 12 && i == 0 ? 12 : i).toString().padLeft(2, '0'),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );

    return SizedBox(
      width: 58,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ListWheelScrollView.useDelegate(
            controller: FixedExtentScrollController(
              initialItem: (max == 12 && value == 12) ? 0 : value,
            ),
            itemExtent: itemExtent,
            perspective: 0.004,
            physics: const FixedExtentScrollPhysics(),
            overAndUnderCenterOpacity: 0.3,
            useMagnifier: true,
            magnification: 1.15,
            onSelectedItemChanged: (i) {
              AppFeedback.tap(); 
              final idx = (i % count + count) % count;
              onChanged((max == 12 && idx == 0) ? 12 : idx);
            },
            childDelegate: ListWheelChildLoopingListDelegate(children: children),
          ),
          if (showHighlight)
            IgnorePointer(
              child: Container(
                height: itemExtent + 6,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const SectionCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}