/// Matter BLE 커미셔닝 화면 — Plan B
///
/// BLE 스캔 UI + BLE relay를 통한 matterjs 커미셔닝.
/// 프로토콜(BTP/PASE/WiFi/CASE)은 matterjs-server가 전부 처리.
/// Flutter는 BLE 바이트를 WS로 중계만 한다.
///
/// 흐름:
/// 1. BLE relay 시작 (matterjs-server :5581 연결)
/// 2. 사용자가 WiFi credentials 입력
/// 3. Go 서버에 commission 요청 (network_only=false)
/// 4. matterjs가 BLE scan/connect/BTP/PASE/WiFi/CASE 전부 수행
/// 5. Flutter는 BLE 바이트 relay만 담당
library;

import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io';
import 'package:flutter/material.dart';

import 'ble_relay.dart';

/// BLE 커미셔닝 화면
class BleCommissioningScreen extends StatefulWidget {
  final String serverUrl;
  const BleCommissioningScreen({super.key, required this.serverUrl});

  @override
  State<BleCommissioningScreen> createState() => _BleCommissioningScreenState();
}

class _BleCommissioningScreenState extends State<BleCommissioningScreen> {
  String _status = 'BLE relay 대기 중';
  bool _commissioning = false;
  BleRelay? _relay;

  @override
  void initState() {
    super.initState();
    _startRelay();
  }

  @override
  void dispose() {
    _relay?.disconnect();
    super.dispose();
  }

  /// BLE relay 시작 — matterjs-server의 BLE WS에 연결
  Future<void> _startRelay() async {
    // serverUrl에서 호스트 추출 → BLE WS 포트로 연결
    final serverUri = Uri.parse(widget.serverUrl);
    final bleWsUrl = 'ws://${serverUri.host}:5581';

    _relay = BleRelay(
      wsUrl: bleWsUrl,
      onStatus: (status) {
        if (mounted) setState(() => _status = status);
      },
    );

    try {
      await _relay!.connect();
      setState(() => _status = 'BLE relay 연결됨 — 커미셔닝 준비');
    } catch (e) {
      setState(() => _status = 'BLE relay 연결 실패: $e');
    }
  }

  /// 커미셔닝 시작 — WiFi + pairing code 입력 → Go 서버 요청
  Future<void> _startCommissioning() async {
    // 1. WiFi + Pairing code 입력
    final info = await _showCommissionDialog();
    if (info == null) return;

    setState(() {
      _commissioning = true;
      _status = '커미셔닝 시작...';
    });

    try {
      // 2. WiFi credentials를 Go 서버에 설정
      await _setWifiCredentials(info.ssid, info.password);

      // 3. Commission 요청 (network_only=false → matterjs가 BLE 커미셔닝)
      await _requestCommission(info.pairingCode);

      setState(() => _status = '⏳ 커미셔닝 진행 중...');

      // SSE로 커미셔닝 결과 추적
      _listenCommissionResult(info.pairingCode, info.ssid);
    } catch (e) {
      setState(() => _status = '❌ 커미셔닝 실패: $e');
    } finally {
      setState(() => _commissioning = false);
    }
  }

  /// SSE로 커미셔닝 결과 추적
  void _listenCommissionResult(String code, String ssid) {
    final client = HttpClient();
    final sseUri = Uri.parse('${widget.serverUrl}/api/events');

    client.getUrl(sseUri).then((request) {
      return request.close();
    }).then((response) {
      response
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
        // SSE 파싱: "data: {...}\n\n"
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data.contains('device_added') || data.contains('commission_result')) {
            if (mounted) {
              setState(() => _status = '✅ 커미셔닝 성공!');
              _showResultDialog('커미셔닝 완료', '디바이스가 추가되었습니다.\nWiFi: $ssid');
            }
          } else if (data.contains('commission_error')) {
            if (mounted) {
              setState(() => _status = '❌ 커미셔닝 실패');
              _showResultDialog('커미셔닝 실패', '자세한 내용은 로그를 확인하세요.\nCode: $code');
            }
          }
        }
      });
    }).catchError((e) {
      print('[COMM] SSE connection failed: $e');
    });
  }

  void _showResultDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// WiFi + Pairing Code 입력 다이얼로그
  Future<({String pairingCode, String ssid, String password})?>
      _showCommissionDialog() async {
    final codeController = TextEditingController(text: '0564-154-0754');
    final ssidController = TextEditingController(text: 'TP-Link_E426');
    final pwController = TextEditingController(text: '93666367');

    return showDialog<({String pairingCode, String ssid, String password})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Matter 디바이스 페어링'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Pairing Code',
                  hintText: 'MT:... 또는 11자리 숫자',
                  helperText: 'QR코드(MT:...) 또는 Manual Code',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ssidController,
                decoration: const InputDecoration(
                  labelText: 'WiFi SSID',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pwController,
                decoration: const InputDecoration(
                  labelText: 'WiFi Password',
                ),
                obscureText: true,
              ),
            ],
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
                  codeController.text.replaceAll(' ', '').replaceAll('-', '');
              if (code.isNotEmpty && ssidController.text.isNotEmpty) {
                Navigator.pop(ctx, (
                  pairingCode: code,
                  ssid: ssidController.text,
                  password: pwController.text,
                ));
              }
            },
            child: const Text('커미셔닝 시작'),
          ),
        ],
      ),
    );
  }

  /// Go 서버에 WiFi credentials 설정
  Future<void> _setWifiCredentials(String ssid, String password) async {
    setState(() => _status = 'WiFi credentials 설정 중...');
    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('${widget.serverUrl}/api/wifi-credentials'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'ssid': ssid,
      'password': password,
    }));
    final response = await request.close();
    await response.drain();
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('WiFi credentials 설정 실패: HTTP ${response.statusCode}');
    }
  }

  /// Go 서버에 commission 요청 (network_only=false)
  Future<void> _requestCommission(String code) async {
    setState(() => _status = 'Commission 요청 중...');
    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('${widget.serverUrl}/api/commission'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'code': code,
      'network_only': false, // B안: matterjs가 BLE 커미셔닝 수행
    }));
    final response = await request.close();
    await response.drain();

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception('Commission 요청 실패: HTTP ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matter 디바이스 페어링'),
      ),
      body: Column(
        children: [
          // 상태 바
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _commissioning
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                if (_commissioning) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(_status, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),

          // 안내
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Matter 디바이스를 페어링 모드로 설정한 후\n'
                      '아래 버튼을 눌러 커미셔닝을 시작하세요.\n\n'
                      'BLE 스캔 → BTP 핸드셰이크 → PASE 인증 →\n'
                      'WiFi 전달 → on-network 커미셔닝까지\n'
                      '자동으로 진행됩니다.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _commissioning ? null : _startCommissioning,
        icon: Icon(_commissioning ? Icons.hourglass_top : Icons.add_link),
        label: Text(_commissioning ? '진행 중...' : '디바이스 추가'),
      ),
    );
  }
}
