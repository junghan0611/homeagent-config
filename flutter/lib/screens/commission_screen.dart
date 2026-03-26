import 'dart:io';

import 'package:flutter/material.dart';

import '../ble_commissioning.dart';
import '../chip_commissioning.dart';
import '../theme.dart';

/// 커미셔닝 화면 — 플랫폼별 + 백엔드별 분기
///
/// Android + CHIP SDK AAR: ChipCommissioningScreen (BLE → multi-admin handoff)
/// Android + matterjs:     BleCommissioningScreen (BLE WS relay)
/// Linux:                  On-network 커미셔닝 (Go REST)
///
/// 아키텍처 결정 (2026-03-20):
/// APP → Go REST → matter-server (단일 경로). WS 직접 연결은 하지 않음.
/// Go 서버가 상태 관리 + aliases + SSE 변환을 전담.
class CommissionScreen extends StatelessWidget {
  final String serverUrl;

  const CommissionScreen({
    super.key,
    required this.serverUrl,
  });

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
            Icon(Icons.add_link, size: 64, color: AppTheme.orange.withAlpha(180)),
            const SizedBox(height: 24),
            Text(
              '디바이스를 페어링 모드로 설정한 후\n아래 버튼을 눌러 추가하세요.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isAndroid
                  ? 'WiFi 디바이스와 Thread 디바이스 모두 지원합니다.'
                  : 'Linux에서는 네트워크 커미셔닝만 지원합니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            if (Platform.isAndroid) ...[
              // Android: BLE 커미셔닝
              // CHIP SDK AAR 경로 (python-matter-server + multi-admin)
              FilledButton.icon(
                icon: const Icon(Icons.bluetooth_searching, size: 24),
                label: const Text('BLE 디바이스 페어링', style: TextStyle(fontSize: 16)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChipCommissioningScreen(serverUrl: serverUrl),
                  ),
                ),
              ),

            ],

            // 모든 플랫폼: On-network 커미셔닝 (setup code)
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.lan, size: 24),
              label: Text(
                Platform.isAndroid ? '네트워크 커미셔닝' : '디바이스 페어링',
                style: const TextStyle(fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => _showNetworkCommissionDialog(context),
            ),

            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  void _showNetworkCommissionDialog(BuildContext context) {
    final codeController = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('네트워크 커미셔닝'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'QR코드의 Setup Code 또는 Manual Pairing Code를 입력하세요.\n'
                'BLE 없이 IP 네트워크로 직접 페어링합니다.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Setup Code',
                  hintText: '숫자만 입력 (예: 05641540754)',
                ),
                enabled: !loading,
              ),
              if (loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('커미셔닝 진행 중... (최대 3분)', style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final code = codeController.text.replaceAll('-', '').trim();
                      if (code.isEmpty) return;

                      setDialogState(() => loading = true);

                      try {
                        // Go REST → matterjs (단일 경로)
                        final client = HttpClient();
                        final request = await client.postUrl(
                          Uri.parse('$serverUrl/api/commission'),
                        );
                        request.headers.contentType = ContentType.json;
                        request.write('{"code":"$code","network_only":true}');
                        final response = await request.close();
                        await response.drain();
                        client.close();

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('디바이스 페어링 성공!')),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => loading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('페어링 실패: $e')),
                          );
                        }
                      }
                    },
              child: const Text('시작'),
            ),
          ],
        ),
      ),
    );
  }
}
