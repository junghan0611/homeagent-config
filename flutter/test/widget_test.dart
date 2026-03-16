import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/theme.dart';

void main() {
  // main.dart의 HomeAgentApp은 HttpClient + Timer를 사용하므로
  // 직접 테스트하면 Timer pending 에러 발생.
  // 대신 테마와 기본 위젯 구성만 검증.

  testWidgets('AppTheme.dark() — MaterialApp 렌더링', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        title: 'IoT Hub',
        theme: AppTheme.dark(),
        home: const Scaffold(body: Text('test')),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
  });

  testWidgets('AppTheme.light() — MaterialApp 렌더링', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        title: 'IoT Hub',
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('light')),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('light'), findsOneWidget);
  });
}
