import 'package:flutter/material.dart';
import 'package:genui/genui.dart' show GenUiSurface;

import '../a2ui_adapter.dart';
import '../api_client.dart';

/// A2UI genui Surface 테스트 화면
/// 설정 → "A2UI 테스트"에서 접근
/// Go /api/home JSON을 genui SDK로 렌더링하는 기능 검증용
class A2uiTestScreen extends StatefulWidget {
  final String serverUrl;
  const A2uiTestScreen({super.key, required this.serverUrl});

  @override
  State<A2uiTestScreen> createState() => _A2uiTestScreenState();
}

class _A2uiTestScreenState extends State<A2uiTestScreen> {
  late final ApiClient _api;
  late final HomeAgentA2uiAdapter _a2ui;
  String _status = '초기화 중...';
  Map<String, dynamic>? _rawJson;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: widget.serverUrl);
    _a2ui = HomeAgentA2uiAdapter(api: _api);
    _loadSurface();
  }

  Future<void> _loadSurface() async {
    setState(() => _status = '/api/home 로딩 중...');

    try {
      final homeData = await _api.getHome();
      if (homeData == null) {
        setState(() => _status = '❌ /api/home 응답 없음');
        return;
      }

      setState(() {
        _rawJson = homeData;
        _status = '✅ JSON 수신 (${(homeData['components'] as List?)?.length ?? 0} components)';
      });

      // genui로 렌더링 시도
      await _a2ui.fetchAndRender();
      setState(() => _status += '\n✅ genui 렌더링 요청 완료');
    } catch (e) {
      setState(() => _status = '❌ 에러: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('A2UI 테스트'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSurface,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 상태
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('상태', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(_status, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // genui Surface 렌더링 결과
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('genui Surface', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 300,
                    child: GenUiSurface(
                      host: _a2ui.host,
                      surfaceId: 'home',
                      defaultBuilder: (_) => Center(
                        child: Text(
                          'Surface 미렌더링\n(genui가 컴포넌트를 인식하지 못함)',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Raw JSON
          if (_rawJson != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Go /api/home Raw JSON', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text(
                      _formatJson(_rawJson!),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatJson(Map<String, dynamic> json) {
    // 간결하게 컴포넌트 트리만 표시
    final components = json['components'] as List? ?? [];
    final buf = StringBuffer();
    buf.writeln('surfaceId: ${json['surfaceId']}');
    buf.writeln('theme: ${json['theme']}');
    buf.writeln('components (${components.length}):');
    for (final c in components) {
      _printComp(c, buf, '  ');
    }
    return buf.toString();
  }

  void _printComp(dynamic comp, StringBuffer buf, String indent) {
    if (comp is! Map) return;
    final type = comp['type'] ?? '?';
    final props = comp['props'] as Map? ?? {};
    final text = props['text'] ?? '';
    final variant = props['variant'] ?? '';
    buf.writeln('$indent$type${text.isNotEmpty ? ': "$text"' : ''}${variant.isNotEmpty ? ' ($variant)' : ''}');
    final children = comp['children'] as List? ?? [];
    for (final child in children) {
      _printComp(child, buf, '$indent  ');
    }
  }
}
