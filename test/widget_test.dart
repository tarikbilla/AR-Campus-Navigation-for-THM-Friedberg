// Basic smoke test for the AR Campus Navigation app.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thmcampusnav/app.dart';

void main() {
  testWidgets('App boots to the branded splash screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ThmCampusApp());
    await tester.pump();

    // The splash shows the app brand while the app settles.
    expect(find.text('THM Campus AR'), findsOneWidget);

    // Unmount before the splash timer fires so the test tears down cleanly.
    await tester.pumpWidget(const SizedBox());
  });
}
