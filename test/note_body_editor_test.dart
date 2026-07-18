import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/widgets/note_body_editor.dart';

void main() {
  group('parseBody / serializeBody', () {
    test('plain text with no checklist lines round-trips unchanged', () {
      const body = 'Just a note.\nWith two lines.';
      final blocks = parseBody(body);

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<TextBodyBlock>());
      expect(serializeBody(blocks), body);
    });

    test('a body that is entirely checklist items parses one block per item',
        () {
      const body = '- [x] Buy milk\n- [ ] Buy eggs\n- [x] Buy bread';
      final blocks = parseBody(body);

      expect(blocks, hasLength(3));
      expect(blocks.whereType<ChecklistBodyBlock>(), hasLength(3));
      expect(serializeBody(blocks), body);
    });

    test('mixes plain text and checklist items in the same note, unlike '
        'Keep\'s all-or-nothing model', () {
      const body =
          'Trip packing list:\n- [x] Passport\n- [ ] Sunscreen\n\n'
          'Remember to charge the camera.';
      final blocks = parseBody(body);

      expect(blocks, hasLength(4));
      expect(blocks[0], isA<TextBodyBlock>());
      expect(blocks[1], isA<ChecklistBodyBlock>());
      expect(blocks[2], isA<ChecklistBodyBlock>());
      expect(blocks[3], isA<TextBodyBlock>());
      expect(
        (blocks[3] as TextBodyBlock).text,
        '\nRemember to charge the camera.', // blank line preserved
      );
      expect(serializeBody(blocks), body);
    });

    test('checked state survives round-trip', () {
      final blocks = parseBody('- [x] done\n- [ ] not done');
      final checklist = blocks.cast<ChecklistBodyBlock>();
      expect(checklist[0].checked, isTrue);
      expect(checklist[1].checked, isFalse);
    });

    test('empty body parses to a single empty text block', () {
      final blocks = parseBody('');
      expect(blocks, hasLength(1));
      expect((blocks.single as TextBodyBlock).text, '');
      expect(serializeBody(blocks), '');
    });

    test('a line that merely looks like a checklist item without the dash '
        'is treated as plain text', () {
      // Deliberately not Markdown task-list syntax ("- [ ] ..."), so it
      // should not be misparsed as a checklist item.
      final blocks = parseBody('[ ] not a checkbox, just brackets');
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<TextBodyBlock>());
    });
  });

  group('NoteBodyEditor widget', () {
    Future<String> pumpEditor(
      WidgetTester tester, {
      required String initialBody,
      required GlobalKey<NoteBodyEditorState> key,
    }) async {
      String latest = initialBody;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: initialBody,
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return latest;
    }

    testWidgets('renders a checkbox for each checklist item and plain text '
        'for the rest', (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      await pumpEditor(
        tester,
        initialBody: 'Heads up:\n- [x] Done thing\n- [ ] Todo thing',
        key: key,
      );

      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.text('Heads up:'), findsOneWidget);
      expect(find.text('Done thing'), findsOneWidget);
      expect(find.text('Todo thing'), findsOneWidget);
    });

    testWidgets('tapping a checkbox toggles it and is reflected on save',
        (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] Buy milk',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(latest, '- [x] Buy milk');
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets(
        'the "Add checklist item" trigger appends a new empty, focused item',
        (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: 'Some notes.',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.addChecklistItem();
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsOneWidget);
      expect(latest, 'Some notes.\n- [ ] ');
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('the remove (x) button deletes a checklist item',
        (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] keep me\n- [ ] remove me',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final removeButtons = find.byIcon(Icons.close);
      expect(removeButtons, findsNWidgets(2));
      await tester.tap(removeButtons.last);
      await tester.pumpAndSettle();

      expect(latest, '- [ ] keep me');
      expect(find.text('remove me'), findsNothing);
    });

    testWidgets(
        'pressing enter inside a checklist item spawns a new item below, '
        "not a newline within the item's own text", (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] first',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate typing a newline into the checklist item's field, as if
      // Enter had been pressed at the end of its text.
      await tester.enterText(find.byType(TextField).last, 'first\nsecond');
      await tester.pumpAndSettle();

      expect(latest, '- [ ] first\n- [ ] second');
      expect(find.byType(Checkbox), findsNWidgets(2));
    });
  });
}
