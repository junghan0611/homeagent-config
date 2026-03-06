import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/main.dart';

void main() {
  testWidgets('HomeAgent app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const HomeAgentApp());
    expect(find.byType(HomeAgentApp), findsOneWidget);
  });
}
