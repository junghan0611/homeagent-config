import 'package:flutter/material.dart';

import '../main.dart';
import 'a2ui_test_screen.dart';

/// 설정 화면 — 테마 전환 + 서버 정보
class SettingsScreen extends StatelessWidget {
  final String serverUrl;
  const SettingsScreen({super.key, required this.serverUrl});

  @override
  Widget build(BuildContext context) {
    final appState = HomeAgentApp.of(context);
    final currentMode = appState?.themeMode ?? ThemeMode.light;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          // 테마 설정
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '화면 테마',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('라이트'),
            subtitle: const Text('밝은 배경 (기본)'),
            secondary: const Icon(Icons.light_mode),
            value: ThemeMode.light,
            groupValue: currentMode,
            onChanged: (v) => appState?.setThemeMode(v!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('다크'),
            subtitle: const Text('어두운 배경'),
            secondary: const Icon(Icons.dark_mode),
            value: ThemeMode.dark,
            groupValue: currentMode,
            onChanged: (v) => appState?.setThemeMode(v!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('시스템 설정 따르기'),
            subtitle: const Text('기기 설정에 맞춤'),
            secondary: const Icon(Icons.settings_brightness),
            value: ThemeMode.system,
            groupValue: currentMode,
            onChanged: (v) => appState?.setThemeMode(v!),
          ),

          const Divider(),

          // 개발자 도구
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '개발자',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.science),
            title: const Text('A2UI 테스트'),
            subtitle: const Text('genui Surface 렌더링 검증'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => A2uiTestScreen(serverUrl: serverUrl),
              ),
            ),
          ),

          const Divider(),

          // 서버 정보
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '연결 정보',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('서버 주소'),
            subtitle: Text(serverUrl),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('버전'),
            subtitle: Text('0.1.0'),
          ),
        ],
      ),
    );
  }
}
