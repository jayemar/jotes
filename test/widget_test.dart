import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/main.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/notes_provider.dart';

/// Real notesProvider goes through DbService (real sqflite platform
/// channel) and, via JotesApp's initState, NotificationService (real
/// flutter_local_notifications channel) - neither is registered in a plain
/// `flutter test` run. Overriding with an empty in-memory notifier lets
/// this test smoke-test the real JotesApp shell (MaterialApp, theme,
/// navigatorKey, notification-stream wiring) without touching either.
class _EmptyNotesNotifier extends NotesNotifier {
  @override
  Future<List<Note>> build() async => const [];
}

void main() {
  testWidgets('app boots and shows the notes list app bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [notesProvider.overrideWith(() => _EmptyNotesNotifier())],
        child: const JotesApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The app bar's title is now the persistent search field, not a plain
    // "jotes" text label - that moved into the hamburger drawer.
    expect(find.byKey(const Key('search_field')), findsOneWidget);
  });

  group('noteIdFromWidgetUri', () {
    test('extracts the id from a well-formed jotes://note/{id} URI', () {
      expect(noteIdFromWidgetUri(Uri.parse('jotes://note/abc123')), 'abc123');
    });

    test('returns null for a null URI', () {
      expect(noteIdFromWidgetUri(null), isNull);
    });

    test("returns null when the host isn't \"note\"", () {
      expect(noteIdFromWidgetUri(Uri.parse('jotes://widget/abc123')), isNull);
    });

    test('returns null when there is no id in the path', () {
      expect(noteIdFromWidgetUri(Uri.parse('jotes://note/')), isNull);
    });
  });
}
