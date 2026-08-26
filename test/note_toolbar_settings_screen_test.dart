import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/providers/note_toolbar_provider.dart';
import 'package:jotes/screens/note_toolbar_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NoteToolbarSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('lists every tool, in its current order, with a label and '
      'icon each', (tester) async {
    await _pumpScreen(tester);

    for (final tool in NoteToolbarTool.values) {
      expect(find.text(tool.label), findsOneWidget);
      expect(find.byIcon(tool.icon), findsOneWidget);
    }
  });

  testWidgets(
    'Cut line shows a composite scissors-plus-line icon (see '
    'noteToolbarIcon), not a bare scissors icon that would read as '
    '"cut the selection" instead of "cut this line"',
    (tester) async {
      await _pumpScreen(tester);

      final cutLineRow = find.byKey(ValueKey(NoteToolbarTool.cutLine));
      // The row's own drag handle is an Icon too, so this tool's own
      // scissors glyph plus that handle is 2, not 1.
      expect(
        find.descendant(of: cutLineRow, matching: find.byType(Icon)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: cutLineRow, matching: find.byType(Stack)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cutLineRow, matching: find.byType(Container)),
        findsOneWidget,
      );

      // A tool other than Cut line has no such extra Stack/Container -
      // just its own bare icon.
      final undoRow = find.byKey(ValueKey(NoteToolbarTool.undo));
      expect(
        find.descendant(of: undoRow, matching: find.byType(Stack)),
        findsNothing,
      );
    },
  );

  testWidgets('every tool starts visible (switch on)', (tester) async {
    await _pumpScreen(tester);

    for (final tool in NoteToolbarTool.values) {
      final switchWidget = tester.widget<Switch>(
        find.byKey(Key('note_toolbar_visibility_${tool.name}')),
      );
      expect(switchWidget.value, isTrue);
    }
  });

  testWidgets(
    'toggling a tool\'s switch off hides it - reflected immediately in '
    'the provider state',
    (tester) async {
      final container = await _pumpScreen(tester);

      await tester.tap(
        find.byKey(const Key('note_toolbar_visibility_paste')),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(noteToolbarProvider).hidden,
        contains(NoteToolbarTool.paste),
      );
      final switchWidget = tester.widget<Switch>(
        find.byKey(const Key('note_toolbar_visibility_paste')),
      );
      expect(switchWidget.value, isFalse);
    },
  );

  testWidgets(
    'toggling an already-hidden tool\'s switch back on re-shows it',
    (tester) async {
      final container = await _pumpScreen(tester);
      await container
          .read(noteToolbarProvider.notifier)
          .setHidden(NoteToolbarTool.undo, true);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('note_toolbar_visibility_undo')),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(noteToolbarProvider).hidden,
        isNot(contains(NoteToolbarTool.undo)),
      );
    },
  );

  testWidgets(
    'dragging a tool\'s handle down past the next one reorders them, '
    'reflected in the provider state',
    (tester) async {
      final container = await _pumpScreen(tester);
      final before = container.read(noteToolbarProvider).order;
      expect(before.first, NoteToolbarTool.checklist);
      expect(before[1], NoteToolbarTool.bullet);

      // A long-press-then-drag, the same technique Flutter's own
      // ReorderableListView tests use - a plain tester.drag() doesn't
      // hold long enough for the drag recognizer to actually win against
      // the list's own scroll recognizer.
      final firstTileHeight = tester
          .getSize(find.byType(ListTile).first)
          .height;
      final drag = await tester.startGesture(
        tester.getCenter(
          find.byKey(
            Key('note_toolbar_drag_${NoteToolbarTool.checklist.name}'),
          ),
        ),
      );
      await tester.pump(kPressTimeout);
      // Small initial move to let the drag recognizer win the gesture
      // arena against the list's own vertical scroll, then just past the
      // halfway point of the next tile - enough to trigger exactly one
      // swap, not two - the same shape (and roughly the same proportion:
      // 10 + half the item's own height) as Flutter's own
      // ReorderableListView tests.
      await drag.moveBy(const Offset(0, 10));
      await tester.pump();
      await drag.moveBy(Offset(0, firstTileHeight / 2));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      final after = container.read(noteToolbarProvider).order;
      expect(after.first, NoteToolbarTool.bullet);
      expect(after[1], NoteToolbarTool.checklist);
      // Reordering must never drop or duplicate a tool.
      expect(after.toSet(), NoteToolbarTool.values.toSet());
    },
  );
}
