// Serenity Clock App — Pixel-perfect update (UI + behavior refined)
// Matches provided screenshots with glass cards, circular timer ring,
// AM/PM picker, repeat days, world cards, and settings sections.
// ---------------------------------------------------------------
// Required deps (pubspec.yaml):
// intl: ^0.19.0
// shared_preferences: ^2.2.2
// flutter_local_notifications: ^17.0.0
// timezone: ^0.9.2
// flutter_timezone: ^1.0.8
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'alarm_integration.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Listen for native full-screen alarm activity to push Ringing UI
  const MethodChannel('serenity/current_alarm').setMethodCallHandler((call) async {
    if (call.method == 'push') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final id = (args['alarm_id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final label = (args['label'] as String?) ?? 'Alarm';
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => RingingScreen(alarmId: id, label: label)),
      );
    }
    return null;
  });
  runApp(const SerenityApp());
}

// ---------------- APP ROOT ----------------
class SerenityApp extends StatefulWidget {
  const SerenityApp({super.key});
  @override
  State<SerenityApp> createState() => _SerenityAppState();
}

class _SerenityAppState extends State<SerenityApp> {
  ThemeMode mode = ThemeMode.dark;
  bool is24h = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      mode = ThemeMode.values[p.getInt('theme') ?? 1];
      is24h = p.getBool('is24h') ?? false;
    });
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
      navigatorKey: navigatorKey,
      themeMode: mode,
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/ringing') || name.startsWith('ringing')) {
          final uri = Uri.parse(name.startsWith('/') ? name : '/$name');
          final idStr = uri.queryParameters['alarm_id'];
          final id = int.tryParse(idStr ?? '') ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final label = uri.queryParameters['label'] ?? 'Alarm';
          return MaterialPageRoute(builder: (_) => RingingScreen(alarmId: id, label: label));
        }
        return null; // fallback to default
      },

      theme: ThemeData(
        useMaterial3: false,
        brightness: Brightness.light,
        scaffoldBackgroundColor: kLightBg,
        primaryColor: kPrimary,
        cardColor: kLightCard,
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

      home: Shell(is24h: is24h, onTheme: saveTheme, on24h: save24, mode: mode),
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      AlarmScreen(is24h: widget.is24h),
      const TimerScreen(),
      const StopwatchScreen(),
      WorldClockScreen(is24h: widget.is24h),
      SettingsScreen(
        is24h: widget.is24h,
        mode: widget.mode,
        on24h: widget.on24h,
        onTheme: widget.onTheme,
      ),
    ];

    return Scaffold(
      body: pages[index],
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            indicatorColor: kPrimary.withOpacity(0.15),
            labelTextStyle: MaterialStateProperty.all(
              TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
        ),
        child: NavigationBar(
          height: 72,
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.alarm_outlined),
              label: 'Alarm',
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
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- ALARM ----------------
class Alarm {
  int id;
  int hour;
  int minute;
  bool isAm;
  String label;
  List<int> repeatDays; // 1=Mon ... 7=Sun
  bool sunrise;
  bool enabled;

  Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.isAm,
    required this.label,
    required this.repeatDays,
    required this.sunrise,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'isAm': isAm,
        'label': label,
        'repeatDays': repeatDays,
        'sunrise': sunrise,
        'enabled': enabled,
      };

  static Alarm fromMap(Map<String, dynamic> m) => Alarm(
        id: m['id'] as int,
        hour: m['hour'] as int,
        minute: m['minute'] as int,
        isAm: m['isAm'] as bool,
        label: (m['label'] ?? '') as String,
        repeatDays:
            (m['repeatDays'] as List<dynamic>? ?? const []).map((e) => e as int).toList(),
        sunrise: (m['sunrise'] ?? false) as bool,
        enabled: (m['enabled'] ?? true) as bool,
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
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _now = DateTime.now();
      });
    });
    _loadAlarms();
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
            title: const Text('Alarm'),
            actions: [
              IconButton(icon: const Icon(Icons.add), onPressed: _addAlarm),
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
              onPressed: _addAlarm,
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
      builder: (_) => const NewAlarmSheet(),
    );

    if (alarm != null) {
      setState(() => alarms.add(alarm));
      await _saveAlarms();
    }
  }

  Widget _emptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        CircleAvatar(
          radius: 45,
          backgroundColor: Color(0xFF1C2330),
          child: Icon(Icons.notifications_none, size: 42),
        ),
        SizedBox(height: 16),
        Text('No alarms yet', style: TextStyle(fontSize: 16)),
        SizedBox(height: 6),
        Text(
          'Create your first alarm to get started',
          style: TextStyle(color: Colors.white54),
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
              color: Colors.red.withOpacity(0.15),
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
            onTap: () => _editAlarm(alarm, i),
            child: _AlarmCard(alarm: alarm),
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
      builder: (_) => EditAlarmSheet(alarm: alarm),
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
        );
      }
    }
  }

  DateTime _computeNextDateFor(Alarm alarm) {
    final now = DateTime.now();
    final hour24 = (alarm.isAm) ? (alarm.hour % 12) : ((alarm.hour % 12) + 12);
    DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day,
      hour24,
      alarm.minute,
    );

    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }

    if (alarm.repeatDays.isNotEmpty) {
      for (int i = 0; i < 7; i++) {
        final day = candidate.add(Duration(days: i));
        final wd = day.weekday; // 1..7
        if (alarm.repeatDays.contains(wd)) {
          return DateTime(day.year, day.month, day.day, hour24, alarm.minute);
        }
      }
    }

    return candidate;
  }
}

class _AlarmCard extends StatefulWidget {
  final Alarm alarm;
  const _AlarmCard({required this.alarm});

  @override
  State<_AlarmCard> createState() => _AlarmCardState();
}

class _AlarmCardState extends State<_AlarmCard> {
  late bool enabled;

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    final time =
        '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')} ${alarm.isAm ? 'AM' : 'PM'}';

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
                  style: const TextStyle(color: Colors.white54),
                ),
              const SizedBox(height: 4),
              Text(
                alarm.repeatDays.isEmpty
                    ? 'One time'
                    : _repeatText(alarm.repeatDays),
                style: const TextStyle(fontSize: 12, color: Colors.white54),
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
                );
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
    final now = DateTime.now();
    // Convert to 24h based on AM/PM
    final hour24 = (alarm.isAm) ? (alarm.hour % 12) : ((alarm.hour % 12) + 12);
    DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day,
      hour24,
      alarm.minute,
    );

    // If time today already passed, move to next day
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }

    // If repeating, find the next matching weekday (1=Mon ... 7=Sun)
    if (alarm.repeatDays.isNotEmpty) {
      for (int i = 0; i < 7; i++) {
        final day = candidate.add(Duration(days: i));
        final wd = day.weekday; // 1..7
        if (alarm.repeatDays.contains(wd)) {
          // Return the time on this matching day
          return DateTime(day.year, day.month, day.day, hour24, alarm.minute);
        }
      }
    }

    return candidate;
  }
}

class NewAlarmSheet extends StatefulWidget {
  const NewAlarmSheet({super.key});

  @override
  State<NewAlarmSheet> createState() => _NewAlarmSheetState();
}

class EditAlarmSheet extends StatefulWidget {
  final Alarm alarm;
  const EditAlarmSheet({super.key, required this.alarm});

  @override
  State<EditAlarmSheet> createState() => _EditAlarmSheetState();
}

class _EditAlarmSheetState extends State<EditAlarmSheet> {
  late int hour;
  late int minute;
  late bool isAm;
  late bool sunrise;
  late String label;
  late Set<int> repeat;

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    hour = a.hour;
    minute = a.minute;
    isAm = a.isAm;
    sunrise = a.sunrise;
    label = a.label;
    repeat = a.repeatDays.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F17),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Edit Alarm', style: TextStyle(fontSize: 18)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _timeWheel(
                  value: hour,
                  max: 12,
                  onChanged: (v) => setState(() => hour = v),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(':', style: TextStyle(fontSize: 42)),
                ),
                _timeWheel(
                  value: minute,
                  max: 59,
                  onChanged: (v) => setState(() => minute = v),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    _ampmButton('AM', isAm, () => setState(() => isAm = true)),
                    const SizedBox(height: 8),
                    _ampmButton('PM', !isAm, () => setState(() => isAm = false)),
                  ],
                ),
              ],
            ),

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
              child: Text('Repeat', style: TextStyle(color: Colors.white70)),
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
                        selected ? Colors.blue : const Color(0xFF1C2330),
                    child: Text(labels[i]),
                  ),
                );
              }),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.wb_sunny),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sunrise Alarm'),
                        Text(
                          'Gradual screen brightness',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
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

            const SizedBox(height: 28),

            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  Alarm(
                    id: widget.alarm.id,
                    hour: hour,
                    minute: minute,
                    isAm: isAm,
                    label: label,
                    repeatDays: repeat.toList(),
                    sunrise: sunrise,
                    enabled: widget.alarm.enabled,
                  ),
                );
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ampmButton(String t, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.blue : const Color(0xFF1C2330),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(t),
      ),
    );
  }

  Widget _timeWheel({
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 70,
      height: 140,
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(
          // For hours: 12 maps to index 0; minutes map directly
          initialItem: (value == max) ? 0 : value,
        ),
        itemExtent: 42,
        perspective: 0.002,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) => onChanged(i == 0 ? max : i),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: max + 1,
          builder: (_, i) => Center(
            child: Text(
              i.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 32),
            ),
          ),
        ),
      ),
    );
  }
}
class _NewAlarmSheetState extends State<NewAlarmSheet> {
  int hour = 12;
  int minute = 0;
  bool isAm = true;
  bool sunrise = false;
  String label = '';
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

  DateTime nextAlarmDate({
    required int hour,
    required int minute,
    required bool isAm,
    required List<int> repeatDays,
  }) {
    int h = hour % 12;
    if (!isAm) h += 12;

    final now = DateTime.now();
    DateTime alarm = DateTime(now.year, now.month, now.day, h, minute);

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
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F17),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header
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

            const SizedBox(height: 24),

            // Time Picker
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _timeWheel(
                  value: hour,
                  max: 12,
                  onChanged: (v) => setState(() => hour = v),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(':', style: TextStyle(fontSize: 42)),
                ),
                _timeWheel(
                  value: minute,
                  max: 59,
                  onChanged: (v) => setState(() => minute = v),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    _ampmButton('AM', isAm, () => setState(() => isAm = true)),
                    const SizedBox(height: 8),
                    _ampmButton(
                      'PM',
                      !isAm,
                      () => setState(() => isAm = false),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Label
            TextField(
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'Alarm label',
              ),
              onChanged: (v) => label = v,
            ),

            const SizedBox(height: 20),

            // Repeat
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Repeat', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final day = i + 1;
                final selected = repeat.contains(day);
                return GestureDetector(
                  onTap: () => setState(() {
                    selected ? repeat.remove(day) : repeat.add(day);
                  }),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: selected
                        ? Colors.blue
                        : const Color(0xFF1C2330),
                    child: Text(['S', 'M', 'T', 'W', 'T', 'F', 'S'][i]),
                  ),
                );
              }),
            ),

            const SizedBox(height: 20),

            // Sunrise Alarm
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.wb_sunny),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sunrise Alarm'),
                        Text(
                          'Gradual screen brightness',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
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

            const SizedBox(height: 28),

            // Save
            FilledButton(
              onPressed: () async {
                // 1️⃣ Notification permission
                final notifAllowed = await requestNotificationPermission();
                if (!notifAllowed) return;

                final alarmTime = nextAlarmDate(
                  hour: hour,
                  minute: minute,
                  isAm: isAm,
                  repeatDays: repeat.toList(),
                );

                final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

                try {
                  await AlarmIntegration.schedule(
                    id: id,
                    label: label.isEmpty ? 'Alarm' : label,
                    when: alarmTime,
                  );

                  Navigator.pop(
                    context,
                    Alarm(
                      id: id,
                      hour: hour,
                      minute: minute,
                      isAm: isAm,
                      label: label,
                      repeatDays: repeat.toList(),
                      sunrise: sunrise,
                      enabled: true,
                    ),
                  );
                } on PlatformException catch (e) {
                  if (e.code == 'exact_alarms_not_permitted') {
                    await showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Allow Exact Alarms'),
                        content: const Text(
                          'Enable "Schedule exact alarms" to allow alarms to ring on time.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Not now'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await openExactAlarmSettings();
                            },
                            child: const Text('Open Settings'),
                          ),
                        ],
                      ),
                    );
                    return; // 🔴 DO NOT CONTINUE
                  }
                  rethrow;
                }
              },

              child: const Text('Save Alarm'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ampmButton(String t, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.blue : const Color(0xFF1C2330),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(t),
      ),
    );
  }

  Widget _timeWheel({
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 70,
      height: 140,
      child: ListWheelScrollView.useDelegate(
        itemExtent: 42,
        perspective: 0.002,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) => onChanged(i == 0 ? max : i),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: max + 1,
          builder: (_, i) => Center(
            child: Text(
              i.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 32),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- TIMER ----------------
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  int totalSeconds = 0;
  int remainingSeconds = 0;
  Timer? _timer;
  bool isRunning = false;
  bool isPaused = false;

  void startTimer(int seconds) {
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
        setState(() {
          remainingSeconds = 0;
          isRunning = false;
        });
      } else {
        setState(() => remainingSeconds--);
      }
    });
  }

  void pauseResume() {
    if (isPaused) {
      startTimer(remainingSeconds);
    } else {
      _timer?.cancel();
      setState(() => isPaused = true);
    }
  }

  void resetTimer() {
    _timer?.cancel();
    setState(() {
      remainingSeconds = totalSeconds;
      isPaused = false;
    });
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
  Widget build(BuildContext context) {
    final progress = totalSeconds == 0
        ? 0.0
        : 1 - (remainingSeconds / totalSeconds);

    final minutes = (remainingSeconds ~/ 60).toString().padLeft(1, '0');
    final seconds = (remainingSeconds % 60).toString().padLeft(2, '0');

    return SafeArea(
      child: Column(
        children: [
          AppBar(title: const Text('Timer')),

          const SizedBox(height: 32),

          // ===== TIMER RING =====
          SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(280, 280),
                  painter: _TimerRingPainter(progress),
                ),
                Text(
                  '$minutes:$seconds',
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ===== CONTROLS =====
          if (!isRunning) ...[
            _presetButtons(),
            const SizedBox(height: 24),
            _manualInputRow(),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _controlIcon(icon: Icons.close, onTap: cancelTimer),
                const SizedBox(width: 24),
                TextButton.icon(
                  onPressed: pauseResume,
                  icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                  label: Text(isPaused ? 'Resume' : 'Pause'),
                ),
                const SizedBox(width: 24),
                _controlIcon(icon: Icons.refresh, onTap: resetTimer),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ===== PRESET BUTTONS =====
  Widget _presetButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _PresetButton(min: 1, onTap: () => startTimer(60)),
        _PresetButton(min: 5, onTap: () => startTimer(300)),
        _PresetButton(min: 10, onTap: () => startTimer(600)),
        _PresetButton(min: 15, onTap: () => startTimer(900)),
        _PresetButton(min: 30, onTap: () => startTimer(1800)),
        _PresetButton(min: 60, onTap: () => startTimer(3600)),
      ],
    );
  }

  // ===== MANUAL INPUT ROW =====
  Widget _manualInputRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _inputChip('Min'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(':', style: TextStyle(fontSize: 18)),
        ),
        _inputChip('Sec'),
        const SizedBox(width: 16),
        TextButton(onPressed: () => startTimer(60), child: const Text('Set')),
      ],
    );
  }

  Widget _inputChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2330),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white54)),
    );
  }

  Widget _controlIcon({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 22,
        backgroundColor: const Color(0xFF1C2330),
        child: Icon(icon, size: 20),
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
          color: const Color(0xFF1C2330),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          min == 60 ? '1 hour' : '$min min',
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  _TimerRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 12;

    final bgPaint = Paint()
      ..color = const Color(0xFF1C2330)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke;

    final fgPaint = Paint()
      ..color = const Color(0xFF00D1B2)
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

  @override
  Widget build(BuildContext context) {
    final elapsed = _stopwatch.elapsed;

    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (elapsed.inMilliseconds % 1000 ~/ 10).toString().padLeft(
      2,
      '0',
    );

    final isRunning = _stopwatch.isRunning;

    return SafeArea(
      child: Column(
        children: [
          AppBar(title: const Text('Stopwatch')),

          const Spacer(),

          // ===== TIME =====
          Text(
            '$minutes:$seconds.$millis',
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w300,
              letterSpacing: 1,
            ),
          ),

          const SizedBox(height: 32),

          // ===== CONTROLS =====
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Lap icon (future use)
              IconButton(
                icon: const Icon(Icons.flag_outlined),
                iconSize: 22,
                onPressed: _lap,
              ),

              const SizedBox(width: 16),

              // Stop / Start button
              SizedBox(
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: isRunning ? _stop : _start,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRunning
                        ? const Color(0xFFD8433A)
                        : Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                  ),
                  icon: Icon(
                    isRunning ? Icons.pause : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(
                    isRunning ? 'Stop' : 'Start',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Reset
              if (!_stopwatch.isRunning && elapsed.inMilliseconds > 0)
                IconButton(icon: const Icon(Icons.refresh), onPressed: _reset),
            ],
          ),

          const Spacer(),
          if (_laps.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _laps.length,
                itemBuilder: (context, index) {
                  final lapTime = _laps[index];
                  final lapNumber = _laps.length - index;

                  final fastest =
                      lapTime == _laps.reduce((a, b) => a < b ? a : b);
                  final slowest =
                      lapTime == _laps.reduce((a, b) => a > b ? a : b);

                  Color color = Colors.white;
                  if (fastest) color = Colors.greenAccent;
                  if (slowest) color = Colors.redAccent;

                  String format(Duration d) {
                    final m = d.inMinutes.toString().padLeft(2, '0');
                    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
                    final ms = (d.inMilliseconds % 1000 ~/ 10)
                        .toString()
                        .padLeft(2, '0');
                    return '$m:$s.$ms';
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lap $lapNumber',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        Text(
                          format(lapTime),
                          style: TextStyle(fontSize: 16, color: color),
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

// ---------------- WORLD ----------------
class WorldCity {
  final String name;
  final int offsetHours;

  WorldCity(this.name, this.offsetHours);
}

class WorldClockScreen extends StatefulWidget {
  final bool is24h;
  const WorldClockScreen({super.key, required this.is24h});

  @override
  State<WorldClockScreen> createState() => _WorldClockScreenState();
}

class _WorldClockScreenState extends State<WorldClockScreen> {
  final List<WorldCity> cities = [
    WorldCity('New York', -5),
    WorldCity('London', 0),
  ];

  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat(widget.is24h ? 'HH:mm' : 'h:mm a');
    final localNow = _now;
    final localUtc = _now.toUtc();

    return SafeArea(
      child: Column(
        children: [
          AppBar(
            title: const Text('World Clock'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () async {
                  final city = await showModalBottomSheet<WorldCity>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => AddCitySheet(
                      existing: cities.map((e) => e.name).toList(),
                    ),
                  );
                  if (city != null) {
                    setState(() => cities.add(city));
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          const Text('Local Time', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 4),
          Text(
            fmt.format(localNow),
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 4),
          const Text('Asia/Calcutta', style: TextStyle(color: Colors.white38)),

          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              children: cities.map((city) {
                final cityTime = localUtc.add(
                  Duration(hours: city.offsetHours),
                );
                final isDay = cityTime.hour >= 6 && cityTime.hour < 18;

                return _WorldCityCard(
                  city: city,
                  time: fmt.format(cityTime),
                  offset:
                      '${city.offsetHours >= 0 ? '+' : ''}${city.offsetHours}h',
                  isDay: isDay,
                  onDelete: () => setState(() => cities.remove(city)),
                );
              }).toList(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () async {
                final city = await showModalBottomSheet<WorldCity>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => AddCitySheet(
                    existing: cities.map((e) => e.name).toList(),
                  ),
                );
                if (city != null) {
                  setState(() => cities.add(city));
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
                Text(offset, style: const TextStyle(color: Colors.white54)),
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

  final allCities = [
    WorldCity('New York', -5),
    WorldCity('Los Angeles', -8),
    WorldCity('London', 0),
    WorldCity('Paris', 1),
    WorldCity('Berlin', 1),
    WorldCity('Dubai', 4),
    WorldCity('Tokyo', 9),
    WorldCity('Sydney', 10),
    WorldCity('Singapore', 8),
    WorldCity('Toronto', -5),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = allCities
        .where(
          (c) =>
              c.name.toLowerCase().contains(query.toLowerCase()) &&
              !widget.existing.contains(c.name),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F17),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Add City', style: TextStyle(fontSize: 18)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 12),

          TextField(
            decoration: const InputDecoration(
              hintText: 'Search cities...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              children: filtered.map((c) {
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(c.name),
                  subtitle: Text(
                    'UTC${c.offsetHours >= 0 ? '+' : ''}${c.offsetHours}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => Navigator.pop(context, c),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- SETTINGS ----------------
class SettingsScreen extends StatefulWidget {
  final bool is24h;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<bool> on24h;

  const SettingsScreen({
    super.key,
    required this.is24h,
    required this.mode,
    required this.onTheme,
    required this.on24h,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int snoozeMinutes = 5;
  int sunriseMinutes = 15;
  bool haptics = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 8),
          const Text('Settings', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 24),

          // ===== APPEARANCE =====
          const _SectionTitle('Appearance'),
          _card(
            child: Column(
              children: [
                _radioRow(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Light',
                  selected: widget.mode == ThemeMode.light,
                  onTap: () => widget.onTheme(ThemeMode.light),
                ),
                _divider(),
                _radioRow(
                  icon: Icons.nights_stay_outlined,
                  title: 'Dark',
                  selected: widget.mode == ThemeMode.dark,
                  onTap: () => widget.onTheme(ThemeMode.dark),
                ),
                _divider(),
                _radioRow(
                  icon: Icons.phone_android_outlined,
                  title: 'System',
                  selected: widget.mode == ThemeMode.system,
                  onTap: () => widget.onTheme(ThemeMode.system),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ===== TIME FORMAT =====
          const _SectionTitle('Time Format'),
          _card(
            child: Column(
              children: [
                _radioRow(
                  icon: Icons.access_time,
                  title: '12-hour',
                  subtitle: '7:30 AM',
                  selected: !widget.is24h,
                  onTap: () => widget.on24h(false),
                ),
                _divider(),
                _radioRow(
                  icon: Icons.access_time,
                  title: '24-hour',
                  subtitle: '19:30',
                  selected: widget.is24h,
                  onTap: () => widget.on24h(true),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ===== DEFAULTS =====
          const _SectionTitle('Defaults'),
          _card(
            child: Column(
              children: [
                _dropdownRow(
                  icon: Icons.snooze,
                  title: 'Default Snooze',
                  subtitle: 'Duration for snooze',
                  value: snoozeMinutes,
                  items: const [5, 10, 15],
                  suffix: 'min',
                  onChanged: (v) => setState(() => snoozeMinutes = v),
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
          _card(
            child: SwitchListTile(
              value: haptics,
              onChanged: (v) => setState(() => haptics = v),
              secondary: const Icon(Icons.vibration),
              title: const Text('Haptic Feedback'),
              subtitle: const Text('Vibration on interactions'),
            ),
          ),

          const SizedBox(height: 40),

          // ===== FOOTER =====
          Column(
            children: const [
              Icon(Icons.wb_sunny, color: Colors.orange, size: 32),
              SizedBox(height: 8),
              Text('Serenity', style: TextStyle(fontSize: 16)),
              SizedBox(height: 4),
              Text('Version 1.0.0', style: TextStyle(color: Colors.white54)),
              SizedBox(height: 6),
              Text(
                'A calm, reliable alarm companion',
                style: TextStyle(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ===== HELPERS =====

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  Widget _divider() {
    return const Divider(height: 1, color: Colors.white12);
  }

  Widget _radioRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: selected ? Colors.blue : Colors.white54),
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
        style: const TextStyle(color: Colors.white54, fontSize: 14),
      ),
    );
  }
}

class RingingScreen extends StatelessWidget {
  final int alarmId;
  final String label;
  const RingingScreen({super.key, required this.alarmId, required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_alarm, size: 72),
              const SizedBox(height: 16),
              Text(label.isEmpty ? 'Alarm' : label, style: Theme.of(context).textTheme.displayLarge, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () async {
                      try { await AlarmIntegration.cancel(alarmId); } catch (_) {}
                      try {
                        await const MethodChannel('serenity/alarm_manager').invokeMethod('stopRinging', {
                          'id': alarmId,
                        });
                        await const MethodChannel('serenity/alarm_manager').invokeMethod('finishActivity');
                      } catch (_) {}
                      // Mark the alarm disabled in persisted list
                      try {
                        final p = await SharedPreferences.getInstance();
                        final s = p.getString('alarms') ?? '[]';
                        final arr = (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e)).toList();
                        for (final e in arr) {
                          if ((e['id'] as num?)?.toInt() == alarmId) {
                            e['enabled'] = false;
                          }
                        }
                        await p.setString('alarms', jsonEncode(arr));
                      } catch (_) {}
                      navigatorKey.currentState?.popUntil((r) => r.isFirst);
                    },
                    child: const Text('Stop'),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        await const MethodChannel('serenity/alarm_manager').invokeMethod('stopRinging', {
                          'id': alarmId,
                        });
                        await const MethodChannel('serenity/alarm_manager').invokeMethod('finishActivity');
                      } catch (_) {}
                      final now = DateTime.now().add(const Duration(minutes: 5));
                      await AlarmIntegration.schedule(id: DateTime.now().millisecondsSinceEpoch ~/ 1000, label: label, when: now);
                      // Also mark the current alarm disabled so it doesn't re-ring
                      try {
                        final p = await SharedPreferences.getInstance();
                        final s = p.getString('alarms') ?? '[]';
                        final arr = (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e)).toList();
                        for (final e in arr) {
                          if ((e['id'] as num?)?.toInt() == alarmId) {
                            e['enabled'] = false;
                          }
                        }
                        await p.setString('alarms', jsonEncode(arr));
                      } catch (_) {}
                      navigatorKey.currentState?.popUntil((r) => r.isFirst);
                    },
                    child: const Text('Snooze 5 min'),
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