import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';
import 'package:jotes/providers/sync_provider.dart';
import 'package:jotes/screens/notes_screen.dart';

/// Same in-memory test double pattern as notes_screen_sync_indicator_test.dart.
class _FakeNotesNotifier extends NotesNotifier {
  @override
  Future<List<Note>> build() async => const [];
}

class _RecordingSyncNotifier extends SyncNotifier {
  int resyncCalls = 0;

  @override
  SyncState build() => const SyncState(status: SyncStatus.connected);

  @override
  Future<void> resync() async {
    resyncCalls++;
  }
}

void main() {
  testWidgets(
    'pulling down the notes list triggers a resync, mirroring the "Sync '
    'now" button in Sync settings',
    (tester) async {
      final syncNotifier = _RecordingSyncNotifier();
      final container = ProviderContainer(
        overrides: [
          notesProvider.overrideWith(() => _FakeNotesNotifier()),
          syncProvider.overrideWith(() => syncNotifier),
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

      expect(find.byKey(const Key('notes_refresh_indicator')), findsOneWidget);

      // Standard way to trigger a RefreshIndicator in a widget test - a
      // drag alone doesn't release past the trigger threshold reliably,
      // but a fling with enough distance/speed does.
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(syncNotifier.resyncCalls, 1);
    },
  );
}
