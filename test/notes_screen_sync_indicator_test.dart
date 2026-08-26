import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/providers/sync_provider.dart';
import 'package:jotes/screens/notes_screen.dart';
import 'package:jotes/screens/sync_settings_screen.dart';

/// Same in-memory test double pattern as notes_screen_search_test.dart, but
/// for notesProvider only - syncProvider is overridden separately per test
/// below so each test controls SyncState directly, without a real
/// PbService/SharedPreferences round trip.
class _FakeNotesNotifier extends NotesNotifier {
  @override
  Future<List<Note>> build() async => const [];
}

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this._state);
  final SyncState _state;

  @override
  SyncState build() => _state;
}

Future<void> _pumpNotesScreen(WidgetTester tester, SyncState syncState) async {
  final container = ProviderContainer(
    overrides: [
      notesProvider.overrideWith(() => _FakeNotesNotifier()),
      syncProvider.overrideWith(() => _FakeSyncNotifier(syncState)),
    ],
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

Color _indicatorColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const Key('sync_indicator')),
  );
  return (container.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('the sync indicator is red when not connected', (tester) async {
    await _pumpNotesScreen(tester, SyncState.initial);

    expect(find.byKey(const Key('sync_indicator')), findsOneWidget);
    expect(_indicatorColor(tester), Colors.red);
  });

  testWidgets('the sync indicator is green when connected', (tester) async {
    await _pumpNotesScreen(
      tester,
      const SyncState(
        status: SyncStatus.connected,
        serverUrl: 'http://example.com',
        userEmail: 'me@example.com',
      ),
    );

    expect(_indicatorColor(tester), Colors.green);
  });

  testWidgets('the sync indicator is red while connecting or on error, not '
      'just fully disconnected', (tester) async {
    await _pumpNotesScreen(tester, const SyncState(status: SyncStatus.error));

    expect(_indicatorColor(tester), Colors.red);
  });

  testWidgets('tapping the sync indicator opens the sync settings screen', (
    tester,
  ) async {
    await _pumpNotesScreen(tester, SyncState.initial);

    await tester.tap(find.byKey(const Key('sync_indicator_button')));
    await tester.pumpAndSettle();

    expect(find.byType(SyncSettingsScreen), findsOneWidget);
  });

  testWidgets(
    'the app bar keeps its leading/title spacing tight, and the sync '
    'indicator\'s own padding modest, so the search field gets as much '
    'width as possible rather than losing it to dead space',
    (tester) async {
      await _pumpNotesScreen(tester, SyncState.initial);

      final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(appBar.leadingWidth, 48);
      expect(appBar.titleSpacing, 4);

      final indicatorPadding = tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.byKey(const Key('sync_indicator')),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding;
      expect(indicatorPadding, const EdgeInsets.all(8));
    },
  );
}
