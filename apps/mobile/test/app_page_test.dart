import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/navigation/app_page.dart';

void main() {
  test('every page has a unique id and label', () {
    expect(AppPage.duplicates(), isEmpty);
  });

  test('ids are non-empty and use a known prefix', () {
    for (final page in AppPage.values) {
      expect(page.id, matches(RegExp(r'^(tab|screen|flow)\.[a-z_]+$')));
    }
  });

  test('tabs are contiguous and ordered', () {
    final tabs = AppPage.tabs;
    expect([for (final t in tabs) t.tabIndex], [0, 1, 2, 3]);
    expect(tabs.every((t) => t.kind == AppPageKind.tab), isTrue);
  });

  test('lookup by label and id', () {
    expect(AppPage.byLabel('Messages'), AppPage.messages);
    expect(AppPage.byId('tab.home'), AppPage.home);
    expect(AppPage.byLabel('Nope'), isNull);
  });
}
