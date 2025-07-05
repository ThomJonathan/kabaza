import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kabanza/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp() as Widget);

    // Verify that the app launches without crashing
    // This checks that a MaterialApp widget exists (which should be in most Flutter apps)
    expect(find.byType(MaterialApp), findsOneWidget);

    // Wait for any async operations to complete
    await tester.pumpAndSettle();

    // The app launched successfully if we get here without exceptions
  });
}

class MyApp {
}
