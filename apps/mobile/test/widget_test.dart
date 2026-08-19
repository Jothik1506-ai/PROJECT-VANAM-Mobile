import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vanam_mobile/screens/login_screen.dart';
import 'package:vanam_mobile/theme/tokens.dart';

// Pumps LoginScreen directly, not the full VanamApp/AuthGate — AuthGate
// does a real Supabase session check on startup, which needs
// Supabase.initialize() (only called from main.dart's main(), not from
// pumping the widget tree in a test). These tests are about LoginScreen's
// own form/validation behavior, not app-level routing, so they don't need
// any of that. buildVanamTheme() IS needed though — context.vanam requires
// the VanamPalette ThemeExtension to be present.
Widget _wrap(Widget child) =>
    MaterialApp(theme: buildVanamTheme(), home: child);

void main() {
  testWidgets(
    'Login screen shows invite code + PIN fields, no password/signup',
    (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));

      expect(find.text('Welcome to Vanam'), findsOneWidget);
      expect(find.text('Invite code'), findsOneWidget);
      expect(find.text('PIN'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);

      // No open-registration UI should ever appear on this screen.
      expect(find.text('Password'), findsNothing);
      expect(find.text('Sign Up'), findsNothing);
      expect(find.textContaining('Google'), findsNothing);
    },
  );

  testWidgets('Login button shows validation errors on empty submit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    await tester.tap(find.text('Log In'));
    await tester.pump();

    expect(
      find.text('Enter the invite code your admin shared'),
      findsOneWidget,
    );
    expect(find.text('Enter the PIN your admin gave you'), findsOneWidget);
  });
}
