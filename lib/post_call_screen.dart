import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'ad_provider.dart';

class PostCallScreen extends StatefulWidget {
  final String? phoneNumber;
  final String? contactName;
  final String? callDuration;

  const PostCallScreen({
    super.key,
    this.phoneNumber,
    this.contactName,
    this.callDuration,
  });

  @override
  State<PostCallScreen> createState() => _PostCallScreenState();
}

class _PostCallScreenState extends State<PostCallScreen> {
  int _tabIndex = 0;
  String? _selectedMessage;
  bool _isCustomMessage = false;
  final TextEditingController _customMessageController = TextEditingController();

  @override
  void dispose() {
    _customMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: Column(
          children: [
            _buildCallHeader(),
            _buildTabs(),
            Expanded(
              child: _buildTabContent(),
            ),
            const BannerAdWidget(size: AdSize.mediumRectangle),
          ],
        ),
      ),
    );
  }

  Widget _buildCallHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => SystemNavigator.pop(),
              ),
            ),
            Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  shape: BoxShape.circle,
                  image: const DecorationImage(
                    image: AssetImage('assets/Frame 12809.png'), // App Logo
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.contactName ?? widget.phoneNumber ?? 'Unknown',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          DateFormat('HH:mm').format(DateTime.now()),
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.grey[400], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.callDuration != null ? 'Duration: ${widget.callDuration}' : 'No answer',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.call, color: Colors.green),
                onPressed: () async {
                   final Uri launchUri = Uri(
                     scheme: 'tel',
                     path: widget.phoneNumber ?? '',
                   );
                   try {
                     await launchUrl(launchUri);
                   } catch (_) {}
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF1C2331),
        borderRadius: BorderRadius.circular(0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _tabIcon(Icons.list, 0),
          _tabIcon(Icons.message, 1),
          _tabIcon(Icons.notifications, 2),
          _tabIcon(Icons.more_horiz, 3),
        ],
      ),
    );
  }

  Widget _tabIcon(IconData icon, int index) {
    final selected = _tabIndex == index;
    return InkWell(
      onTap: () => setState(() => _tabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey[400]),
            if (selected)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 20,
                height: 2,
                color: Colors.white,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildMessageTab();
      case 2:
        return _buildAlarmTab();
      default:
        return _buildActionList();
    }
  }

  Widget _buildDashboardTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Dark Header Card
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1713), // Dark brownish black
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _dashboardItem("Alarm", Icons.alarm, () => _launchApp()),
                _dashboardItem("Reminder", Icons.notifications_active_outlined, () => _launchApp()),
                _dashboardItem("Bedtime", Icons.nightlight_round, () => _launchApp()),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Greeting Card
          _buildGreetingCard(),
        ],
      ),
    );
  }

  Widget _dashboardItem(String label, IconData icon, VoidCallback onTap) {
    const color = Color(0xFFE6CCA0); // Goldish beige
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildGreetingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
             color: Colors.black.withOpacity(0.05),
             blurRadius: 10,
             offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.wb_sunny_outlined, size: 40, color: Colors.black87),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGreeting(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Today, the sun rises at 06:56 and sets at 17:56", 
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning!';
    if (hour < 17) return 'Good afternoon!';
    if (hour < 21) return 'Good evening!';
    return 'Good night!';
  }

  Future<void> _launchApp() async {
     try {
       const intent = AndroidIntent(
         action: 'android.intent.action.MAIN',
         category: 'android.intent.category.LAUNCHER',
         package: 'com.serenity.sunrise',
         flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
       );
       await intent.launch();
     } catch (_) {}
  }

  Widget _buildActionList() {
    // Basic logic: if contactName is missing or same as phone, assume it's new
    final isNewNumber = (widget.contactName == null || widget.contactName == widget.phoneNumber);
    
    final actions = [
      if (isNewNumber)
        {'icon': Icons.person_add, 'label': 'Add caller to your contacts', 'type': 'contact'},
      {'icon': Icons.chat_bubble_outline, 'label': 'Messages', 'type': 'sms'},
      {'icon': Icons.mail_outline, 'label': 'Send Mail', 'type': 'email'},
      {'icon': Icons.calendar_today_outlined, 'label': 'Calendar', 'type': 'calendar'},
      {'icon': Icons.public, 'label': 'Web', 'type': 'web'},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2F3C),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: Icon(action['icon'] as IconData, color: Colors.white),
            title: Text(action['label'] as String, style: const TextStyle(color: Colors.white)),
            onTap: () async {
               final type = action['type'];
               if (type == 'contact') {
                 // Open contacts app to add new contact
                 // Using intent to insert
                 try {
                   final intent = AndroidIntent(
                     action: 'android.intent.action.INSERT',
                     type: 'vnd.android.cursor.dir/contact',
                     arguments: <String, dynamic>{
                        'phone': widget.phoneNumber ?? '',
                     },
                   );
                   await intent.launch();
                 } catch (_) {}
               } else if (type == 'sms') {
                 final Uri smsLaunchUri = Uri(
                  scheme: 'sms',
                  path: widget.phoneNumber ?? '',
                );
                try { await launchUrl(smsLaunchUri); } catch (_) {}
               } else if (type == 'email') {
                  final Uri emailLaunchUri = Uri(
                    scheme: 'mailto',
                    path: '',
                  );
                  try { await launchUrl(emailLaunchUri); } catch (_) {}
               } else if (type == 'calendar') {
                  // Open calendar app
                  try {
                     // Generic intent to open calendar
                     final intent = AndroidIntent(
                        action: 'android.intent.action.MAIN',
                        category: 'android.intent.category.APP_CALENDAR',
                     );
                     await intent.launch();
                  } catch (_) {
                     // Fallback if category not supported
                     try {
                        const intent = AndroidIntent(
                           action: 'android.intent.action.VIEW',
                           data: 'content://com.android.calendar/time/',
                        );
                        await intent.launch();
                     } catch (_) {}
                  }
               } else if (type == 'web') {
                  final Uri webUri = Uri.parse("https://google.com");
                  try { await launchUrl(webUri, mode: LaunchMode.externalApplication); } catch (_) {}
               }
            },
          ),
        );
      },
    );
  }

  Widget _buildMessageTab() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _selectableMsgItem("Sorry, I can't talk right now"),
              _selectableMsgItem("Can I call you later?"),
              _selectableMsgItem("I'm on my way"),
              _customMsgItem(),
            ],
          ),
        ),
        if (_selectedMessage != null || _isCustomMessage)
          Container(
             padding: const EdgeInsets.all(16),
             color: Colors.white,
             child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4C8DFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _sendSMS,
                child: const Text("Send Message", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _selectableMsgItem(String text) {
    bool isSelected = _selectedMessage == text && !_isCustomMessage;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedMessage = text;
          _isCustomMessage = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F0FE) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: const Color(0xFF4C8DFF)) : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF4C8DFF) : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(text, style: const TextStyle(fontSize: 16, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _customMsgItem() {
    return InkWell(
      onTap: () {
        setState(() {
          _isCustomMessage = true;
          _selectedMessage = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
           color: _isCustomMessage ? const Color(0xFFE8F0FE) : Colors.white,
           borderRadius: BorderRadius.circular(8),
           border: _isCustomMessage ? Border.all(color: const Color(0xFF4C8DFF)) : Border.all(color: Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
              children: [
                Icon(
                  _isCustomMessage ? Icons.radio_button_checked : Icons.radio_button_off, 
                  color: _isCustomMessage ? const Color(0xFF4C8DFF) : Colors.grey,
                  size: 20
                ),
                const SizedBox(width: 16),
                const Text("Write personal message", style: TextStyle(fontSize: 16, color: Colors.black87)),
              ],
            ),
            if (_isCustomMessage)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _customMessageController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: "Type your message...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  maxLines: 3,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendSMS() async {
    final message = _isCustomMessage ? _customMessageController.text : (_selectedMessage ?? "");
    if (message.trim().isEmpty) return;
    
    final Uri smsLaunchUri = Uri(
      scheme: 'sms',
      path: widget.phoneNumber ?? '',
      queryParameters: <String, String>{
        'body': message,
      },
    );
    try {
      await launchUrl(smsLaunchUri);
    } catch (_) {}
  }

  Widget _buildAlarmTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1C2331),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _launchApp,
            child: const Text('Create new reminder', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 20),
          _reminderItem("No title", "13:20", "Today"),
        ],
      ),
    );
  }

  Widget _reminderItem(String title, String time, String date) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 12, color: Colors.blue),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(time, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    const SizedBox(width: 16),
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(date, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.delete_outline, color: Colors.grey[400]),
        ],
      ),
    );
  }
}
