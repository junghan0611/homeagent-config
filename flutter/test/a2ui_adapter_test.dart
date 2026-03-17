import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/a2ui_adapter.dart';
import 'package:homeagent/api_client.dart';

void main() {
  group('HomeAgentA2uiAdapter 트리 평탄화', () {
    late HomeAgentA2uiAdapter adapter;

    setUp(() {
      adapter = HomeAgentA2uiAdapter(
        api: ApiClient(baseUrl: 'http://localhost:8080'),
      );
    });

    test('단일 Text 컴포넌트 → 평탄화', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'home',
        'components': [
          {'type': 'Text', 'props': {'variant': 'h3', 'text': '15:04'}},
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      expect(comps.length, 1);
      expect(comps[0]['id'], isA<String>());
      expect(comps[0]['component']['Text']['text'], '15:04');
      expect(result['rootId'], comps[0]['id']);
    });

    test('Card + children → 평탄화 (children이 ID 참조)', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'home',
        'components': [
          {
            'type': 'Card',
            'props': {'variant': 'elevated'},
            'children': [
              {'type': 'Text', 'props': {'text': 'hello'}},
              {'type': 'Divider'},
            ],
          },
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      // Text + Divider + Card = 3개
      expect(comps.length, 3);

      // Card의 children이 ID 참조 배열
      final card = comps.lastWhere((c) => c['component'].containsKey('Card'));
      final childIds = card['component']['Card']['children'] as List;
      expect(childIds.length, 2);
      expect(childIds.every((id) => id is String), true);
    });

    test('여러 최상위 컴포넌트 → Column 래퍼', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'home',
        'components': [
          {'type': 'Card', 'props': {'variant': 'elevated'}},
          {'type': 'Card', 'props': {'variant': 'outlined'}},
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      // Card1 + Card2 + Column = 3개
      expect(comps.length, 3);

      final root = comps.lastWhere((c) => c['component'].containsKey('Column'));
      expect(root['id'], result['rootId']);
      expect((root['component']['Column']['children'] as List).length, 2);
    });

    test('빈 components → 빈 리스트 + root null', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'empty',
        'components': [],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      // 빈 리스트 → Column 래퍼도 없음
      expect(comps, isEmpty);
    });

    test('깊은 중첩 — Row > Icon + Text', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'test',
        'components': [
          {
            'type': 'Row',
            'props': {'gap': 10},
            'children': [
              {'type': 'Icon', 'props': {'name': 'sun', 'size': 32}},
              {'type': 'Text', 'props': {'variant': 'body', 'text': '거실'}},
            ],
          },
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      expect(comps.length, 3); // Icon + Text + Row

      final row = comps.lastWhere((c) => c['component'].containsKey('Row'));
      expect(row['component']['Row']['gap'], 10);
      expect((row['component']['Row']['children'] as List).length, 2);
    });

    test('props 없는 Divider', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'test',
        'components': [
          {'type': 'Divider'},
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      expect(comps.length, 1);
      expect(comps[0]['component'].containsKey('Divider'), true);
    });
  });
}
