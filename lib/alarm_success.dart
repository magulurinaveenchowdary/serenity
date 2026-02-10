import 'dart:async';
import 'package:flutter/material.dart';
import 'ad_provider.dart';

class AlarmSuccessScreen extends StatefulWidget {
  final String label;
  const AlarmSuccessScreen({super.key, required this.label});

  @override
  State<AlarmSuccessScreen> createState() => _AlarmSuccessScreenState();
}

class _AlarmSuccessScreenState extends State<AlarmSuccessScreen>
    with SingleTickerProviderStateMixin {
  DateTime _now = DateTime.now();
  Timer? _timer;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return PopScope(
      canPop: true,
      child: Scaffold(
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_controller.value);
              final bg1 = Color.lerp(const Color(0xFF2B1608), const Color(0xFFFFB199), t)!;
              final bg2 = Color.lerp(const Color(0xFF2B1608), const Color(0xFFFFF3B0), t)!;
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [bg1, bg2],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.9, end: 1.0)
                          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)),
                      child: const Icon(Icons.check_circle, color: Color(0xFF4C8DFF), size: 84),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Alarm dismissed',
                      style: TextStyle(color: Colors.black87, fontSize: 24, fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.label.isEmpty ? 'Alarm' : widget.label,
                      style: const TextStyle(color: Colors.black54, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '$hh:$mm',
                      style: const TextStyle(color: Colors.black87, fontSize: 56, fontWeight: FontWeight.w300),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Have a calm day',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const BannerAdWidget(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
