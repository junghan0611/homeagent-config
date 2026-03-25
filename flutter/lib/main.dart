import 'dart:io';

import 'package:flutter/material.dart';

import 'backend_process.dart';
import 'shell_webview.dart';
import 'widgets/nav_shell.dart';
import 'ble_commissioning.dart';
import 'theme.dart';

/// --dart-define=NATIVE_UI=true → Android에서도 네이티브 UI 사용
const _forceNative = bool.fromEnvironment('NATIVE_UI', defaultValue: true);

void main() {
  runApp(const HomeAgentApp());
}

class HomeAgentApp extends StatefulWidget {
  const HomeAgentApp({super.key});

  @override
  State<HomeAgentApp> createState() => _HomeAgentAppState();

  /// 하위 위젯에서 테마 변경용
  static _HomeAgentAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_HomeAgentAppState>();
}

class _HomeAgentAppState extends State<HomeAgentApp> {
  ThemeMode _themeMode = ThemeMode.light; // 기본: 라이트 (월패드 밝은 환경)

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Hub',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
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
  /// Android 기본 → WebView Shell
  /// Android --dart-define=NATIVE_UI=true → 네이티브 UI
  bool get _useWebView => Platform.isAndroid && !_forceNative;

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

  int _retryCount = 0;
  static const int _maxRetries = 30; // 부팅 후 최대 90초 대기 (3초×30)

  Future<void> _startBackend() async {
    setState(() {
      _status = '서버 시작 대기 중...';
      _retryCount = 0;
    });
    debugPrint('[HomeAgent] 서버 연결 시도: $_serverUrl');

    for (int i = 0; i < _maxRetries; i++) {
      setState(() {
        _retryCount = i + 1;
        _status = '서버 시작 대기 중... (${i + 1}/$_maxRetries)';
      });
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final request = await client.getUrl(Uri.parse('$_serverUrl/api/devices'));
        final response = await request.close();
        await response.drain();
        if (response.statusCode == 200) {
          debugPrint('[HomeAgent] 서버 연결 성공! (${i + 1}번째 시도)');
          setState(() {
            _serverReady = true;
            _isLoading = false;
            _status = '';
          });
          return;
        }
      } catch (e) {
        debugPrint('[HomeAgent] 연결 시도 ${i + 1}/$_maxRetries: $e');
      }
      await Future.delayed(const Duration(seconds: 3));
    }

    debugPrint('[HomeAgent] 서버 연결 실패: $_serverUrl');
    setState(() {
      _isLoading = false;
      _error = '서버를 찾을 수 없습니다\n$_serverUrl\n$_maxRetries회 시도 후 포기';
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
    // 로딩 중 — 서버 시작 대기 (부팅 후 50~80초)
    if (_isLoading) {
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 64, height: 64,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  value: _maxRetries > 0 ? _retryCount / _maxRetries : null,
                ),
              ),
              const SizedBox(height: 24),
              const Icon(Icons.router, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_status, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text(
                '부팅 후 서버가 시작될 때까지 기다리는 중입니다',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
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
        return Stack(
          children: [
            ShellWebView(serverUrl: _serverUrl),
            // BLE 페어링 FAB
            if (Platform.isAndroid)
              Positioned(
                right: 16,
                bottom: 80,
                child: FloatingActionButton(
                  mini: true,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BleCommissioningScreen(serverUrl: _serverUrl),
                    ),
                  ),
                  child: const Icon(Icons.bluetooth_searching, size: 20),
                ),
              ),
          ],
        );
      } else {
        return NavShell(serverUrl: _serverUrl);
      }
    }

    return const SizedBox.shrink();
  }
}
