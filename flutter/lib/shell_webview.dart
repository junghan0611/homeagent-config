import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'ble_relay.dart';

/// WebView Shell — Android / Yocto (ivi-homescreen)
/// A2UI + Lit UI를 WebView로 렌더링
class ShellWebView extends StatefulWidget {
  final String serverUrl;
  const ShellWebView({super.key, required this.serverUrl});

  @override
  State<ShellWebView> createState() => _ShellWebViewState();
}

class _ShellWebViewState extends State<ShellWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  BleRelay? _bleRelay;

  @override
  void initState() {
    super.initState();
    _initBleRelay();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('[WebView] 페이지 로딩 시작: $url');
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            debugPrint('[WebView] 페이지 로딩 완료: $url');
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint('[WebView] 에러: ${error.errorCode} ${error.description}');
            setState(() => _isLoading = false);
          },
        ),
      )
      ..setOnConsoleMessage((message) {
        debugPrint('[WebView:JS] ${message.level}: ${message.message}');
      })
      ..loadRequest(Uri.parse(widget.serverUrl));
  }

  /// BLE relay를 APK 시작 시 자동 연결 — Web UI 커미셔닝에서도 BLE 사용 가능
  void _initBleRelay() {
    final serverUri = Uri.parse(widget.serverUrl);
    final bleWsUrl = 'ws://${serverUri.host}:5581';
    _bleRelay = BleRelay(
      wsUrl: bleWsUrl,
      onStatus: (s) => debugPrint('[BLE-RELAY] $s'),
    );
    _bleRelay!.connect();
  }

  @override
  void dispose() {
    _bleRelay?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
