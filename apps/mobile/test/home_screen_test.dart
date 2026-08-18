import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/screens/home_screen.dart';
import 'package:vanam_mobile/theme/tokens.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildVanamTheme(), home: child);

void main() {
  testWidgets('Home shows VANAM web page updates', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));

    expect(find.text('Web Page Updates'), findsOneWidget);
    expect(find.text('Varalakshmi Vratham'), findsOneWidget);
    expect(find.text('VANAM Central Library'), findsOneWidget);
    expect(find.text('Open page'), findsNWidgets(2));
  });
}
