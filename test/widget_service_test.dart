import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/widget_service.dart';

Note _note({
  required String id,
  String title = '',
  String body = '',
  int colorIndex = 0,
  DateTime? reminderAt,
}) {
  final now = DateTime(2026, 1, 1);
  return Note(
    id: id,
    title: title,
    body: body,
    colorIndex: colorIndex,
    reminderAt: reminderAt,
    created: now,
    updated: now,
  );
}

void main() {
  group('WidgetService.buildReminderListPayload', () {
    final now = DateTime(2026, 7, 20, 12);

    test('excludes notes with no reminder set', () {
      final notes = [
        _note(id: 'a', title: 'No reminder'),
        _note(
          id: 'b',
          title: 'Has one',
          reminderAt: now.add(const Duration(hours: 1)),
        ),
      ];

      final payload = WidgetService.buildReminderListPayload(notes, now: now);

      expect(payload, hasLength(1));
      expect(payload.single['id'], 'b');
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

      final payload = WidgetService.buildReminderListPayload(notes, now: now);

      expect(payload.map((e) => e['id']), [
        'oldest-overdue',
        'recent-overdue',
        'soonest-upcoming',
      ]);
    });

    test('marks a reminder exactly at "now" as overdue, not upcoming', () {
      final notes = [_note(id: 'a', reminderAt: now)];

      final payload = WidgetService.buildReminderListPayload(notes, now: now);

      expect(payload.single['isOverdue'], isTrue);
    });

    test(
      'isOverdue is false for a future reminder and true for a past one',
      () {
        final notes = [
          _note(id: 'future', reminderAt: now.add(const Duration(hours: 1))),
          _note(id: 'past', reminderAt: now.subtract(const Duration(hours: 1))),
        ];

        final payload = WidgetService.buildReminderListPayload(notes, now: now);
        final byId = {for (final e in payload) e['id']: e};

        expect(byId['future']!['isOverdue'], isFalse);
        expect(byId['past']!['isOverdue'], isTrue);
      },
    );

    test('reminderAtMillis matches the note\'s reminderAt exactly', () {
      final reminderAt = now.add(const Duration(hours: 3));
      final notes = [_note(id: 'a', reminderAt: reminderAt)];

      final payload = WidgetService.buildReminderListPayload(notes, now: now);

      expect(
        payload.single['reminderAtMillis'],
        reminderAt.millisecondsSinceEpoch,
      );
    });

    test('an empty note list produces an empty payload', () {
      expect(WidgetService.buildReminderListPayload([], now: now), isEmpty);
    });
  });

  group('WidgetService.buildSingleNoteJson', () {
    test('carries the fields the widget needs to render', () {
      final reminderAt = DateTime(2026, 7, 20, 9);
      final note = _note(
        id: 'note-1',
        title: 'Title',
        body: 'Body text',
        colorIndex: 4,
        reminderAt: reminderAt,
      );

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json, {
        'id': 'note-1',
        'title': 'Title',
        'body': 'Body text',
        'colorIndex': 4,
        'reminderAtMillis': reminderAt.millisecondsSinceEpoch,
      });
    });

    test('reminderAtMillis is null when the note has no reminder', () {
      final note = _note(id: 'note-1', title: 'Title');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['reminderAtMillis'], isNull);
    });
  });
}
