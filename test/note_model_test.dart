import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';

Note _note({
  String id = 'n1',
  String title = '',
  String body = '',
  DateTime? reminderAt,
  bool reminderResolved = false,
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: title,
    body: body,
    reminderAt: reminderAt,
    created: now,
    updated: now,
    reminderResolved: reminderResolved,
  );
}

void main() {
  group('Note.isEmpty', () {
    test('true for no title, no body, no reminder', () {
      expect(_note().isEmpty, isTrue);
    });

    test('false when title is set', () {
      expect(_note(title: 'Groceries').isEmpty, isFalse);
    });

    test('false when body is set', () {
      expect(_note(body: 'Milk, eggs').isEmpty, isFalse);
    });

    test(
        'false when only a reminder is set, with no title or body - '
        'a reminder-only note is meaningful and must not be treated as '
        'empty/discardable', () {
      final note = _note(reminderAt: DateTime.now().add(const Duration(hours: 1)));
      expect(note.isEmpty, isFalse);
    });
  });

  group('notesWithActiveOrPendingReminders', () {
    final now = DateTime(2026, 7, 20, 12);

    test('excludes notes with no reminder set', () {
      final notes = [
        _note(id: 'a', title: 'No reminder'),
        _note(id: 'b', reminderAt: now.add(const Duration(hours: 1))),
      ];

      final result = notesWithActiveOrPendingReminders(notes, now: now);

      expect(result.map((n) => n.id), ['b']);
    });

    test('sorts oldest-first regardless of input order, mixing overdue and '
        'upcoming into one chronological list', () {
      final notes = [
        _note(
          id: 'soonest-upcoming',
          reminderAt: now.add(const Duration(minutes: 30)),
        ),
        _note(
          id: 'oldest-overdue',
          reminderAt: now.subtract(const Duration(days: 2)),
        ),
        _note(
          id: 'recent-overdue',
          reminderAt: now.subtract(const Duration(minutes: 5)),
        ),
      ];

      final result = notesWithActiveOrPendingReminders(notes, now: now);

      expect(result.map((n) => n.id), [
        'oldest-overdue',
        'recent-overdue',
        'soonest-upcoming',
      ]);
    });

    test('excludes an overdue note whose reminder has been resolved', () {
      final notes = [
        _note(
          id: 'resolved',
          reminderAt: now.subtract(const Duration(hours: 1)),
          reminderResolved: true,
        ),
      ];

      expect(notesWithActiveOrPendingReminders(notes, now: now), isEmpty);
    });

    test('still includes an upcoming note even if it is somehow marked '
        'resolved - resolved only means something for a reminder that has '
        'actually fired', () {
      final notes = [
        _note(
          id: 'future-but-resolved',
          reminderAt: now.add(const Duration(hours: 1)),
          reminderResolved: true,
        ),
      ];

      final result = notesWithActiveOrPendingReminders(notes, now: now);

      expect(result.map((n) => n.id), ['future-but-resolved']);
    });

    test('still includes an overdue note that has not been resolved', () {
      final notes = [
        _note(
          id: 'unresolved',
          reminderAt: now.subtract(const Duration(hours: 1)),
        ),
      ];

      final result = notesWithActiveOrPendingReminders(notes, now: now);

      expect(result.map((n) => n.id), ['unresolved']);
    });

    test('a reminder exactly at "now" counts as overdue, not upcoming - so '
        'it is excluded once resolved', () {
      final notes = [
        _note(id: 'right-now', reminderAt: now, reminderResolved: true),
      ];

      expect(notesWithActiveOrPendingReminders(notes, now: now), isEmpty);
    });

    test('an empty note list produces an empty result', () {
      expect(notesWithActiveOrPendingReminders([], now: now), isEmpty);
    });
  });
}
