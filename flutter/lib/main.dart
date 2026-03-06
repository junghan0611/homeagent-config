import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

class _HomeAgentShellState extends State<HomeAgentShell> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _error = '';

  // Go 백엔드 주소 — 같은 기기에서 실행 시 localhost,
  // RPi5 등 원격이면 IP로 변경
  static const String _serverUrl = 'http://localhost:8080';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() {
            _isLoading = false;
            _error = '';
          }),
          onWebResourceError: (error) => setState(() {
            _isLoading = false;
            _error = '서버 연결 실패: ${error.description}';
          }),
        ),
      )
      ..loadRequest(Uri.parse(_serverUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),
            if (_error.isNotEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(_error, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _error = '';
                          _isLoading = true;
                        });
                        _controller.loadRequest(Uri.parse(_serverUrl));
                      },
                      child: const Text('재연결'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
