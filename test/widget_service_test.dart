import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/widget_service.dart';

Note _note({
  required String id,
  String title = '',
  String body = '',
  int colorIndex = 0,
  DateTime? reminderAt,
  bool reminderResolved = false,
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
    reminderResolved: reminderResolved,
  );
}

void main() {
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
          reminderResolved: true,
        ),
      ];

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
          reminderResolved: true,
        ),
      ];

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
          {'type': 'text', 'text': 'Body text', 'style': 'plain'},
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
        {'type': 'text', 'text': 'Intro', 'style': 'plain'},
        {
          'type': 'checklist',
          'checked': false,
          'text': 'Buy milk',
          'style': 'plain',
          'indent': 0,
        },
        {
          'type': 'checklist',
          'checked': true,
          'text': 'Sub-item',
          'style': 'plain',
          'indent': 1,
        },
      ]);
    });

    test('folds a plain bullet item back into a "text" block using the '
        'same "•" glyph the in-app preview shows, not the raw "- " '
        'markdown syntax - a numbered item keeps its own literal number, '
        'same as in-app', () {
      final note = _note(id: 'note-1', body: '- Bread\n1. Preheat oven');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {'type': 'text', 'text': '• Bread', 'style': 'plain', 'indent': 0},
        {
          'type': 'text',
          'text': '1. Preheat oven',
          'style': 'plain',
          'indent': 0,
        },
      ]);
    });

    test('a bullet/numbered sub-item keeps its indent, so it renders at the '
        'same visual level as it does in-app rather than flush with its '
        'top-level parent', () {
      final note = _note(
        id: 'note-1',
        body: '- Groceries\n  - Bread\n  1. Preheat oven',
      );

      final json = WidgetService.buildSingleNoteJson(note);

      expect((json['blocks'] as List).map((b) => (b as Map)['indent']), [
        0,
        1,
        1,
      ]);
    });

    test('a text block that is entirely a link has its markdown syntax '
        'stripped to just the label, and style set to "link" - the widget '
        'can style the whole block as a link since Glance has no way to '
        'style just part of one', () {
      final note = _note(
        id: 'note-1',
        body: '[jotes repo](https://example.com/jotes)',
      );

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {'type': 'text', 'text': 'jotes repo', 'style': 'link'},
      ]);
    });

    test('a text block mixing a link with surrounding prose still has the '
        'markdown stripped to its label, but style stays "plain" - Glance '
        'cannot color/underline just the link portion of a mixed line', () {
      final note = _note(
        id: 'note-1',
        body: 'See https://example.com for more.',
      );

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {
          'type': 'text',
          'text': 'See https://example.com for more.',
          'style': 'plain',
        },
      ]);
    });

    test('a text block that is entirely bold has its markdown syntax '
        'stripped and style set to "bold"', () {
      final note = _note(id: 'note-1', body: '**Important**');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {'type': 'text', 'text': 'Important', 'style': 'bold'},
      ]);
    });

    test('a text block that is entirely italic has its markdown syntax '
        'stripped and style set to "italic"', () {
      final note = _note(id: 'note-1', body: '*aside*');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {'type': 'text', 'text': 'aside', 'style': 'italic'},
      ]);
    });

    test('a text block that is entirely strikethrough has its markdown '
        'syntax stripped and style set to "strikethrough"', () {
      final note = _note(id: 'note-1', body: '~~done~~');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {'type': 'text', 'text': 'done', 'style': 'strikethrough'},
      ]);
    });

    test('a text block that is entirely inline code has its markdown '
        'syntax stripped and style set to "code"', () {
      final note = _note(id: 'note-1', body: '`flutter test`');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {'type': 'text', 'text': 'flutter test', 'style': 'code'},
      ]);
    });

    test('a text block mixing formatted and plain text has its markdown '
        'syntax stripped entirely, but style stays "plain" - Glance cannot '
        'style just part of a line', () {
      final note = _note(id: 'note-1', body: 'This is **bold** and *italic*');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {'type': 'text', 'text': 'This is bold and italic', 'style': 'plain'},
      ]);
    });

    test('a checklist item that is entirely bold is styled as such, not '
        'left showing literal asterisks', () {
      final note = _note(id: 'note-1', body: '- [ ] **Urgent**');

      final json = WidgetService.buildSingleNoteJson(note);

      expect(json['blocks'], [
        {
          'type': 'checklist',
          'checked': false,
          'text': 'Urgent',
          'style': 'bold',
          'indent': 0,
        },
      ]);
    });
  });
}
