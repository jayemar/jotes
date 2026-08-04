import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/notification_service.dart';
import 'package:jotes/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  setUp(() {
    // buildReminderListPayload checks NotificationService.isReminderResolved
    // for overdue notes, which touches SharedPreferences.
    SharedPreferences.setMockInitialValues({});
  });

  group('WidgetService.buildReminderListPayload', () {
    final now = DateTime(2026, 7, 20, 12);

    test('excludes notes with no reminder set', () async {
      final notes = [
        _note(id: 'a', title: 'No reminder'),
        _note(
          id: 'b',
          title: 'Has one',
          reminderAt: now.add(const Duration(hours: 1)),
        ),
      ];

      final payload = await WidgetService.buildReminderListPayload(
        notes,
        now: now,
      );

      expect(payload, hasLength(1));
      expect(payload.single['id'], 'b');
    });

    test('sorts oldest-first regardless of input order, mixing overdue and '
        'upcoming into one chronological list', () async {
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

      final payload = await WidgetService.buildReminderListPayload(
        notes,
        now: now,
      );

      expect(payload.map((e) => e['id']), [
        'oldest-overdue',
        'recent-overdue',
        'soonest-upcoming',
      ]);
    });

    test(
      'marks a reminder exactly at "now" as overdue, not upcoming',
      () async {
        final notes = [_note(id: 'a', reminderAt: now)];

        final payload = await WidgetService.buildReminderListPayload(
          notes,
          now: now,
        );

        expect(payload.single['isOverdue'], isTrue);
      },
    );

    test(
      'isOverdue is false for a future reminder and true for a past one',
      () async {
        final notes = [
          _note(id: 'future', reminderAt: now.add(const Duration(hours: 1))),
          _note(id: 'past', reminderAt: now.subtract(const Duration(hours: 1))),
        ];

        final payload = await WidgetService.buildReminderListPayload(
          notes,
          now: now,
        );
        final byId = {for (final e in payload) e['id']: e};

        expect(byId['future']!['isOverdue'], isFalse);
        expect(byId['past']!['isOverdue'], isTrue);
      },
    );

    test("reminderAtMillis matches the note's reminderAt exactly", () async {
      final reminderAt = now.add(const Duration(hours: 3));
      final notes = [_note(id: 'a', reminderAt: reminderAt)];

      final payload = await WidgetService.buildReminderListPayload(
        notes,
        now: now,
      );

      expect(
        payload.single['reminderAtMillis'],
        reminderAt.millisecondsSinceEpoch,
      );
    });

    test('an empty note list produces an empty payload', () async {
      expect(
        await WidgetService.buildReminderListPayload([], now: now),
        isEmpty,
      );
    });

    test('excludes an overdue note whose reminder has been resolved (via '
        'Dismiss or Snooze)', () async {
      final notes = [
        _note(
          id: 'resolved',
          reminderAt: now.subtract(const Duration(hours: 1)),
        ),
      ];
      await NotificationService.instance.markReminderResolved('resolved');

      final payload = await WidgetService.buildReminderListPayload(
        notes,
        now: now,
      );

      expect(payload, isEmpty);
    });

    test('still includes an upcoming note even if it is somehow marked '
        'resolved - resolved only means something for a reminder that has '
        'actually fired', () async {
      final notes = [
        _note(
          id: 'future-but-resolved',
          reminderAt: now.add(const Duration(hours: 1)),
        ),
      ];
      await NotificationService.instance.markReminderResolved(
        'future-but-resolved',
      );

      final payload = await WidgetService.buildReminderListPayload(
        notes,
        now: now,
      );

      expect(payload, hasLength(1));
      expect(payload.single['id'], 'future-but-resolved');
    });

    test('still includes an overdue note that has not been resolved', () async {
      final notes = [
        _note(
          id: 'unresolved',
          reminderAt: now.subtract(const Duration(hours: 1)),
        ),
      ];

      final payload = await WidgetService.buildReminderListPayload(
        notes,
        now: now,
      );

      expect(payload, hasLength(1));
      expect(payload.single['id'], 'unresolved');
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
        'blocks': [
          {'type': 'text', 'text': 'Body text'},
        ],
        'colorIndex': 4,
        'reminderAtMillis': reminderAt.millisecondsSinceEpoch,
      });
    });

    test('reminderAtMillis is null when the note has no reminder', () {
      final note = _note(id: 'note-1', title: 'Title');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['reminderAtMillis'], isNull);
    });

    test('parses checklist syntax into structured blocks - see '
        'SingleNoteWidget.kt, which renders these as real checkbox glyphs '
        'instead of the raw markdown in "body"', () {
      final note = _note(
        id: 'note-1',
        body: 'Intro\n- [ ] Buy milk\n  - [x] Sub-item',
      );

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {'type': 'text', 'text': 'Intro'},
        {
          'type': 'checklist',
          'checked': false,
          'text': 'Buy milk',
          'indent': 0,
        },
        {'type': 'checklist', 'checked': true, 'text': 'Sub-item', 'indent': 1},
      ]);
    });
  });
}
