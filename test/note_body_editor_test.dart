import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/services/link_service.dart';
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

  group('parseBody / serializeBody - bullet lists', () {
    test('"- text" and "* text" lines each parse as their own '
        'BulletBodyBlock, round-tripping with their own original marker',
        () {
      const body = '- dash bullet\n* star bullet';
      final blocks = parseBody(body);

      expect(blocks, hasLength(2));
      expect(blocks.whereType<BulletBodyBlock>(), hasLength(2));
      expect((blocks[0] as BulletBodyBlock).text, 'dash bullet');
      expect((blocks[1] as BulletBodyBlock).text, 'star bullet');
      // serializeBody always writes "-" regardless of the original marker -
      // same "doesn't remember which literal spelling was used" trade-off
      // as everything else here (e.g. checklist doesn't remember 2 vs 4
      // spaces of indent, just how many *levels*).
      expect(serializeBody(blocks), '- dash bullet\n- star bullet');
    });

    test('mixes plain text, checklist items, and plain bullets in the same '
        'note', () {
      const body = 'Groceries:\n- [x] Milk\n- Bread\n- Eggs';
      final blocks = parseBody(body);

      expect(blocks, hasLength(4));
      expect(blocks[0], isA<TextBodyBlock>());
      expect(blocks[1], isA<ChecklistBodyBlock>());
      expect(blocks[2], isA<BulletBodyBlock>());
      expect(blocks[3], isA<BulletBodyBlock>());
      expect(serializeBody(blocks), body);
    });

    test('a bare "-"/"*" with no trailing space or text is still '
        'recognized as a valid empty bullet, same as a bare checklist '
        'marker', () {
      final dash = parseBody('-').cast<BulletBodyBlock>();
      expect(dash.single.text, '');

      final star = parseBody('*').cast<BulletBodyBlock>();
      expect(star.single.text, '');
    });

    test('2 leading spaces before a bullet line mark it as a sub-item, and '
        'round-trip back to the same spacing', () {
      const body = '- top-level\n  - a sub-item';
      final blocks = parseBody(body).cast<BulletBodyBlock>();

      expect(blocks.map((b) => b.indent), [0, 1]);
      expect(serializeBody(blocks), body);
    });
  });

  group('parseBody / serializeBody - numbered lists', () {
    test('"N. text" lines each parse as their own NumberedBodyBlock, '
        'preserving the exact written number rather than renumbering', () {
      const body = '1. First\n1. Also written as 1\n3. Skipped to 3';
      final blocks = parseBody(body).cast<NumberedBodyBlock>();

      expect(blocks.map((b) => b.number), [1, 1, 3]);
      expect(blocks.map((b) => b.text), ['First', 'Also written as 1', 'Skipped to 3']);
      expect(serializeBody(blocks), body);
    });

    test('mixes plain text and numbered items in the same note', () {
      const body = 'Steps:\n1. Preheat oven\n2. Mix batter\n\nDone.';
      final blocks = parseBody(body);

      expect(blocks, hasLength(4));
      expect(blocks[0], isA<TextBodyBlock>());
      expect(blocks[1], isA<NumberedBodyBlock>());
      expect(blocks[2], isA<NumberedBodyBlock>());
      expect(blocks[3], isA<TextBodyBlock>());
      expect(serializeBody(blocks), body);
    });

    test('a bare "N." with no trailing space or text is still recognized '
        'as a valid empty numbered item', () {
      final blocks = parseBody('1.').cast<NumberedBodyBlock>();
      expect(blocks.single.number, 1);
      expect(blocks.single.text, '');
    });

    test('a decimal number that is not actually a list marker (nothing '
        'after it but more digits, no space) is treated as plain text - '
        'e.g. "3.14 is pi" should not be misread as a numbered item', () {
      final blocks = parseBody('3.14 is pi');
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<TextBodyBlock>());
    });

    test('2 leading spaces before a numbered line mark it as a sub-item, '
        'and round-trip back to the same spacing', () {
      const body = '1. top-level\n  1. a sub-item';
      final blocks = parseBody(body).cast<NumberedBodyBlock>();

      expect(blocks.map((b) => b.indent), [0, 1]);
      expect(serializeBody(blocks), body);
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

  group('matchAnyLineMarker', () {
    test('matches a checklist line', () {
      final match = matchAnyLineMarker('- [ ] Buy milk')!;
      expect(match.text, 'Buy milk');
      expect(match.rawPrefixLength, 6);
    });

    test('matches a bullet line', () {
      final match = matchAnyLineMarker('- Buy milk')!;
      expect(match.text, 'Buy milk');
      expect(match.rawPrefixLength, 2);
    });

    test('matches a numbered line', () {
      final match = matchAnyLineMarker('1. Buy milk')!;
      expect(match.text, 'Buy milk');
      expect(match.rawPrefixLength, 3);
    });

    test('returns null for plain text', () {
      expect(matchAnyLineMarker('Just some text'), isNull);
    });
  });

  group('toggleLineMarker', () {
    test('adds the marker to a plain-text line, placing the cursor right '
        'after it, unchanged relative to the line\'s own text', () {
      const text = 'Buy milk';
      final result = toggleLineMarker(
        text: text,
        cursorOffset: 0,
        marker: '- [ ] ',
      );
      expect(result.text, '- [ ] Buy milk');
      expect(result.selection.baseOffset, '- [ ] '.length);
    });

    test('removes the marker when the line already uses that exact one, '
        'back to plain text', () {
      const text = '- [ ] Buy milk';
      final result = toggleLineMarker(
        text: text,
        cursorOffset: text.length,
        marker: '- [ ] ',
      );
      expect(result.text, 'Buy milk');
      expect(result.selection.baseOffset, 'Buy milk'.length);
    });

    test('switches to the new marker when the line already uses a '
        'different one, rather than stacking both', () {
      const text = '- Buy milk';
      final result = toggleLineMarker(
        text: text,
        cursorOffset: text.length,
        marker: '- [ ] ',
      );
      expect(result.text, '- [ ] Buy milk');
    });

    test('a numbered line switched to a checklist item drops the digits '
        'too, not just the ". "', () {
      const text = '1. Buy milk';
      final result = toggleLineMarker(
        text: text,
        cursorOffset: text.length,
        marker: '- [ ] ',
      );
      expect(result.text, '- [ ] Buy milk');
    });

    test('only the line the cursor is on is affected, not the whole body',
        () {
      const text = 'First line\nSecond line\nThird line';
      final cursor = text.indexOf('Second');
      final result = toggleLineMarker(
        text: text,
        cursorOffset: cursor,
        marker: '- ',
      );
      expect(result.text, 'First line\n- Second line\nThird line');
    });

    test('preserves leading indent', () {
      const text = '  - [ ] Sub-item';
      final result = toggleLineMarker(
        text: text,
        cursorOffset: text.length,
        marker: '- [ ] ',
      );
      expect(result.text, '  Sub-item');
    });

    test('keeps the cursor anchored to the same character of the line\'s '
        'own text, not a now-stale raw offset, when the marker length '
        'changes', () {
      // Cursor sits right after "Buy" in "- Buy milk" (offset 5) - after
      // switching to "- [ ] ", it should still sit right after "Buy" in
      // "- [ ] Buy milk" (offset 9), not still at raw offset 5 (which
      // would now land inside the new marker itself).
      const text = '- Buy milk';
      final result = toggleLineMarker(
        text: text,
        cursorOffset: text.indexOf('Buy') + 3,
        marker: '- [ ] ',
      );
      expect(result.selection.baseOffset, result.text.indexOf('Buy') + 3);
    });
  });

  group('swapLine', () {
    test('moves the current line up past its neighbor', () {
      const text = 'First\nSecond\nThird';
      final result = swapLine(
        text: text,
        cursorOffset: text.indexOf('Second'),
        direction: -1,
      )!;
      expect(result.text, 'Second\nFirst\nThird');
    });

    test('moves the current line down past its neighbor', () {
      const text = 'First\nSecond\nThird';
      final result = swapLine(
        text: text,
        cursorOffset: text.indexOf('Second'),
        direction: 1,
      )!;
      expect(result.text, 'First\nThird\nSecond');
    });

    test('returns null when already the first line and moving up', () {
      const text = 'First\nSecond';
      final result = swapLine(
        text: text,
        cursorOffset: text.indexOf('First'),
        direction: -1,
      );
      expect(result, isNull);
    });

    test('returns null when already the last line and moving down', () {
      const text = 'First\nSecond';
      final result = swapLine(
        text: text,
        cursorOffset: text.indexOf('Second'),
        direction: 1,
      );
      expect(result, isNull);
    });

    test('keeps the cursor on the same character of the moved line\'s own '
        'text, following it to its new position', () {
      const text = 'First\nSecond\nThird';
      // Cursor right after "Sec" in "Second" (2 chars into that line).
      final cursor = text.indexOf('Second') + 3;
      final result = swapLine(text: text, cursorOffset: cursor, direction: -1)!;
      final newLineStart = result.text.indexOf('Second');
      expect(result.selection.baseOffset, newLineStart + 3);
    });

    test('list markers move with their line, not left behind', () {
      const text = '- [ ] First\nPlain second';
      final result = swapLine(
        text: text,
        cursorOffset: 0,
        direction: 1,
      )!;
      expect(result.text, 'Plain second\n- [ ] First');
    });
  });

  group('cutLineAt', () {
    test('removes the current line along with its own trailing newline, '
        'closing the gap with the line below', () {
      const text = 'First\nSecond\nThird';
      final result = cutLineAt(
        text: text,
        cursorOffset: text.indexOf('Second'),
      );
      expect(result.value.text, 'First\nThird');
      expect(result.cutText, 'Second');
    });

    test('cutting the last line removes the preceding newline instead, so '
        'no blank line is left dangling at the end', () {
      const text = 'First\nSecond\nThird';
      final result = cutLineAt(
        text: text,
        cursorOffset: text.indexOf('Third'),
      );
      expect(result.value.text, 'First\nSecond');
      expect(result.cutText, 'Third');
    });

    test('cutting the only line in the note leaves it empty', () {
      const text = 'Only line';
      final result = cutLineAt(text: text, cursorOffset: 3);
      expect(result.value.text, '');
      expect(result.cutText, 'Only line');
    });

    test('the returned cutText is the full raw line, list marker included, '
        'so pasting it elsewhere still renders as a checklist item', () {
      const text = '- [x] Buy milk\nPlain line';
      final result = cutLineAt(text: text, cursorOffset: 0);
      expect(result.cutText, '- [x] Buy milk');
      expect(result.value.text, 'Plain line');
    });

    test('the cursor lands at the start of whatever line now occupies '
        'that position', () {
      const text = 'First\nSecond\nThird';
      final result = cutLineAt(
        text: text,
        cursorOffset: text.indexOf('Second') + 3,
      );
      expect(result.value.selection.baseOffset, result.value.text.indexOf('Third'));
    });
  });

  group('insertTextAt', () {
    test('inserts at a collapsed cursor, without touching the rest of the '
        'text', () {
      const text = 'Hello world';
      final result = insertTextAt(
        text: text,
        selection: const TextSelection.collapsed(offset: 5),
        insertion: ' there',
      );
      expect(result.text, 'Hello there world');
    });

    test('replaces an active selection rather than inserting alongside it', () {
      const text = 'Hello world';
      final result = insertTextAt(
        text: text,
        selection: const TextSelection(baseOffset: 6, extentOffset: 11),
        insertion: 'jotes',
      );
      expect(result.text, 'Hello jotes');
    });

    test('the cursor lands right after the inserted text', () {
      const text = 'Hello world';
      final result = insertTextAt(
        text: text,
        selection: const TextSelection.collapsed(offset: 5),
        insertion: ' there',
      );
      expect(result.selection, const TextSelection.collapsed(offset: 11));
    });

    test('inserting multi-line text is a plain string splice, not special-'
        'cased list-marker handling - that only applies to typed Enter '
        'keypresses (see applyEnterOnChecklistLine)', () {
      const text = 'Before\nAfter';
      final result = insertTextAt(
        text: text,
        selection: const TextSelection.collapsed(offset: 6),
        insertion: '\n- [ ] pasted item',
      );
      expect(result.text, 'Before\n- [ ] pasted item\nAfter');
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
              linkColor: Colors.blue,
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
      'renders a bullet glyph ("•") for a plain "- "/"* " list item, not '
      'the raw markdown syntax',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        await pumpEditor(
          tester,
          initialBody: 'Shopping:\n- Bread\n* Eggs',
          key: key,
        );

        expect(find.text('•'), findsNWidgets(2));
        expect(find.text('Shopping:'), findsOneWidget);
        expect(find.text('Bread'), findsOneWidget);
        expect(find.text('Eggs'), findsOneWidget);
        // The raw markers themselves are never shown as part of the text.
        expect(find.textContaining('- Bread'), findsNothing);
        expect(find.textContaining('* Eggs'), findsNothing);
      },
    );

    testWidgets(
      'renders the literal number for a "N. " numbered list item, not '
      'the raw markdown syntax',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        await pumpEditor(
          tester,
          initialBody: 'Steps:\n1. Preheat\n2. Bake',
          key: key,
        );

        expect(find.text('1.'), findsOneWidget);
        expect(find.text('2.'), findsOneWidget);
        expect(find.text('Preheat'), findsOneWidget);
        expect(find.text('Bake'), findsOneWidget);
        expect(find.textContaining('1. Preheat'), findsNothing);
      },
    );

    testWidgets(
      'a double-digit numbered marker ("10.") renders on a single line, '
      'not wrapped across several - regression test for a fixed-width '
      'marker column that only had room for a bullet/single digit',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        await pumpEditor(
          tester,
          initialBody: List.generate(10, (i) => '${i + 1}. Item ${i + 1}')
              .join('\n'),
          key: key,
        );

        expect(find.text('10.'), findsOneWidget);
        // A single-line "10." and a single-line "1." (same font size) have
        // the same rendered height - if "10." had wrapped onto multiple
        // lines instead, its height would be a multiple of that.
        expect(
          tester.getSize(find.text('10.')).height,
          tester.getSize(find.text('1.')).height,
        );
      },
    );

    testWidgets(
      'tapping a bullet/numbered item\'s text switches to edit mode with '
      'the cursor at the tapped text offset, same as tapping a plain-text '
      'paragraph',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        await pumpEditor(
          tester,
          initialBody: '- Bread',
          key: key,
        );

        await tester.tap(find.text('Bread'));
        await tester.pumpAndSettle();

        expect(key.currentState!.isEditingBody, isTrue);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, '- Bread');
      },
    );

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
              linkColor: Colors.blue,
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

    group('checking an item sinks it to the bottom (see _toggleChecked)', () {
      testWidgets(
        'checking the top item moves it below the still-unchecked ones',
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
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byType(Checkbox).at(0));
          await tester.pumpAndSettle();

          expect(latest, '- [ ] second\n- [ ] third\n- [x] first');
        },
      );

      testWidgets(
        'unchecking an already-checked item does not move it - it stays '
        'wherever it currently is until manually reordered',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          String latest = '';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: '- [ ] first\n- [x] second\n- [ ] third',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // "second" is the checked one - unchecking it.
          await tester.tap(find.byType(Checkbox).at(1));
          await tester.pumpAndSettle();

          expect(latest, '- [ ] first\n- [ ] second\n- [ ] third');
        },
      );

      testWidgets(
        'checking an item already at the bottom of its run is a no-op '
        'positionally - it was already there',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          String latest = '';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: '- [ ] first\n- [ ] second',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byType(Checkbox).at(1)); // "second"
          await tester.pumpAndSettle();

          expect(latest, '- [ ] first\n- [x] second');
        },
      );

      testWidgets(
        'checking an item never crosses into a separate checklist run - '
        'it sinks to the bottom of its own run, not the very end of the '
        'note',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          String latest = '';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody:
                      '- [ ] first\n- [ ] second\n'
                      'A paragraph in between.\n'
                      '- [ ] third',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byType(Checkbox).at(0)); // "first"
          await tester.pumpAndSettle();

          expect(
            latest,
            '- [ ] second\n- [x] first\n'
            'A paragraph in between.\n'
            '- [ ] third',
          );
        },
      );

      testWidgets(
        'checking a top-level item with a sub-item under it un-indents '
        'the now-orphaned sub-item, same as deleting/dragging its parent '
        'away already does',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          String latest = '';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: '- [ ] parent\n  - [ ] sub-item\n- [ ] other',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byType(Checkbox).at(0)); // "parent"
          await tester.pumpAndSettle();

          expect(
            latest,
            '- [ ] sub-item\n- [ ] other\n- [x] parent',
          );
        },
      );
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
              linkColor: Colors.blue,
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

    testWidgets('the "Add list item" trigger appends a new empty bullet and '
        'switches to edit mode with the cursor right after it, same as '
        '"Add checklist item" but with a plain "- " marker instead of a '
        'checkbox', (tester) async {
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
              linkColor: Colors.blue,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.addBulletItem();
      await tester.pumpAndSettle();

      expect(key.currentState!.isEditingBody, isTrue);
      expect(latest, 'Some notes.\n- ');
      expect(tester.testTextInput.isVisible, isTrue);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Some notes.\n- ');
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 14),
      );
    });

    testWidgets(
      'toggleChecklistLine adds a checklist marker to the line currently '
      'being edited, in place, rather than appending a new item at the end',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'Buy milk\nSecond line',
                textColor: Colors.black,
                hintColor: Colors.black38,
                linkColor: Colors.blue,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Cursor at offset 0, on the first line ("Buy milk").
        key.currentState!.focusBody();
        await tester.pumpAndSettle();

        key.currentState!.toggleChecklistLine();
        await tester.pumpAndSettle();

        expect(latest, '- [ ] Buy milk\nSecond line');
        expect(key.currentState!.isEditingBody, isTrue);
      },
    );

    testWidgets(
      'toggleChecklistLine tapped again on the same (now checklist) line '
      'removes the marker, back to plain text',
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
                linkColor: Colors.blue,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        key.currentState!.focusBody();
        await tester.pumpAndSettle();
        key.currentState!.toggleChecklistLine();
        await tester.pumpAndSettle();

        expect(latest, 'Buy milk');
      },
    );

    testWidgets(
      'toggleBulletLine while not currently editing falls back to '
      'appending a new empty bullet at the end - there is no "current '
      'line" to toggle without an active cursor',
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
                linkColor: Colors.blue,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(key.currentState!.isEditingBody, isFalse);
        key.currentState!.toggleBulletLine();
        await tester.pumpAndSettle();

        expect(latest, 'Some notes.\n- ');
        expect(key.currentState!.isEditingBody, isTrue);
      },
    );

    testWidgets('moveLineUp swaps the currently-edited line with the one '
        'above it', (tester) async {
      final key = GlobalKey<NoteBodyEditorState>();
      String latest = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBodyEditor(
              key: key,
              initialBody: 'First\nSecond',
              textColor: Colors.black,
              hintColor: Colors.black38,
              linkColor: Colors.blue,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // focusBody() enters edit mode with the cursor at offset 0, on
      // "First" - move it onto "Second" the same way a user placing the
      // cursor there would, by driving the rendered field's own selection.
      key.currentState!.focusBody();
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(
        offset: 'First\nSecond'.length,
      );
      await tester.pumpAndSettle();

      key.currentState!.moveLineUp();
      await tester.pumpAndSettle();

      expect(latest, 'Second\nFirst');
    });

    testWidgets(
      'moveLineUp/moveLineDown are a no-op while not currently editing - '
      'there is no "current line" without an active cursor',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'First\nSecond',
                textColor: Colors.black,
                hintColor: Colors.black38,
                linkColor: Colors.blue,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(key.currentState!.isEditingBody, isFalse);
        key.currentState!.moveLineUp();
        key.currentState!.moveLineDown();
        await tester.pumpAndSettle();

        expect(latest, isEmpty); // onChanged never fired
        expect(key.currentState!.isEditingBody, isFalse);
      },
    );

    group('cutLine', () {
      testWidgets(
        'removes the currently-edited line and copies it to the clipboard',
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
            () =>
                tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                  SystemChannels.platform,
                  null,
                ),
          );

          final key = GlobalKey<NoteBodyEditorState>();
          String latest = '';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: 'First\nSecond\nThird',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          key.currentState!.focusBody();
          await tester.pumpAndSettle();
          final controller = tester
              .widget<TextField>(find.byType(TextField))
              .controller!;
          controller.selection = TextSelection.collapsed(
            offset: 'First\n'.length,
          );
          await tester.pumpAndSettle();

          key.currentState!.cutLine();
          await tester.pumpAndSettle();

          expect(latest, 'First\nThird');
          expect(clipboardCalls, hasLength(1));
          expect(
            (clipboardCalls.single.arguments as Map)['text'],
            'Second',
          );
        },
      );

      testWidgets(
        'is a no-op while not currently editing - there is no "current '
        'line" without an active cursor',
        (tester) async {
          final key = GlobalKey<NoteBodyEditorState>();
          String latest = '';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: 'First\nSecond',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          key.currentState!.cutLine();
          await tester.pumpAndSettle();

          expect(latest, isEmpty);
        },
      );

      testWidgets(
        'pushes an undo snapshot, so undo() (the same general undo used '
        'for checklist changes - see NoteToolbarTool.undo) restores the '
        'cut line, cursor and all, without leaving edit mode',
        (tester) async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
          addTearDown(
            () =>
                tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                  SystemChannels.platform,
                  null,
                ),
          );

          final key = GlobalKey<NoteBodyEditorState>();
          String latest = '';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: 'First\nSecond\nThird',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          key.currentState!.focusBody();
          await tester.pumpAndSettle();
          final controller = tester
              .widget<TextField>(find.byType(TextField))
              .controller!;
          final cursorBeforeCut = 'First\n'.length;
          controller.selection = TextSelection.collapsed(
            offset: cursorBeforeCut,
          );
          await tester.pumpAndSettle();

          expect(key.currentState!.canUndo, isFalse);
          key.currentState!.cutLine();
          await tester.pumpAndSettle();
          expect(latest, 'First\nThird');
          expect(key.currentState!.canUndo, isTrue);

          key.currentState!.undo();
          await tester.pumpAndSettle();

          expect(latest, 'First\nSecond\nThird');
          // Still in edit mode, with the TextField's own controller
          // reflecting the restored text and cursor - not just
          // NoteBodyEditor.onChanged's own latest value.
          expect(key.currentState!.isEditingBody, isTrue);
          expect(controller.text, 'First\nSecond\nThird');
          expect(
            controller.selection,
            TextSelection.collapsed(offset: cursorBeforeCut),
          );
        },
      );
    });

    group('pasteAtCursor', () {
      Future<void> mockClipboardText(WidgetTester tester, String? text) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.getData') {
              return text == null ? null : {'text': text};
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
      }

      testWidgets('inserts the clipboard\'s text at the cursor', (
        tester,
      ) async {
        await mockClipboardText(tester, 'pasted text');

        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'Before After',
                textColor: Colors.black,
                hintColor: Colors.black38,
                linkColor: Colors.blue,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        key.currentState!.focusBody();
        await tester.pumpAndSettle();
        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        controller.selection = TextSelection.collapsed(
          offset: 'Before'.length,
        );
        await tester.pumpAndSettle();

        await key.currentState!.pasteAtCursor();
        await tester.pumpAndSettle();

        expect(latest, 'Beforepasted text After');
      });

      testWidgets(
        'is a no-op while not currently editing - there is no cursor to '
        'insert at',
        (tester) async {
          await mockClipboardText(tester, 'pasted text');

          final key = GlobalKey<NoteBodyEditorState>();
          String latest = '';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: NoteBodyEditor(
                  key: key,
                  initialBody: 'Some text',
                  textColor: Colors.black,
                  hintColor: Colors.black38,
                  linkColor: Colors.blue,
                  onChanged: (body) => latest = body,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await key.currentState!.pasteAtCursor();
          await tester.pumpAndSettle();

          expect(latest, isEmpty);
        },
      );

      testWidgets('does nothing if the clipboard has no text to paste', (
        tester,
      ) async {
        await mockClipboardText(tester, null);

        final key = GlobalKey<NoteBodyEditorState>();
        String latest = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'Some text',
                textColor: Colors.black,
                hintColor: Colors.black38,
                linkColor: Colors.blue,
                onChanged: (body) => latest = body,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        key.currentState!.focusBody();
        await tester.pumpAndSettle();

        await key.currentState!.pasteAtCursor();
        await tester.pumpAndSettle();

        expect(latest, isEmpty);
      });
    });

    testWidgets(
      'onModeChanged fires when entering and leaving edit mode, so a '
      'parent toolbar (e.g. move-line buttons) can stay in sync',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        var modeChangedCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'Some notes.',
                textColor: Colors.black,
                hintColor: Colors.black38,
                linkColor: Colors.blue,
                onChanged: (_) {},
                onModeChanged: () => modeChangedCount++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        key.currentState!.focusBody();
        await tester.pumpAndSettle();
        expect(modeChangedCount, 1);

        key.currentState!.exitEditMode();
        await tester.pumpAndSettle();
        expect(modeChangedCount, 2);
      },
    );

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
              linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
              linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
              linkColor: Colors.blue,
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
              linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
              linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
              linkColor: Colors.blue,
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
              linkColor: Colors.blue,
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
              linkColor: Colors.blue,
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
              linkColor: Colors.blue,
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
              linkColor: Colors.blue,
              onChanged: (body) => latest = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Three separate structural changes in a row - each one always
      // tapped at position 0, since checking an item sinks it to the
      // bottom of the list (see NoteBodyEditorState._toggleChecked),
      // moving whichever item is still unchecked back up to the front:
      // checking "first" leaves "second" at the front, checking that
      // leaves "third" at the front, ready to delete.
      await tester.tap(find.byType(Checkbox).at(0)); // checks "first"
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(0)); // checks "second"
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close).at(0)); // deletes "third"
      await tester.pumpAndSettle();
      expect(latest, '- [x] first\n- [x] second');

      key.currentState!.undo();
      await tester.pumpAndSettle();
      expect(latest, '- [ ] third\n- [x] first\n- [x] second');

      key.currentState!.undo();
      await tester.pumpAndSettle();
      expect(latest, '- [ ] second\n- [ ] third\n- [x] first');

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
              linkColor: Colors.blue,
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
                linkColor: Colors.blue,
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
                  linkColor: Colors.blue,
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
                      linkColor: Colors.blue,
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
                        linkColor: Colors.blue,
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
                        linkColor: Colors.blue,
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
                  linkColor: Colors.blue,
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

  group('links in view mode', () {
    tearDown(() {
      LinkService.instance.debugOpen = null;
    });

    testWidgets(
      'tapping directly on a link opens it instead of entering edit mode',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        final opened = <String>[];
        LinkService.instance.debugOpen = (url) async {
          opened.add(url);
          return true;
        };
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'See https://example.com now',
                textColor: Colors.black,
                hintColor: Colors.black38,
                linkColor: Colors.blue,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final paragraph =
            tester.renderObject(find.byType(RichText).first) as RenderParagraph;
        final fullText = 'See https://example.com now';
        final linkStart = fullText.indexOf('https://example.com');
        final linkEnd = linkStart + 'https://example.com'.length;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: linkStart, extentOffset: linkEnd),
        );
        final box = boxes.first;
        final tapPoint = paragraph.localToGlobal(
          Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
        );

        await tester.tapAt(tapPoint);
        await tester.pumpAndSettle();

        expect(opened, ['https://example.com']);
        expect(key.currentState!.isEditingBody, isFalse);
      },
    );

    testWidgets(
      'tapping plain text next to a link still enters edit mode as usual',
      (tester) async {
        final key = GlobalKey<NoteBodyEditorState>();
        LinkService.instance.debugOpen = (_) async => true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteBodyEditor(
                key: key,
                initialBody: 'See https://example.com now',
                textColor: Colors.black,
                hintColor: Colors.black38,
                linkColor: Colors.blue,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final paragraph =
            tester.renderObject(find.byType(RichText).first) as RenderParagraph;
        final boxes = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 3), // "See"
        );
        final box = boxes.first;
        final tapPoint = paragraph.localToGlobal(
          Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
        );

        await tester.tapAt(tapPoint);
        await tester.pumpAndSettle();

        expect(key.currentState!.isEditingBody, isTrue);
      },
    );
  });
}
