import 'package:flutter_test/flutter_test.dart';

import 'package:vanam_mobile/main.dart';

void main() {
  testWidgets('Login screen shows invite code + PIN fields, no password/signup', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VanamApp());

    expect(find.text('Welcome to Vanam'), findsOneWidget);
    expect(find.text('Invite code'), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);

    // No open-registration UI should ever appear on this screen.
    expect(find.text('Password'), findsNothing);
    expect(find.text('Sign Up'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
  });

  testWidgets('Login button shows validation errors on empty submit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VanamApp());

    await tester.tap(find.text('Log In'));
    await tester.pump();

    expect(find.text('Enter the invite code your admin shared'), findsOneWidget);
    expect(find.text('Enter the PIN your admin gave you'), findsOneWidget);
  });
}
