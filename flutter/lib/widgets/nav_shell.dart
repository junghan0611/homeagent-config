import 'package:flutter/material.dart';

import '../screens/dashboard_screen.dart';
import '../screens/settings_screen.dart';

/// 하단 네비게이션 셸 — 대시보드 / 설정
class NavShell extends StatefulWidget {
  final String serverUrl;
  const NavShell({super.key, required this.serverUrl});

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(serverUrl: widget.serverUrl),
          SettingsScreen(serverUrl: widget.serverUrl),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        height: 64,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '대시보드',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
