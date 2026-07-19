import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:jotes/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotesNotifier extends NotesNotifier {
  @override
  Future<List<Note>> build() async => const [];
}

Future<void> _pumpNotesScreen(WidgetTester tester) async {
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
      'tapping Settings in the drawer navigates to the Settings screen',
      (tester) async {
    await _pumpNotesScreen(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_drawer_item')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_drawer_item')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
