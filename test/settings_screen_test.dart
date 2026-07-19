import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/providers/theme_provider.dart';
import 'package:jotes/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpSettingsScreen(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Opens a DropdownMenu and taps the entry matching [label]. Unlike the old
/// DropdownButton, DropdownMenu's closed field also displays the current
/// selection as literal text, so there can be two matches once the menu is
/// open - `.last` reliably targets the freshly-opened menu entry, added
/// later in the tree.
Future<void> _choose(
  WidgetTester tester,
  Key dropdownKey,
  String label,
) async {
  await tester.tap(find.byKey(dropdownKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'shows a theme dropdown defaulting to System, with Light and Dark '
      'selectable when opened', (tester) async {
    final container = await _pumpSettingsScreen(tester);

    expect(find.byKey(const Key('theme_dropdown')), findsOneWidget);
    // DropdownMenu pre-builds its entries (for width measurement) even
    // while closed, so the initially-selected entry's text can match both
    // that hidden entry and the closed field's own displayed text -
    // findsWidgets (at least one) is what matters, not an exact count of
    // Flutter's internal representation.
    expect(find.text('System'), findsWidgets);
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.tap(find.byKey(const Key('theme_dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('Light'), findsWidgets);
    expect(find.text('Dark'), findsWidgets);
  });

  testWidgets('selecting Dark updates the theme provider', (tester) async {
    final container = await _pumpSettingsScreen(tester);
    await _choose(tester, const Key('theme_dropdown'), 'Dark');
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets(
      'selecting Light then System updates the theme provider each time',
      (tester) async {
    final container = await _pumpSettingsScreen(tester);
    await _choose(tester, const Key('theme_dropdown'), 'Light');
    expect(container.read(themeModeProvider), ThemeMode.light);
    await _choose(tester, const Key('theme_dropdown'), 'System');
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  testWidgets('shows Font and Text size dropdowns', (tester) async {
    await _pumpSettingsScreen(tester);

    expect(find.byKey(const Key('font_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('text_size_dropdown')), findsOneWidget);
    // DropdownMenu pre-builds its entries (for width measurement) even
    // while closed, so a font entry with a custom labelWidget can match
    // both that hidden entry and the closed field's own displayed text -
    // findsWidgets (at least one) is what actually matters here, not an
    // exact count of Flutter's internal representation.
    expect(find.text('Default'), findsWidgets);
    expect(find.text('Medium'), findsWidgets);
  });
}
