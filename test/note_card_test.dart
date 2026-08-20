import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/link_service.dart';
import 'package:jotes/widgets/note_card.dart';

Note _note({
  String title = 'Title',
  String body = '',
  DateTime? reminderAt,
  bool reminderResolved = false,
}) {
  final now = DateTime.now();
  return Note(
    id: 'note-1',
    title: title,
    body: body,
    colorIndex: 0,
    reminderAt: reminderAt,
    created: now,
    updated: now,
    reminderResolved: reminderResolved,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Note note, {
  bool selectionMode = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NoteCard(
          note: note,
          selected: false,
          selectionMode: selectionMode,
          onTap: () {},
          onLongPress: () {},
        ),
      ),
    ),
  );
}

/// The style of the specific TextSpan showing [text] - previews now render
/// via Text.rich/buildLinkSpans (see note_card.dart), so a run's own style
/// lives on its own child span, not top-level Text.style, and [text] is
/// usually only part of a wider Text.rich's full plain text (e.g. a link
/// within "Check https://example.com now") rather than a whole Text's own
/// exact string - searches every Text in the tree for a child span whose
/// text exactly matches, not find.text's whole-widget match.
TextStyle _spanStyle(WidgetTester tester, String text) {
  TextStyle? found;
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    if (found != null) break;
    widget.textSpan?.visitChildren((child) {
      if (child is TextSpan && child.text == text) {
        found = child.style;
        return false;
      }
      return true;
    });
  }
  return found!;
}

void main() {
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
    expect(_spanStyle(tester, 'Done thing').decoration, TextDecoration.lineThrough);
  });

  testWidgets('an unchecked checklist item has no strikethrough', (
    tester,
  ) async {
    await _pump(tester, _note(body: '- [ ] Not done yet'));

    expect(
      _spanStyle(tester, 'Not done yet').decoration,
      isNot(TextDecoration.lineThrough),
    );
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

  group('links in the preview', () {
    tearDown(() {
      LinkService.instance.debugOpen = null;
    });

    testWidgets('a markdown/bare-URL link renders underlined in link-blue, '
        'unlike surrounding plain text', (tester) async {
      await _pump(tester, _note(body: 'Check https://example.com now'));

      final linkStyle = _spanStyle(tester, 'https://example.com');
      expect(linkStyle.decoration, TextDecoration.underline);
      expect(linkStyle.color, Colors.blue);

      final plainStyle = _spanStyle(tester, 'Check ');
      expect(plainStyle.decoration, isNot(TextDecoration.underline));
    });

    testWidgets(
      'tapping a link outside selection mode opens it, not the note',
      (tester) async {
        final opened = <String>[];
        LinkService.instance.debugOpen = (url) async {
          opened.add(url);
          return true;
        };
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteCard(
                note: _note(body: 'See https://example.com here'),
                selected: false,
                selectionMode: false,
                onTap: () => tapped = true,
                onLongPress: () {},
              ),
            ),
          ),
        );

        // Not find.byType(RichText).first - the note's own title ("Title",
        // the _note() helper's default) renders as a RichText too, so this
        // picks out specifically the body preview's one.
        const fullText = 'See https://example.com here';
        final paragraph = tester
            .renderObjectList<RenderParagraph>(find.byType(RichText))
            .firstWhere((p) => p.text.toPlainText() == fullText);
        final linkStart = fullText.indexOf('https://example.com');
        final linkEnd = linkStart + 'https://example.com'.length;
        final box = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: linkStart, extentOffset: linkEnd),
            )
            .first;
        final tapPoint = paragraph.localToGlobal(
          Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
        );

        await tester.tapAt(tapPoint);
        await tester.pumpAndSettle();

        expect(opened, ['https://example.com']);
        expect(tapped, isFalse);
      },
    );

    testWidgets(
      'in selection mode, tapping a link toggles selection instead of '
      'opening it - a card is a single toggle-selection target while '
      'selecting',
      (tester) async {
        LinkService.instance.debugOpen = (_) async => true;
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteCard(
                note: _note(body: 'See https://example.com here'),
                selected: false,
                selectionMode: true,
                onTap: () => tapped = true,
                onLongPress: () {},
              ),
            ),
          ),
        );

        await tester.tap(find.textContaining('https://example.com'));
        await tester.pumpAndSettle();

        expect(tapped, isTrue);
      },
    );
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
      await _pump(
        tester,
        _note(
          reminderAt: DateTime.now().subtract(const Duration(hours: 1)),
          reminderResolved: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(chipColor(tester), Colors.red.withAlpha(40));
    });
  });
}
