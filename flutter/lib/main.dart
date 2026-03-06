import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'backend_process.dart';

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
  late final WebViewController _controller;
  BackendProcess? _backend;
  bool _isLoading = true;
  String _error = '';
  String _status = '초기화 중...';

  static const int _goPort = 8080;
  String get _serverUrl => 'http://localhost:$_goPort';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
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
    // Android: 앱이 백그라운드로 가도 프로세스 유지
    // 완전 종료(detached)될 때만 stop
    if (state == AppLifecycleState.detached) {
      _backend?.stop();
    }
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() {
            _isLoading = false;
            _error = '';
            _status = '';
          }),
          onWebResourceError: (error) => setState(() {
            _isLoading = false;
            _error = '서버 연결 실패: ${error.description}';
          }),
        ),
      );
  }

  Future<void> _startBackend() async {
    final mode = detectBackendMode();

    if (mode == BackendMode.bundle) {
      // Android: 번들 내 프로세스 시작
      setState(() => _status = '백엔드 시작 중...');
      final bundlePath = '${_appFilesDir()}/backend';
      _backend = BackendProcess(bundlePath: bundlePath, goPort: _goPort);

      try {
        await _backend!.start();
        setState(() => _status = '서버 연결 중...');
        _controller.loadRequest(Uri.parse(_serverUrl));
      } catch (e) {
        setState(() {
          _isLoading = false;
          _error = '백엔드 시작 실패: $e';
        });
      }
    } else {
      // Yocto/개발: 외부 서버에 바로 연결, healthcheck 후 로드
      setState(() => _status = '서버 확인 중...');
      final checker = BackendProcess(bundlePath: '', goPort: _goPort);

      // 최대 10초 대기 (Yocto에서 systemd 시작 시간)
      bool healthy = false;
      for (int i = 0; i < 10; i++) {
        if (await checker.checkHealth()) {
          healthy = true;
          break;
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      if (healthy) {
        setState(() => _status = '서버 연결 중...');
        _controller.loadRequest(Uri.parse(_serverUrl));
      } else {
        setState(() {
          _isLoading = false;
          _error = '서버를 찾을 수 없습니다 ($_serverUrl)';
        });
      }
    }
  }

  /// Android app files 디렉토리
  String _appFilesDir() {
    if (Platform.isAndroid) {
      // /data/data/<package>/files
      return '/data/data/com.example.homeagent/files';
    }
    // Linux fallback
    return '${Platform.environment['HOME'] ?? '/tmp'}/.homeagent';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // WebView (항상 렌더링, 로딩/에러 오버레이 위에)
            WebViewWidget(controller: _controller),

            // 로딩 상태
            if (_isLoading && _error.isEmpty)
              Container(
                color: const Color(0xFF1A1A2E),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _status,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 에러 상태
            if (_error.isNotEmpty)
              Container(
                color: const Color(0xFF1A1A2E),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _error,
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _error = '';
                              _isLoading = true;
                              _status = '재연결 중...';
                            });
                            _startBackend();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('재연결'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
