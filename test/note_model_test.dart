import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/models/repeat_rule.dart';

Note _note({
  String id = 'n1',
  String title = '',
  String body = '',
  DateTime? reminderAt,
  bool reminderResolved = false,
  RepeatRule? repeatRule,
  int repeatOccurrenceNumber = 1,
  bool pinned = false,
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
    repeatRule: repeatRule,
    repeatOccurrenceNumber: repeatOccurrenceNumber,
    pinned: pinned,
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

  group('noteAfterDismiss', () {
    test('a non-repeating reminder is just marked resolved, reminderAt '
        'unchanged', () {
      final reminderAt = DateTime(2026, 7, 20, 9);
      final note = _note(reminderAt: reminderAt);

      final result = noteAfterDismiss(note);

      expect(result.reminderResolved, isTrue);
      expect(result.reminderAt, reminderAt);
    });

    test('a repeating reminder rolls reminderAt forward and stays '
        'unresolved for the fresh cycle, when dismissed shortly after '
        'firing', () {
      final reminderAt = DateTime.now().subtract(const Duration(minutes: 5));
      final note = _note(
        reminderAt: reminderAt,
        repeatRule: RepeatRule.preset(RepeatFrequency.daily),
      );

      final result = noteAfterDismiss(note);

      expect(result.reminderResolved, isFalse);
      expect(result.reminderAt, reminderAt.add(const Duration(days: 1)));
      expect(result.repeatOccurrenceNumber, 2);
    });

    test('a repeating reminder dismissed several days late skips straight '
        'to the next occurrence that is actually still ahead, not just one '
        'step forward from the original time (which could still be in the '
        'past)', () {
      final reminderAt = DateTime.now().subtract(
        const Duration(days: 3, minutes: 5),
      );
      final note = _note(
        reminderAt: reminderAt,
        repeatRule: RepeatRule.preset(RepeatFrequency.daily),
      );

      final result = noteAfterDismiss(note);

      expect(result.reminderResolved, isFalse);
      expect(result.reminderAt!.isAfter(DateTime.now()), isTrue);
    });

    test('a repeating note with no reminderAt at all is just marked '
        'resolved - nothing to advance', () {
      final note = _note(repeatRule: RepeatRule.preset(RepeatFrequency.daily));

      final result = noteAfterDismiss(note);

      expect(result.reminderResolved, isTrue);
      expect(result.reminderAt, isNull);
    });

    test('a rule that has just run its own course (RepeatEnd reached) is '
        'marked resolved and its repeatRule cleared, same as a '
        'non-repeating reminder from here on', () {
      final reminderAt = DateTime.now().subtract(const Duration(minutes: 5));
      final note = _note(
        reminderAt: reminderAt,
        repeatRule: RepeatRule(
          frequency: RepeatFrequency.daily,
          end: const RepeatEndAfterCount(1),
        ),
        repeatOccurrenceNumber: 1,
      );

      final result = noteAfterDismiss(note);

      expect(result.reminderResolved, isTrue);
      expect(result.repeatRule, isNull);
      // The reminderAt itself is left as whatever it already was - only
      // reminderResolved/repeatRule change once the rule ends.
      expect(result.reminderAt, reminderAt);
    });
  });

  group('Note.repeatRule round-trips', () {
    test('through toMap/fromMap (local storage)', () {
      final rule = RepeatRule(
        frequency: RepeatFrequency.weekly,
        interval: 2,
        weekdays: const {1, 3},
        end: const RepeatEndAfterCount(5),
      );
      final note = _note(repeatRule: rule, repeatOccurrenceNumber: 3);

      final restored = Note.fromMap(note.toMap());

      expect(restored.repeatRule, rule);
      expect(restored.repeatOccurrenceNumber, 3);
    });

    test('a null repeatRule (does not repeat) round-trips as null', () {
      final note = _note();

      final restored = Note.fromMap(note.toMap());

      expect(restored.repeatRule, isNull);
    });

    test('fromMap falls back to no rule and occurrence 1 for a note saved '
        'before these fields existed', () {
      final map = _note().toMap()
        ..remove('repeat_rule')
        ..remove('repeat_occurrence_number');

      final restored = Note.fromMap(map);

      expect(restored.repeatRule, isNull);
      expect(restored.repeatOccurrenceNumber, 1);
    });

    test('through toPocketBase/fromPocketBase (server sync)', () {
      final rule = RepeatRule.preset(RepeatFrequency.yearly);
      final note = _note(repeatRule: rule, repeatOccurrenceNumber: 4);

      final restored = Note.fromPocketBase({
        'id': note.id,
        ...note.toPocketBase(),
      });

      expect(restored.repeatRule, rule);
      expect(restored.repeatOccurrenceNumber, 4);
    });

    test('fromPocketBase falls back to no rule for an empty repeat_rule '
        'value (an un-migrated or untouched server record)', () {
      final restored = Note.fromPocketBase({
        'id': 'n1',
        'repeat_rule': '',
      });

      expect(restored.repeatRule, isNull);
      expect(restored.repeatOccurrenceNumber, 1);
    });
  });

  group('Note.pinned', () {
    test('defaults to false', () {
      expect(_note().pinned, isFalse);
    });

    test('copyWith sets it independently of other fields', () {
      final note = _note(pinned: false);
      final pinned = note.copyWith(pinned: true);

      expect(pinned.pinned, isTrue);
      expect(pinned.title, note.title);
    });

    test('round-trips through toMap/fromMap (local storage)', () {
      final note = _note(pinned: true);

      final restored = Note.fromMap(note.toMap());

      expect(restored.pinned, isTrue);
    });

    test('fromMap falls back to false for a note saved before this field '
        'existed', () {
      final map = _note(pinned: true).toMap()..remove('pinned');

      final restored = Note.fromMap(map);

      expect(restored.pinned, isFalse);
    });

    test('round-trips through toPocketBase/fromPocketBase (server sync)', () {
      final note = _note(pinned: true);

      final restored = Note.fromPocketBase({
        'id': note.id,
        ...note.toPocketBase(),
      });

      expect(restored.pinned, isTrue);
    });

    test('fromPocketBase falls back to false for an un-migrated or '
        'untouched server record with no pinned value', () {
      final restored = Note.fromPocketBase({'id': 'n1'});

      expect(restored.pinned, isFalse);
    });
  });
}
