import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';

Note _note({String title = '', String body = '', DateTime? reminderAt}) {
  final now = DateTime.now();
  return Note(
    id: 'n1',
    title: title,
    body: body,
    reminderAt: reminderAt,
    created: now,
    updated: now,
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
}
