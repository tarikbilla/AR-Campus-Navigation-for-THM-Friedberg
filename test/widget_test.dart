// Basic smoke test for the AR Campus Navigation app.

import 'package:flutter_test/flutter_test.dart';

import 'package:thmcampusnav/app.dart';

void main() {
  testWidgets('App launches on the home screen with both navigation modes',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ThmCampusApp());
    await tester.pump();

    // The two committed navigation modes are advertised on the home screen.
    expect(find.text('Map Mode'), findsOneWidget);
    expect(find.text('AR Mode'), findsOneWidget);
  });
}
