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

    test('Text — literalString + usageHint 변환', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'home',
        'components': [
          {'type': 'Text', 'props': {'variant': 'h3', 'text': '15:04'}},
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      expect(comps.length, 1);

      final textProps = comps[0]['component']['Text'] as Map;
      expect(textProps['text'], {'literalString': '15:04'});
      expect(textProps['usageHint'], 'h3');
    });

    test('Card + children → Column 래퍼 + child 단일 참조', () {
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
      // Text + Divider + Column래퍼 + Card = 4개
      expect(comps.length, 4);

      final card = comps.lastWhere((c) =>
          (c['component'] as Map).containsKey('Card'));
      // Card.child가 Column 래퍼 ID
      expect(card['component']['Card']['child'], isA<String>());
    });

    test('Row — children ID 배열', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'test',
        'components': [
          {
            'type': 'Row',
            'children': [
              {'type': 'Icon', 'props': {'name': 'home', 'size': 32}},
              {'type': 'Text', 'props': {'text': '거실'}},
            ],
          },
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      expect(comps.length, 3); // Icon + Text + Row

      final row = comps.lastWhere((c) =>
          (c['component'] as Map).containsKey('Row'));
      final childIds = row['component']['Row']['children'] as List;
      expect(childIds.length, 2);
    });

    test('Icon — literalString 매핑', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'test',
        'components': [
          {'type': 'Icon', 'props': {'name': 'home'}},
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      final icon = comps[0]['component']['Icon'] as Map;
      expect(icon['name'], {'literalString': 'home'});
    });

    test('Divider — 빈 props', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'test',
        'components': [
          {'type': 'Divider'},
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      expect(comps[0]['component']['Divider'], isA<Map>());
    });

    test('여러 최상위 → Column 래퍼 + rootId', () {
      final result = adapter.convertToA2uiForTest({
        'surfaceId': 'home',
        'components': [
          {'type': 'Text', 'props': {'text': 'a'}},
          {'type': 'Text', 'props': {'text': 'b'}},
        ],
      });

      final comps = result['surfaceUpdate']['components'] as List;
      // Text + Text + Column = 3
      expect(comps.length, 3);
      expect(result['rootId'], isNotEmpty);
    });
  });
}
