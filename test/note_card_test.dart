import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/notification_service.dart';
import 'package:jotes/widgets/note_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Note _note({String title = 'Title', String body = '', DateTime? reminderAt}) {
  final now = DateTime.now();
  return Note(
    id: 'note-1',
    title: title,
    body: body,
    colorIndex: 0,
    reminderAt: reminderAt,
    created: now,
    updated: now,
  );
}

Future<void> _pump(WidgetTester tester, Note note) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NoteCard(
          note: note,
          selected: false,
          selectionMode: false,
          onTap: () {},
          onLongPress: () {},
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a checklist line renders a real checkbox glyph, not the raw '
      'markdown syntax', (tester) async {
    await _pump(tester, _note(body: '- [ ] Buy milk'));

    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.textContaining('- [ ]'), findsNothing);
  });

  testWidgets('a checked checklist item shows a filled checkbox and '
      'strikethrough text', (tester) async {
    await _pump(tester, _note(body: '- [x] Done thing'));

    expect(find.byIcon(Icons.check_box), findsOneWidget);
    final text = tester.widget<Text>(find.text('Done thing'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('an unchecked checklist item has no strikethrough', (
    tester,
  ) async {
    await _pump(tester, _note(body: '- [ ] Not done yet'));

    final text = tester.widget<Text>(find.text('Not done yet'));
    expect(text.style?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('mixed plain text and checklist items both render in the '
      'same card', (tester) async {
    await _pump(
      tester,
      _note(body: 'Some notes\n- [ ] First item\n- [x] Second item'),
    );

    expect(find.text('Some notes'), findsOneWidget);
    expect(find.text('First item'), findsOneWidget);
    expect(find.text('Second item'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
  });

  testWidgets('plain text notes with no checklist syntax render as before', (
    tester,
  ) async {
    await _pump(tester, _note(body: 'Just a plain note with no checkboxes'));

    expect(find.text('Just a plain note with no checkboxes'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsNothing);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
  });

  group('reminder chip color (see _ReminderChip)', () {
    Color chipColor(WidgetTester tester) {
      // Not find.byType(Container) alone - NoteCard's own outer container
      // would also match. Closest Container ancestor of the chip's own
      // icon (alarm or alarm_off) is the chip's, not the card's.
      final icon = find.byWidgetPredicate(
        (w) =>
            w is Icon && (w.icon == Icons.alarm || w.icon == Icons.alarm_off),
      );
      final container = tester.widget<Container>(
        find.ancestor(of: icon, matching: find.byType(Container)).first,
      );
      return (container.decoration as BoxDecoration).color!;
    }

    testWidgets('a reminder still in the future is green (untriggered)', (
      tester,
    ) async {
      await _pump(
        tester,
        _note(reminderAt: DateTime.now().add(const Duration(hours: 1))),
      );
      await tester.pumpAndSettle();

      expect(chipColor(tester), Colors.green.withAlpha(40));
    });

    testWidgets('a reminder that fired but was not dismissed/snoozed is amber '
        '(triggered, pending action)', (tester) async {
      await _pump(
        tester,
        _note(reminderAt: DateTime.now().subtract(const Duration(hours: 1))),
      );
      await tester.pumpAndSettle();

      expect(chipColor(tester), Colors.amber.withAlpha(40));
    });

    testWidgets('a reminder that was dismissed/snoozed is red (complete)', (
      tester,
    ) async {
      await NotificationService.instance.markReminderResolved('note-1');
      await _pump(
        tester,
        _note(reminderAt: DateTime.now().subtract(const Duration(hours: 1))),
      );
      await tester.pumpAndSettle();

      expect(chipColor(tester), Colors.red.withAlpha(40));
    });
  });
}
