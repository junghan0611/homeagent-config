import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/a2ui_adapter.dart';
import 'package:homeagent/api_client.dart';

void main() {
  group('HomeAgentA2uiAdapter JSON 변환', () {
    late HomeAgentA2uiAdapter adapter;

    setUp(() {
      adapter = HomeAgentA2uiAdapter(
        api: ApiClient(baseUrl: 'http://localhost:8080'),
      );
    });

    test('Go surface JSON → A2UI v0.9 createSurface 포맷', () {
      // Go surface.go가 생성하는 형식
      final goSurface = {
        'surfaceId': 'home',
        'components': [
          {
            'type': 'Card',
            'props': {'variant': 'elevated'},
            'children': [
              {
                'type': 'Text',
                'props': {'variant': 'h3', 'text': '15:04'},
              },
            ],
          },
        ],
        'theme': {'accent': '#FF9800', 'mood': 'morning'},
      };

      final a2ui = adapter.convertToA2uiForTest(goSurface);

      expect(a2ui['version'], 'v0.9');
      expect(a2ui['createSurface'], isNotNull);
      expect(a2ui['createSurface']['surfaceId'], 'home');

      final components = a2ui['createSurface']['components'] as List;
      expect(components.length, 1);
      expect(components[0]['type'], 'card'); // 소문자 변환
      expect(components[0]['props']['variant'], 'elevated');
    });

    test('컴포넌트 type이 소문자로 변환됨', () {
      final goSurface = {
        'surfaceId': 'test',
        'components': [
          {'type': 'Text', 'props': {'text': 'hello'}},
          {'type': 'Icon', 'props': {'name': 'sun'}},
          {'type': 'Row', 'props': {'gap': 8}},
          {'type': 'Column', 'props': {'gap': 4}},
          {'type': 'Divider'},
        ],
      };

      final a2ui = adapter.convertToA2uiForTest(goSurface);
      final comps = a2ui['createSurface']['components'] as List;

      expect(comps[0]['type'], 'text');
      expect(comps[1]['type'], 'icon');
      expect(comps[2]['type'], 'row');
      expect(comps[3]['type'], 'column');
      expect(comps[4]['type'], 'divider');
    });

    test('중첩 children 재귀 변환', () {
      final goSurface = {
        'surfaceId': 'home',
        'components': [
          {
            'type': 'Card',
            'props': {'variant': 'outlined'},
            'children': [
              {
                'type': 'Row',
                'props': {'gap': 10},
                'children': [
                  {'type': 'Icon', 'props': {'name': 'door', 'size': 20}},
                  {'type': 'Text', 'props': {'variant': 'body', 'text': '거실'}},
                ],
              },
            ],
          },
        ],
      };

      final a2ui = adapter.convertToA2uiForTest(goSurface);
      final card = (a2ui['createSurface']['components'] as List)[0];
      final row = (card['children'] as List)[0];
      final children = row['children'] as List;

      expect(children.length, 2);
      expect(children[0]['type'], 'icon');
      expect(children[1]['type'], 'text');
      expect(children[1]['props']['text'], '거실');
    });

    test('빈 components → 빈 리스트', () {
      final goSurface = {'surfaceId': 'empty'};

      final a2ui = adapter.convertToA2uiForTest(goSurface);
      final comps = a2ui['createSurface']['components'] as List;
      expect(comps, isEmpty);
    });

    test('surfaceId 기본값 home', () {
      final goSurface = {'components': []};

      final a2ui = adapter.convertToA2uiForTest(goSurface);
      expect(a2ui['createSurface']['surfaceId'], 'home');
    });

    test('props 없는 컴포넌트 처리', () {
      final goSurface = {
        'surfaceId': 'test',
        'components': [
          {'type': 'Divider'},
        ],
      };

      final a2ui = adapter.convertToA2uiForTest(goSurface);
      final comp = (a2ui['createSurface']['components'] as List)[0];
      expect(comp['type'], 'divider');
      expect(comp['props'], isA<Map>());
    });
  });
}
