import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show visibleForTesting;
import 'package:genui/genui.dart';

import 'api_client.dart';

/// Go HomeAgent /api/home JSON → genui A2uiMessage 어댑터
///
/// Go surface.go의 커스텀 JSON을 A2UI v0.9로 변환하여 genui 렌더링.
/// genui가 experimental이므로 이 어댑터를 교체하면 다른 렌더러로 전환 가능.
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
      if (homeData == null) return;

      final a2uiJson = _convertToA2ui(homeData);
      final message = A2uiMessage.fromJson(a2uiJson);
      _processor.handleMessage(message);
    } catch (e) {
      debugPrint('[A2uiAdapter] fetchAndRender error: $e');
    }
  }

  /// SSE surface_update 이벤트 수신 시 호출
  void handleSurfaceUpdate(Map<String, dynamic> surfaceData) {
    try {
      final a2uiJson = _convertToA2ui(surfaceData);
      final message = A2uiMessage.fromJson(a2uiJson);
      _processor.handleMessage(message);
    } catch (e) {
      debugPrint('[A2uiAdapter] surface_update error: $e');
    }
  }

  /// 테스트용 — Go JSON → A2UI v0.9 변환 결과 확인
  @visibleForTesting
  Map<String, dynamic> convertToA2uiForTest(Map<String, dynamic> goSurface) =>
      _convertToA2ui(goSurface);

  /// Go surface.go JSON → A2UI v0.9 createSurface 메시지
  Map<String, dynamic> _convertToA2ui(Map<String, dynamic> goSurface) {
    final surfaceId = goSurface['surfaceId'] ?? 'home';
    final components = goSurface['components'] as List? ?? [];

    final a2uiComponents = components
        .map((c) => _convertComponent(Map<String, dynamic>.from(c)))
        .toList();

    return {
      'version': 'v0.9',
      'createSurface': {
        'surfaceId': surfaceId,
        'components': a2uiComponents,
      },
    };
  }

  /// Go comp → A2UI component (type 소문자 변환)
  Map<String, dynamic> _convertComponent(Map<String, dynamic> comp) {
    final type = (comp['type'] as String? ?? '').toLowerCase();
    final props = Map<String, dynamic>.from(comp['props'] ?? {});
    final children = (comp['children'] as List?)
        ?.map((c) => _convertComponent(Map<String, dynamic>.from(c)))
        .toList();

    final result = <String, dynamic>{
      'type': type,
      'props': props,
    };
    if (children != null && children.isNotEmpty) {
      result['children'] = children;
    }
    return result;
  }
}
