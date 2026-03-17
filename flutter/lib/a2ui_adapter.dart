import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show visibleForTesting;
import 'package:genui/genui.dart';

import 'api_client.dart';

/// Go HomeAgent /api/home JSON → genui A2UI 어댑터
///
/// Go surface.go의 중첩 트리 JSON을 genui A2UI v0.9 프로토콜로 변환.
/// 핵심: 중첩 트리 → 평탄화된 ID 기반 컴포넌트 + surfaceUpdate + beginRendering
class HomeAgentA2uiAdapter {
  final ApiClient api;
  late final A2uiMessageProcessor _processor;

  HomeAgentA2uiAdapter({required this.api}) {
    final catalog = CoreCatalogItems.asCatalog();
    _processor = A2uiMessageProcessor(catalogs: [catalog]);
  }

  /// genui GenUiSurface 위젯에 전달할 host
  GenUiHost get host => _processor;

  /// Go /api/home에서 Surface JSON을 가져와 genui에 주입
  Future<void> fetchAndRender() async {
    try {
      final homeData = await api.getHome();
      if (homeData == null) {
        debugPrint('[A2uiAdapter] /api/home returned null');
        return;
      }

      final surfaceId = (homeData['surfaceId'] as String?) ?? 'home';
      final components = homeData['components'] as List? ?? [];

      // 1. 트리 평탄화 → ID 기반 컴포넌트 리스트
      _idCounter = 0;
      final flatComponents = <Map<String, dynamic>>[];
      final rootId = _flattenTree(components, flatComponents, 'root');

      debugPrint('[A2uiAdapter] Flattened: ${flatComponents.length} components, root=$rootId');

      if (flatComponents.isEmpty || rootId.isEmpty) {
        debugPrint('[A2uiAdapter] No components to render');
        return;
      }

      // 2. surfaceUpdate 메시지 — 컴포넌트 등록
      final updateMsg = A2uiMessage.fromJson({
        'surfaceUpdate': {
          'surfaceId': surfaceId,
          'components': flatComponents,
        },
      });
      _processor.handleMessage(updateMsg);

      // 3. beginRendering 메시지 — 렌더링 시작
      final renderMsg = A2uiMessage.fromJson({
        'beginRendering': {
          'surfaceId': surfaceId,
          'root': rootId,
        },
      });
      _processor.handleMessage(renderMsg);

      debugPrint('[A2uiAdapter] Surface rendered OK');
    } catch (e, stack) {
      debugPrint('[A2uiAdapter] fetchAndRender error: $e');
      debugPrint('[A2uiAdapter] stack: ${stack.toString().split('\n').take(5).join('\n')}');
    }
  }

  /// SSE surface_update 이벤트 수신 시 호출
  void handleSurfaceUpdate(Map<String, dynamic> surfaceData) {
    // surface_update는 전체 교체이므로 fetchAndRender와 동일 처리
    try {
      final surfaceId = (surfaceData['surfaceId'] as String?) ?? 'home';
      final components = surfaceData['components'] as List? ?? [];

      _idCounter = 0;
      final flatComponents = <Map<String, dynamic>>[];
      final rootId = _flattenTree(components, flatComponents, 'root');

      final updateMsg = A2uiMessage.fromJson({
        'surfaceUpdate': {
          'surfaceId': surfaceId,
          'components': flatComponents,
        },
      });
      _processor.handleMessage(updateMsg);

      final renderMsg = A2uiMessage.fromJson({
        'beginRendering': {
          'surfaceId': surfaceId,
          'root': rootId,
        },
      });
      _processor.handleMessage(renderMsg);
    } catch (e) {
      debugPrint('[A2uiAdapter] surface_update error: $e');
    }
  }

  /// 테스트용 — 평탄화 결과 확인
  @visibleForTesting
  Map<String, dynamic> convertToA2uiForTest(Map<String, dynamic> goSurface) {
    _idCounter = 0;
    final components = goSurface['components'] as List? ?? [];
    final flatComponents = <Map<String, dynamic>>[];
    final rootId = _flattenTree(components, flatComponents, 'root');
    return {
      'surfaceUpdate': {
        'surfaceId': goSurface['surfaceId'] ?? 'home',
        'components': flatComponents,
      },
      'rootId': rootId,
    };
  }

  // ─── 트리 평탄화 ───

  int _idCounter = 0;

  String _nextId(String prefix) => '${prefix}_${_idCounter++}';

  /// Go 중첩 트리 → genui 평탄 컴포넌트 리스트
  /// 반환: root 컴포넌트 ID (빈 리스트면 빈 문자열)
  String _flattenTree(
    List components,
    List<Map<String, dynamic>> output,
    String prefix,
  ) {
    if (components.isEmpty) return '';

    if (components.length == 1) {
      return _flattenComponent(
        Map<String, dynamic>.from(components[0]),
        output,
        prefix,
      );
    }

    // 여러 컴포넌트 → Column 래퍼
    final columnId = _nextId(prefix);
    final childIds = <String>[];
    for (final comp in components) {
      final childId = _flattenComponent(
        Map<String, dynamic>.from(comp),
        output,
        '${columnId}_c',
      );
      childIds.add(childId);
    }

    output.add({
      'id': columnId,
      'component': {
        'Column': {
          'children': childIds,
          'gap': 8,
        },
      },
    });

    return columnId;
  }

  /// 단일 Go 컴포넌트 → 평탄화. 반환: 이 컴포넌트의 ID
  String _flattenComponent(
    Map<String, dynamic> comp,
    List<Map<String, dynamic>> output,
    String prefix,
  ) {
    final type = comp['type'] as String? ?? 'Text';
    final props = Map<String, dynamic>.from(comp['props'] ?? {});
    final children = comp['children'] as List?;
    final id = _nextId(prefix);

    // children이 있으면 재귀 평탄화 → ID 참조로 교체
    if (children != null && children.isNotEmpty) {
      final childIds = <String>[];
      for (final child in children) {
        final childId = _flattenComponent(
          Map<String, dynamic>.from(child),
          output,
          '${id}_c',
        );
        childIds.add(childId);
      }
      props['children'] = childIds;
    }

    // genui 컴포넌트 포맷: {id, component: {TypeName: {props}}}
    output.add({
      'id': id,
      'component': {
        type: props,
      },
    });

    return id;
  }
}
