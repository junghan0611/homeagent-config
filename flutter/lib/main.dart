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
  String get _serverUrl => 'http://localhost:$_goPort';

  /// Linux desktop → Flutter 네이티브 UI
  /// Android/Yocto → WebView Shell
  bool get _useWebView => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    final mode = detectBackendMode();

    if (mode == BackendMode.bundle) {
      setState(() => _status = '백엔드 시작 중...');
      final bundlePath = '${_appFilesDir()}/backend';
      _backend = BackendProcess(bundlePath: bundlePath, goPort: _goPort);
      try {
        await _backend!.start();
        setState(() {
          _serverReady = true;
          _isLoading = false;
          _status = '';
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
          _error = '백엔드 시작 실패: $e';
        });
      }
    } else {
      // External mode: healthcheck 후 연결
      setState(() => _status = '서버 확인 중...');
      final checker = BackendProcess(bundlePath: '', goPort: _goPort);

      for (int i = 0; i < 10; i++) {
        if (await checker.checkHealth()) {
          setState(() {
            _serverReady = true;
            _isLoading = false;
            _status = '';
          });
          return;
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      setState(() {
        _isLoading = false;
        _error = '서버를 찾을 수 없습니다 ($_serverUrl)\nGo 서버를 먼저 실행하세요';
      });
    }
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
