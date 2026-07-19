import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/widgets/note_card.dart';

Note _note({String title = 'Title', String body = ''}) {
  final now = DateTime.now();
  return Note(
    id: 'note-1',
    title: title,
    body: body,
    colorIndex: 0,
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
  testWidgets(
      'a checklist line renders a real checkbox glyph, not the raw '
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

  testWidgets('an unchecked checklist item has no strikethrough',
      (tester) async {
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

  testWidgets('plain text notes with no checklist syntax render as before',
      (tester) async {
    await _pump(tester, _note(body: 'Just a plain note with no checkboxes'));

    expect(
      find.text('Just a plain note with no checkboxes'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_box), findsNothing);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
  });
}
