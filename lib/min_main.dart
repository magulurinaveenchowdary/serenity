import 'package:flutter/material.dart';
import 'alarm_integration.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SerenityApp());
}

class SerenityApp extends StatelessWidget {
  const SerenityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gentle Wake Alarm Clock Timer',
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = 'Ready';

  Future<void> _scheduleTest() async {
    final when = DateTime.now().add(const Duration(seconds: 15));
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    setState(() => _status = 'Scheduling alarm for ${when.toLocal()}');
    try {
      await AlarmIntegration.schedule(
        id: id,
        label: 'Test Alarm',
        when: when,
      );
      if (mounted) setState(() => _status = 'Scheduled (id=$id)');
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('Gentle Wake Alarm Clock Timer — Alarm Demo')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_status),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _scheduleTest,
                icon: const Icon(Icons.alarm_add),
                label: const Text('Schedule test alarm (+15s)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
