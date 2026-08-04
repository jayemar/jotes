import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    test(
      'a body that is entirely checklist items parses one block per item',
      () {
        const body = '- [x] Buy milk\n- [ ] Buy eggs\n- [x] Buy bread';
        final blocks = parseBody(body);

        expect(blocks, hasLength(3));
        expect(blocks.whereType<ChecklistBodyBlock>(), hasLength(3));
        expect(serializeBody(blocks), body);
      },
    );

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

    test('2 leading spaces before a checklist line mark it as a sub-item '
        'of the item above, and round-trip back to the same spacing', () {
      const body = '- [ ] top-level\n  - [ ] a sub-item';
      final blocks = parseBody(body).cast<ChecklistBodyBlock>();

      expect(blocks.map((b) => b.indent), [0, 1]);
      expect(serializeBody(blocks), body);
    });

    test('an irregular (odd) leading-space count integer-divides down '
        'instead of crashing or misparsing', () {
      final blocks = parseBody(
        '   - [ ] three spaces',
      ).cast<ChecklistBodyBlock>();
      expect(blocks.single.indent, 1);
    });

    test('leading-space indent beyond one level is clamped - only '
        'top-level items and sub-items are supported, not a deeper '
        'outline', () {
      final deeplyIndented = '${'  ' * 5}- [ ] way too deep';
      final blocks = parseBody(deeplyIndented).cast<ChecklistBodyBlock>();
      expect(blocks.single.indent, maxChecklistIndent);
    });

    test('a bare "- [ ]"/"- [x]" with no trailing space or text is still '
        'recognized as a valid empty checklist item, matching how GitHub '
        'and most other Markdown tools treat it', () {
      final unchecked = parseBody('- [ ]').cast<ChecklistBodyBlock>();
      expect(unchecked.single.checked, isFalse);
      expect(unchecked.single.text, '');

      final checked = parseBody('- [x]').cast<ChecklistBodyBlock>();
      expect(checked.single.checked, isTrue);
      expect(checked.single.text, '');
    });

    test('matchChecklistLine reports the raw prefix length correctly for '
        'both a bare checkbox and one with trailing text - used for '
        'cursor-offset mapping in note_body_view.dart', () {
      final bare = matchChecklistLine('- [ ]')!;
      expect(bare.rawPrefixLength, 5);

      final withText = matchChecklistLine('- [ ] hello')!;
      expect(withText.rawPrefixLength, 6);
    });
  });

  group('applyEnterOnChecklistLine', () {
    test('continues the list when Enter is pressed at the end of a '
        'checklist item with text', () {
      const oldText = '- [ ] Buy milk';
      const newText = '- [ ] Buy milk\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result, isNotNull);
      expect(result!.text, '- [ ] Buy milk\n- [ ] ');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('preserves indent when continuing a sub-item', () {
      const oldText = '- [ ] Top\n  - [ ] Sub';
      const newText = '- [ ] Top\n  - [ ] Sub\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '- [ ] Top\n  - [ ] Sub\n  - [ ] ');
    });

    test('exits the list instead of continuing when the item is empty - '
        'otherwise there would be no way to stop it short of deleting the '
        'marker by hand', () {
      const oldText = '- [ ] Buy milk\n- [ ]';
      const newText = '- [ ] Buy milk\n- [ ]\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '- [ ] Buy milk\n');
      expect(result.selection.baseOffset, '- [ ] Buy milk\n'.length);
    });

    test('exits the list for an empty item with a trailing space too', () {
      const oldText = '- [ ] ';
      const newText = '- [ ] \n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '');
      expect(result.selection.baseOffset, 0);
    });

    test('does nothing when Enter is pressed mid-line rather than at the '
        'end', () {
      const oldText = '- [ ] Buy milk';
      const newText = '- [ ] Buy \nmilk';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: 11,
      );

      expect(result, isNull);
    });

    test('does nothing on a plain (non-checklist) line', () {
      const oldText = 'Just some text';
      const newText = 'Just some text\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result, isNull);
    });

    test('does nothing for edits other than a single newline insertion - '
        'e.g. a multi-character paste', () {
      const oldText = '- [ ] Buy milk';
      const newText = '- [ ] Buy milk\nand eggs';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result, isNull);
    });
  });

  group('applyEnterOnChecklistLine - bullet lists', () {
    test('continues the list with the same marker when Enter is pressed at '
        'the end of a "- " bullet item with text', () {
      const oldText = '- Buy milk';
      const newText = '- Buy milk\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '- Buy milk\n- ');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('continues with "*" rather than switching to "-" when that is the '
        'marker the item already used', () {
      const oldText = '* Buy milk';
      const newText = '* Buy milk\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '* Buy milk\n* ');
    });

    test('preserves indent when continuing an indented bullet', () {
      const oldText = '- Top\n  - Sub';
      const newText = '- Top\n  - Sub\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '- Top\n  - Sub\n  - ');
    });

    test('exits the list instead of continuing when the bullet item is '
        'empty', () {
      const oldText = '- Buy milk\n- ';
      const newText = '- Buy milk\n- \n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '- Buy milk\n');
      expect(result.selection.baseOffset, '- Buy milk\n'.length);
    });

    test('exits the list for a bare marker with no trailing space either', () {
      const oldText = '-';
      const newText = '-\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '');
      expect(result.selection.baseOffset, 0);
    });

    test('does not misfire on a markdown horizontal rule ("---")', () {
      const oldText = '---';
      const newText = '---\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result, isNull);
    });

    test('does not misfire on a hyphenated word with no space after the '
        'dash', () {
      const oldText = '-encrypted';
      const newText = '-encrypted\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result, isNull);
    });
  });

  group('applyEnterOnChecklistLine - numbered lists', () {
    test('continues the list with the next number when Enter is pressed at '
        'the end of a numbered item with text', () {
      const oldText = '1. Buy milk';
      const newText = '1. Buy milk\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '1. Buy milk\n2. ');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('continues from whatever number the line itself has, not a count '
        'of preceding items', () {
      const oldText = '7. Buy milk';
      const newText = '7. Buy milk\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '7. Buy milk\n8. ');
    });

    test('preserves indent when continuing an indented numbered item', () {
      const oldText = '1. Top\n  1. Sub';
      const newText = '1. Top\n  1. Sub\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '1. Top\n  1. Sub\n  2. ');
    });

    test('exits the list instead of continuing when the numbered item is '
        'empty', () {
      const oldText = '1. Buy milk\n2. ';
      const newText = '1. Buy milk\n2. \n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '1. Buy milk\n');
      expect(result.selection.baseOffset, '1. Buy milk\n'.length);
    });

    test('exits the list for a bare "N." with no trailing space either', () {
      const oldText = '1.';
      const newText = '1.\n';
      final result = applyEnterOnChecklistLine(
        oldText: oldText,
        newText: newText,
        newCursorOffset: newText.length,
      );

      expect(result!.text, '');
      expect(result.selection.baseOffset, 0);
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

    testWidgets(
      'a note ending in a bare "- [ ]" (no trailing space or text) renders '
      'a checkbox for it too, not plain text - the original bug report '
      'that prompted this whole view/edit-mode redesign',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        await pumpEditor(
          tester,
          initialBody: 'Words here\n\n- [ ] Thing 1\n- [ ] Thing 2\n- [ ]',
          key: key,
        );

        expect(find.byType(Checkbox), findsNWidgets(3));
      },
    );

    testWidgets('tapping a checkbox toggles it and is reflected on save', (
      tester,
    ) async {
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

    testWidgets('the "Add checklist item" trigger appends a new empty item and '
        'switches to edit mode with the cursor right after it, since a '
        'brand-new item is empty and the user almost certainly wants to '
        'type its text immediately', (tester) async {
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

      // The new checkbox doesn't render until edit mode exits and the
      // body re-parses - while active, edit mode is the raw-text field.
      expect(find.byType(Checkbox), findsNothing);
      expect(key.currentState!.isEditingBody, isTrue);
      expect(latest, 'Some notes.\n- [ ] ');
      expect(tester.testTextInput.isVisible, isTrue);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Some notes.\n- [ ] ');
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 18),
      );
    });

    testWidgets('the remove (x) button deletes a checklist item', (
      tester,
    ) async {
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
      'removing a checklist item that sits between two plain-text blocks '
      'merges them back into one paragraph in the saved body, so a later '
      "edit can backspace across the old boundary like it's a single "
      'paragraph again',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'First\n- [ ] Item\nSecond',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Checkbox), findsOneWidget);
        expect(find.text('First'), findsOneWidget);
        expect(find.text('Second'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.byType(Checkbox), findsNothing);
        expect(latest, 'First\nSecond');

        // Confirm it's genuinely merged into one TextBodyBlock/paragraph
        // (not two adjacent blocks that only look merged) by opening edit
        // mode and checking the raw text has no leftover checklist line.
        await tester.tap(find.textContaining('First'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'First\nSecond');
      },
    );

    testWidgets(
      'typing new "- [ ] text" lines directly in edit mode renders as '
      'separate checklist items once edit mode exits and the body '
      're-parses - there is no per-keystroke handling of arbitrary typed '
      'content, typing the raw markdown is enough (Enter at the end of an '
      'existing checklist line is the one deliberate exception - see the '
      'applyEnterOnChecklistLine tests/the test below this one)',
      (tester) async {
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

        await tester.tap(find.text('first'));
        await tester.pumpAndSettle();
        expect(key.currentState!.isEditingBody, isTrue);

        // Simulates a multi-line paste (or an IME delivering several
        // lines in one change) landing directly in the raw body - no
        // per-keystroke interception needed, unlike the old per-item
        // TextField design.
        await tester.enterText(
          find.byType(TextField),
          '- [ ] first\n- [ ] second\n- [ ] third\n- [ ] fourth',
        );
        key.currentState!.exitEditMode();
        await tester.pumpAndSettle();

        expect(latest, '- [ ] first\n- [ ] second\n- [ ] third\n- [ ] fourth');
        expect(find.byType(Checkbox), findsNWidgets(4));
      },
    );

    testWidgets('pressing Enter at the end of a checklist line in edit mode '
        'continues the list with a fresh checkbox, end to end through the '
        "TextField's own input formatter, not just the pure "
        'applyEnterOnChecklistLine function in isolation', (tester) async {
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

      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '- [ ] first\n');
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '- [ ] first\n- [ ] ',
      );

      key.currentState!.exitEditMode();
      await tester.pumpAndSettle();

      expect(latest, '- [ ] first\n- [ ] ');
      expect(find.byType(Checkbox), findsNWidgets(2));
    });

    testWidgets(
      "dragging a checklist item's drag handle down reorders it within "
      'its run',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: '- [ ] first\n- [ ] second\n- [ ] third',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byIcon(Icons.drag_indicator).at(0),
          const Offset(0, 60),
        );
        await tester.pumpAndSettle();

        expect(latest, '- [ ] second\n- [ ] first\n- [ ] third');
      },
    );

    testWidgets(
      'reordering a checklist item stays within its own contiguous run - '
      'it cannot cross a text paragraph to reach a separate checklist '
      'group',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody:
                    '- [ ] A1\n- [ ] A2\nSeparator\n- [ ] B1\n- [ ] B2',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // A's run only has 2 items, so even a very large downward drag can
        // only ever swap A1 and A2 - it has no way to reach the B run past
        // the "Separator" paragraph.
        await tester.drag(
          find.byIcon(Icons.drag_indicator).at(0),
          const Offset(0, 500),
        );
        await tester.pumpAndSettle();

        expect(latest, '- [ ] A2\n- [ ] A1\nSeparator\n- [ ] B1\n- [ ] B2');
      },
    );

    testWidgets(
      'dragging a checklist item\'s drag handle to the right makes it a '
      "sub-item of whatever's above it - a single drag doing both the "
      'reorder and the indent, like Keep',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: '- [ ] parent\n- [ ] child',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byIcon(Icons.drag_indicator).at(1),
          const Offset(25, 0),
        );
        await tester.pumpAndSettle();

        expect(latest, '- [ ] parent\n  - [ ] child');
      },
    );

    testWidgets(
      'dragging an already-indented item\'s handle to the left removes it '
      'from its parent',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: '- [ ] parent\n  - [ ] child',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byIcon(Icons.drag_indicator).at(1),
          const Offset(-25, 0),
        );
        await tester.pumpAndSettle();

        expect(latest, '- [ ] parent\n- [ ] child');
      },
    );

    testWidgets(
      "a run's first item can't be dragged into a sub-item, since there's "
      'nothing above it to attach to',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        const initialBody = '- [ ] only item so far';
        String latest = '';
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

        await tester.drag(
          find.byIcon(Icons.drag_indicator).first,
          const Offset(25, 0),
        );
        await tester.pumpAndSettle();

        expect(latest, initialBody);
      },
    );

    testWidgets('indent cannot be dragged past one level', (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] parent\n  - [ ] child',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byIcon(Icons.drag_indicator).at(1),
        const Offset(100, 0),
      );
      await tester.pumpAndSettle();

      expect(latest, '- [ ] parent\n  - [ ] child');
    });

    testWidgets('indent cannot be dragged below 0', (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      const initialBody = '- [ ] item';
      String latest = '';
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

      await tester.drag(
        find.byIcon(Icons.drag_indicator).first,
        const Offset(-100, 0),
      );
      await tester.pumpAndSettle();

      expect(latest, initialBody);
    });

    testWidgets(
      'removing the top-level item a sub-item depended on un-indents the '
      'now-orphaned sub-item',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: '- [ ] parent\n  - [ ] child',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.close).first);
        await tester.pumpAndSettle();

        expect(latest, '- [ ] child');
      },
    );

    testWidgets("dragging an indented item's handle to the front of its run "
        'un-indents it, since it would otherwise have nothing above it', (
      tester,
    ) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] parent\n  - [ ] child',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byIcon(Icons.drag_indicator).at(1),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      expect(latest, '- [ ] child\n- [ ] parent');
    });

    testWidgets(
      'removing a checklist item copies the full "- [ ] text" markdown '
      'line to the clipboard, not just the bare text, so pasting it '
      'elsewhere still renders as a checkbox',
      (tester) async {
        final clipboardCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        final key = GlobalKey<NoteBodyEditorState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: '- [ ] copy my text',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(clipboardCalls, hasLength(1));
        expect(
          (clipboardCalls.single.arguments as Map)['text'],
          '- [ ] copy my text',
        );
      },
    );

    testWidgets(
      'the copied markdown line preserves checked state and indent too',
      (tester) async {
        final clipboardCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        final key = GlobalKey<NoteBodyEditorState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: '- [ ] parent\n  - [x] done sub-item',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();

        expect(clipboardCalls, hasLength(1));
        expect(
          (clipboardCalls.single.arguments as Map)['text'],
          '  - [x] done sub-item',
        );
      },
    );

    testWidgets('canUndo is false with nothing to undo yet', (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] item',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.canUndo, isFalse);
    });

    testWidgets('undo reverts a checkbox toggle', (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] item',
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
      expect(latest, '- [x] item');

      key.currentState!.undo();
      await tester.pumpAndSettle();

      expect(latest, '- [ ] item');
      expect(key.currentState!.canUndo, isFalse);
    });

    testWidgets('undo restores a deleted checklist item, including its '
        'position', (tester) async {
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

      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      expect(latest, '- [ ] keep me');

      key.currentState!.undo();
      await tester.pumpAndSettle();

      expect(latest, '- [ ] keep me\n- [ ] remove me');
    });

    testWidgets('undo reverts a drag-handle reorder/indent', (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] parent\n- [ ] child',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byIcon(Icons.drag_indicator).at(1),
        const Offset(25, 0),
      );
      await tester.pumpAndSettle();
      expect(latest, '- [ ] parent\n  - [ ] child');

      key.currentState!.undo();
      await tester.pumpAndSettle();

      expect(latest, '- [ ] parent\n- [ ] child');
    });

    testWidgets('multiple undos in sequence revert multiple steps, not '
        'just the last one', (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: '- [ ] first\n- [ ] second\n- [ ] third',
              textColor: Colors.black,
              hintColor: Colors.black38,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Three separate structural changes in a row.
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close).at(2));
      await tester.pumpAndSettle();
      expect(latest, '- [x] first\n- [x] second');

      key.currentState!.undo();
      await tester.pumpAndSettle();
      expect(latest, '- [x] first\n- [x] second\n- [ ] third');

      key.currentState!.undo();
      await tester.pumpAndSettle();
      expect(latest, '- [x] first\n- [ ] second\n- [ ] third');

      key.currentState!.undo();
      await tester.pumpAndSettle();
      expect(latest, '- [ ] first\n- [ ] second\n- [ ] third');
      expect(key.currentState!.canUndo, isFalse);
    });

    testWidgets('undo with nothing to undo is a harmless no-op', (
      tester,
    ) async {
      final key = GlobalKey<NoteBodyEditorState>();
      const initialBody = '- [ ] item';
      String latest = '';
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

      key.currentState!.undo();
      await tester.pumpAndSettle();

      expect(latest, '');
      expect(key.currentState!.canUndo, isFalse);
    });

    group('view/edit mode switching', () {
      testWidgets('tapping a paragraph enters edit mode with the cursor '
          'near the tapped position, not just at the start or end', (
        tester,
      ) async {
        final key = GlobalKey<NoteBodyEditorState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'abcdefghij',
                textColor: Colors.black,
                hintColor: Colors.black38,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(key.currentState!.isEditingBody, isFalse);

        final textBox = tester.getRect(find.text('abcdefghij'));
        await tester.tapAt(Offset(textBox.left + 2, textBox.top + 8));
        await tester.pumpAndSettle();

        expect(key.currentState!.isEditingBody, isTrue);
        expect(
          tester.testTextInput.editingState?['selectionBase'],
          lessThan(10),
        );
      });

      testWidgets(
        'tapping blank space below the last block enters edit mode with '
        'the cursor at the very end',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          const body = '- [ ] only item';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: body,
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  onChanged: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Tap well below the single checklist row, inside the ListView
          // but past its content.
          await tester.tapAt(
            tester.getTopLeft(find.byType(ListView)) + const Offset(10, 300),
          );
          await tester.pumpAndSettle();

          expect(key.currentState!.isEditingBody, isTrue);
          expect(
            tester.testTextInput.editingState?['selectionBase'],
            body.length,
          );
        },
      );

      testWidgets('losing focus returns to view mode and re-parses the '
          'latest text', (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const TextField(key: Key('elsewhere')),
                  Expanded(
                    child: NoteBodyEditor(
                      key: key,
                      initialBody: 'plain text',
                      textColor: Colors.black,
                      hintColor: Colors.black38,
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('plain text'));
        await tester.pumpAndSettle();
        expect(key.currentState!.isEditingBody, isTrue);

        await tester.enterText(find.byType(TextField).last, '- [ ] now a task');
        await tester.tap(find.byKey(const Key('elsewhere')));
        await tester.pumpAndSettle();

        expect(key.currentState!.isEditingBody, isFalse);
        expect(find.byType(Checkbox), findsOneWidget);
        expect(find.text('now a task'), findsOneWidget);
      });

      testWidgets(
        'tapping blank space below the text while already in edit mode '
        'still moves the cursor there, not just when entering edit mode '
        'from view - regression test for the edit-mode TextField not '
        'filling its available space without expands:true, which left '
        'anywhere below a short note untappable',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: NoteBodyEditor(
                        key: key,
                        initialBody: 'short',
                        textColor: Colors.black,
                        hintColor: Colors.black38,
                        onChanged: (_) {},
                        autofocusFirst: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(key.currentState!.isEditingBody, isTrue);

          // Tap near the bottom-right corner of the field's Expanded box -
          // well below and to the right of where the single short line of
          // text actually renders (top-aligned) - simulating "clicking
          // anywhere in the note area" rather than precisely on the
          // rendered text. Before the fix, a tap out here landed on empty
          // space outside the field's undersized hit area and did nothing;
          // now it resolves to the nearest text position, the end of
          // "short".
          final fieldBox = tester.getRect(find.byType(TextField));
          await tester.tapAt(Offset(fieldBox.right - 10, fieldBox.bottom - 10));
          await tester.pumpAndSettle();

          expect(tester.testTextInput.editingState?['selectionBase'], 5);
        },
      );

      testWidgets(
        'tapping anywhere in an empty note (not just directly on the "Note" '
        'hint text) enters edit mode - regression test for the view-mode '
        'empty-body placeholder not filling its available space, which '
        'left everywhere except that one word untappable',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: NoteBodyEditor(
                        key: key,
                        initialBody: '',
                        textColor: Colors.black,
                        hintColor: Colors.black38,
                        onChanged: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(key.currentState!.isEditingBody, isFalse);

          // Tap near the bottom-right corner of the Expanded box - well
          // away from where the "Note" hint text itself renders (top-left,
          // after the fix - previously centered, but nowhere near this
          // corner either way).
          final viewBox = tester.getRect(find.byType(NoteBodyEditor));
          await tester.tapAt(Offset(viewBox.right - 10, viewBox.bottom - 10));
          await tester.pumpAndSettle();

          expect(key.currentState!.isEditingBody, isTrue);
          expect(tester.testTextInput.editingState?['selectionBase'], 0);
        },
      );

      testWidgets(
        'toggling a checkbox, dragging a handle, and deleting an item all '
        'stay in view mode - only tapping into text (or the blank space '
        'below it, or Add checklist item) switches to edit mode',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: '- [ ] first\n- [ ] second',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  onChanged: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byType(Checkbox).first);
          await tester.pumpAndSettle();
          expect(key.currentState!.isEditingBody, isFalse);

          await tester.drag(
            find.byIcon(Icons.drag_indicator).first,
            const Offset(0, 60),
          );
          await tester.pumpAndSettle();
          expect(key.currentState!.isEditingBody, isFalse);

          await tester.tap(find.byIcon(Icons.close).first);
          await tester.pumpAndSettle();
          expect(key.currentState!.isEditingBody, isFalse);
        },
      );
    });
  });
}
