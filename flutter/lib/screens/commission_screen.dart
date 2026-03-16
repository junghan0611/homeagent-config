import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../ble_commissioning.dart';
import '../theme.dart';

/// 커미셔닝 화면 — WiFi/Thread 모드 선택 + BLE relay 통합
///
/// 기존 ble_commissioning.dart를 네이티브 앱 네비게이션에 통합.
/// WiFi 커미셔닝: BLE relay + /api/commission
/// Thread on-network: /api/commission-on-network (BLE 불필요)
class CommissionScreen extends StatefulWidget {
  final String serverUrl;
  const CommissionScreen({super.key, required this.serverUrl});

  @override
  State<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends State<CommissionScreen> {
  late final ApiClient _api;
  StreamSubscription<SseEvent>? _sseSub;
  bool _commissioning = false;
  String? _resultMessage;
  bool _resultSuccess = false;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: widget.serverUrl);
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  /// WiFi BLE 커미셔닝 — 기존 BleCommissioningScreen으로 이동
  void _startWifiBleCommissioning() {
    if (!Platform.isAndroid) {
      _showMessage('BLE 커미셔닝은 Android에서만 가능합니다.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BleCommissioningScreen(serverUrl: widget.serverUrl),
      ),
    );
  }

  /// Thread on-network 커미셔닝 — PIN 입력 → API 호출
  Future<void> _startThreadCommissioning() async {
    final info = await _showThreadDialog();
    if (info == null) return;

    setState(() {
      _commissioning = true;
      _resultMessage = null;
    });

    // SSE 구독으로 결과 추적
    _listenForResult();

    try {
      await _api.commissionOnNetwork(
        info.pinCode,
        ipAddr: info.ipAddr.isNotEmpty ? info.ipAddr : null,
      );
    } catch (e) {
      setState(() {
        _commissioning = false;
        _resultMessage = '요청 실패: $e';
        _resultSuccess = false;
      });
    }
  }

  /// Pairing Code로 BLE 커미셔닝 (Thread 디바이스)
  Future<void> _startCodeCommissioning() async {
    final code = await _showCodeDialog();
    if (code == null || code.isEmpty) return;

    setState(() {
      _commissioning = true;
      _resultMessage = null;
    });

    _listenForResult();

    try {
      // network_only=false → BLE relay 사용
      await _api.commission(code, networkOnly: false);
    } catch (e) {
      setState(() {
        _commissioning = false;
        _resultMessage = '요청 실패: $e';
        _resultSuccess = false;
      });
    }
  }

  void _listenForResult() {
    _sseSub?.cancel();
    _sseSub = _api.eventStream().listen((event) {
      if (event.type == 'device_added') {
        setState(() {
          _commissioning = false;
          _resultMessage = '✅ 디바이스가 추가되었습니다!';
          _resultSuccess = true;
        });
        _sseSub?.cancel();
      } else if (event.type == 'commission_error') {
        setState(() {
          _commissioning = false;
          _resultMessage = '❌ 커미셔닝 실패: ${event.value ?? "알 수 없는 오류"}';
          _resultSuccess = false;
        });
        _sseSub?.cancel();
      }
    });

    // 3분 타임아웃
    Future.delayed(const Duration(minutes: 3), () {
      if (_commissioning && mounted) {
        setState(() {
          _commissioning = false;
          _resultMessage = '⏰ 시간 초과 — 디바이스가 페어링 모드인지 확인하세요';
          _resultSuccess = false;
        });
        _sseSub?.cancel();
      }
    });
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<({int pinCode, String ipAddr})?> _showThreadDialog() {
    final pinController = TextEditingController();
    final ipController = TextEditingController();

    return showDialog<({int pinCode, String ipAddr})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thread On-Network 커미셔닝'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinController,
              decoration: const InputDecoration(
                labelText: 'Setup PIN Code',
                hintText: '예: 56204424',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'IPv6 주소 (선택)',
                hintText: 'fd9c:5a4a:... (비우면 mDNS 탐색)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final pin = int.tryParse(pinController.text.trim());
              if (pin != null) {
                Navigator.pop(ctx, (
                  pinCode: pin,
                  ipAddr: ipController.text.trim(),
                ));
              }
            },
            child: const Text('시작'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showCodeDialog() {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('BLE 커미셔닝'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Pairing Code',
            hintText: '0073-043-4300 또는 MT:...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final code =
                  controller.text.replaceAll(' ', '').replaceAll('-', '');
              if (code.isNotEmpty) Navigator.pop(ctx, code);
            },
            child: const Text('시작'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('디바이스 추가')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 결과 배너
          if (_commissioning || _resultMessage != null)
            Card(
              color: _commissioning
                  ? Theme.of(context).colorScheme.primaryContainer
                  : _resultSuccess
                      ? AppTheme.green.withAlpha(30)
                      : AppTheme.errorColor.withAlpha(30),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (_commissioning)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _resultSuccess ? Icons.check_circle : Icons.error,
                        color: _resultSuccess
                            ? AppTheme.green
                            : AppTheme.errorColor,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _commissioning
                            ? '커미셔닝 진행 중... (최대 3분)'
                            : _resultMessage ?? '',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_commissioning || _resultMessage != null)
            const SizedBox(height: 16),

          // WiFi 디바이스 (BLE 커미셔닝)
          _CommissionOption(
            icon: Icons.wifi,
            color: AppTheme.blue,
            title: 'WiFi 디바이스',
            subtitle: 'BLE로 WiFi 정보 전달 후 페어링',
            detail: 'WiFi 스마트 플러그, 전구 등',
            enabled: !_commissioning && Platform.isAndroid,
            onTap: _startWifiBleCommissioning,
          ),
          const SizedBox(height: 12),

          // Thread 디바이스 (BLE 커미셔닝)
          _CommissionOption(
            icon: Icons.bluetooth,
            color: AppTheme.orange,
            title: 'Thread 디바이스 (BLE)',
            subtitle: 'BLE로 Thread 네트워크 정보 전달 후 페어링',
            detail: '도어센서, 온습도 센서 등',
            enabled: !_commissioning && Platform.isAndroid,
            onTap: _startCodeCommissioning,
          ),
          const SizedBox(height: 12),

          // Thread on-network (BLE 우회)
          _CommissionOption(
            icon: Icons.lan,
            color: AppTheme.green,
            title: 'Thread On-Network',
            subtitle: '이미 Thread에 합류한 디바이스를 PIN으로 추가',
            detail: 'BLE 없이 직접 연결 (mDNS 또는 IP 지정)',
            enabled: !_commissioning,
            onTap: _startThreadCommissioning,
          ),
        ],
      ),
    );
  }
}

class _CommissionOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String detail;
  final bool enabled;
  final VoidCallback? onTap;

  const _CommissionOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            const SizedBox(height: 4),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(128),
                  ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        enabled: enabled,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
