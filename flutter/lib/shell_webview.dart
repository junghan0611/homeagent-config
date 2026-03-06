import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (error) => setState(() => _isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.serverUrl));
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
