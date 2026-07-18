import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/providers/theme_provider.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotesNotifier extends NotesNotifier {
  @override
  Future<List<Note>> build() async => const [];
}

Future<ProviderContainer> _pumpNotesScreen(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [notesProvider.overrideWith(_FakeNotesNotifier.new)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Opens the theme dropdown and taps the given option. The dropdown's
/// closed button already shows the currently-selected value's text, so
/// once open there can be two matches for that label (button + menu entry)
/// - `.last` reliably targets the opened menu's entry, added later in the
/// tree.
Future<void> _chooseTheme(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('theme_dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the drawer shows a J beside the jotes header', (tester) async {
    await _pumpNotesScreen(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('J'), findsOneWidget);
    expect(find.text('jotes'), findsOneWidget);
  });

  testWidgets(
      'the drawer shows a theme dropdown defaulting to System, with Light '
      'and Dark selectable when opened', (tester) async {
    final container = await _pumpNotesScreen(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('theme_dropdown')), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.tap(find.byKey(const Key('theme_dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('selecting Dark updates the theme provider', (tester) async {
    final container = await _pumpNotesScreen(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await _chooseTheme(tester, 'Dark');

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('selecting Light then System updates the theme provider each '
      'time', (tester) async {
    final container = await _pumpNotesScreen(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await _chooseTheme(tester, 'Light');
    expect(container.read(themeModeProvider), ThemeMode.light);

    // Reopen the drawer + dropdown: selecting an item closes the menu (and
    // in this app's case, the drawer stays open, but re-opening the
    // dropdown fresh each time keeps this test robust either way).
    await _chooseTheme(tester, 'System');
    expect(container.read(themeModeProvider), ThemeMode.system);
  });
}
