import 'dart:io';

import 'package:flutter/material.dart';

import 'backend_process.dart';
import 'shell_webview.dart';
import 'shell_native.dart';

void main() {
  runApp(const HomeAgentApp());
}

class HomeAgentApp extends StatelessWidget {
  const HomeAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeAgent',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeAgentShell(),
    );
  }
}

class HomeAgentShell extends StatefulWidget {
  const HomeAgentShell({super.key});

  @override
  State<HomeAgentShell> createState() => _HomeAgentShellState();
}

class _HomeAgentShellState extends State<HomeAgentShell> with WidgetsBindingObserver {
  BackendProcess? _backend;
  bool _isLoading = true;
  bool _serverReady = false;
  String _error = '';
  String _status = '초기화 중...';

  static const int _goPort = 8080;

  /// Android: 환경변수 또는 기본 서버 주소
  /// Yocto/Linux: localhost (Go 서버가 같은 디바이스)
  String get _serverUrl {
    if (Platform.isAndroid) {
      // Android에서는 Go 서버가 외부(RPi5 등)에 있을 수 있음
      // 추후 설정 화면에서 변경 가능하도록
      return 'http://${const String.fromEnvironment('SERVER_HOST', defaultValue: 'localhost')}:$_goPort';
    }
    return 'http://localhost:$_goPort';
  }

  /// Linux desktop → Flutter 네이티브 UI
  /// Android/Yocto → WebView Shell
  bool get _useWebView => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[HomeAgent] serverUrl=$_serverUrl, useWebView=$_useWebView');
    _startBackend();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backend?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _backend?.stop();
    }
  }

  Future<void> _startBackend() async {
    // 항상 외부 서버 모드로 시작 (서버 URL은 dart-define으로 지정)
    // 추후 번들 모드 추가 시 detectBackendMode() 사용
    setState(() => _status = '서버 연결 중... $_serverUrl');
    debugPrint('[HomeAgent] 서버 연결 시도: $_serverUrl');

    for (int i = 0; i < 10; i++) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final request = await client.getUrl(Uri.parse('$_serverUrl/api/devices'));
        final response = await request.close();
        await response.drain();
        if (response.statusCode == 200) {
          debugPrint('[HomeAgent] 서버 연결 성공!');
          setState(() {
            _serverReady = true;
            _isLoading = false;
            _status = '';
          });
          return;
        }
      } catch (e) {
        debugPrint('[HomeAgent] 연결 시도 ${i + 1}/10: $e');
      }
      await Future.delayed(const Duration(seconds: 1));
    }

    debugPrint('[HomeAgent] 서버 연결 실패: $_serverUrl');
    setState(() {
      _isLoading = false;
      _error = '서버를 찾을 수 없습니다\n$_serverUrl\nGo 서버를 먼저 실행하세요';
    });
  }

  String _appFilesDir() {
    if (Platform.isAndroid) return '/data/data/com.example.homeagent/files';
    return '${Platform.environment['HOME'] ?? '/tmp'}/.homeagent';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // 로딩 중
    if (_isLoading) {
      return Container(
        color: const Color(0xFF1A1A2E),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 24),
              Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // 에러
    if (_error.isNotEmpty) {
      return Container(
        color: const Color(0xFF1A1A2E),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(_error, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() { _error = ''; _isLoading = true; _status = '재연결 중...'; });
                    _startBackend();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('재연결'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 서버 준비 완료 — 플랫폼별 UI
    if (_serverReady) {
      if (_useWebView) {
        return ShellWebView(serverUrl: _serverUrl);
      } else {
        return ShellNative(serverUrl: _serverUrl);
      }
    }

    return const SizedBox.shrink();
  }
}
