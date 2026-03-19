import 'dart:io';

import 'package:flutter/material.dart';

import '../ble_commissioning.dart';
import '../theme.dart';

/// 커미셔닝 화면 — 단일 페어링 버튼
/// WiFi/Thread 선택은 BleCommissioningScreen 다이얼로그에서 처리
class CommissionScreen extends StatelessWidget {
  final String serverUrl;
  const CommissionScreen({super.key, required this.serverUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('디바이스 추가')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            // 안내
            Icon(Icons.add_link, size: 64, color: AppTheme.orange.withAlpha(180)),
            const SizedBox(height: 24),
            Text(
              '디바이스를 페어링 모드로 설정한 후\n아래 버튼을 눌러 추가하세요.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'WiFi 디바이스와 Thread 디바이스 모두 지원합니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // 메인 버튼
            FilledButton.icon(
              icon: const Icon(Icons.bluetooth_searching, size: 24),
              label: const Text('디바이스 페어링', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: Platform.isAndroid
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BleCommissioningScreen(serverUrl: serverUrl),
                        ),
                      )
                  : null,
            ),

            if (!Platform.isAndroid) ...[
              const SizedBox(height: 12),
              Text(
                'BLE 커미셔닝은 Android에서만 가능합니다.\nLinux에서는 WebView 모드를 사용하세요.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],

            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
