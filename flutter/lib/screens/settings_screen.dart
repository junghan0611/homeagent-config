import 'package:flutter/material.dart';

/// 설정 화면 — placeholder
class SettingsScreen extends StatelessWidget {
  final String serverUrl;
  const SettingsScreen({super.key, required this.serverUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('서버 주소'),
            subtitle: Text(serverUrl),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('버전'),
            subtitle: const Text('0.1.0'),
          ),
        ],
      ),
    );
  }
}
