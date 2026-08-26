import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/providers/note_toolbar_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NoteToolbarState.visibleInOrder', () {
    test('returns the order as-is when nothing is hidden', () {
      const state = NoteToolbarState(
        order: [NoteToolbarTool.undo, NoteToolbarTool.checklist],
        hidden: {},
      );
      expect(state.visibleInOrder, [
        NoteToolbarTool.undo,
        NoteToolbarTool.checklist,
      ]);
    });

    test('omits hidden tools, keeping the relative order of the rest', () {
      const state = NoteToolbarState(
        order: [
          NoteToolbarTool.checklist,
          NoteToolbarTool.bullet,
          NoteToolbarTool.undo,
        ],
        hidden: {NoteToolbarTool.bullet},
      );
      expect(state.visibleInOrder, [
        NoteToolbarTool.checklist,
        NoteToolbarTool.undo,
      ]);
    });
  });

  group('NoteToolbarNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to every tool, in enum order, nothing hidden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(noteToolbarProvider);
      expect(state.order, NoteToolbarTool.values);
      expect(state.hidden, isEmpty);
    });

    test('setOrder updates the order without touching hidden', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(noteToolbarProvider.notifier);
      await notifier.setHidden(NoteToolbarTool.paste, true);

      final reordered = [
        NoteToolbarTool.undo,
        ...NoteToolbarTool.values.where((t) => t != NoteToolbarTool.undo),
      ];
      await notifier.setOrder(reordered);

      final state = container.read(noteToolbarProvider);
      expect(state.order, reordered);
      expect(state.hidden, {NoteToolbarTool.paste});
    });

    test('setHidden toggles a tool\'s visibility without touching order',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(noteToolbarProvider.notifier);

      await notifier.setHidden(NoteToolbarTool.moveUp, true);
      expect(container.read(noteToolbarProvider).hidden, {
        NoteToolbarTool.moveUp,
      });

      await notifier.setHidden(NoteToolbarTool.moveUp, false);
      expect(container.read(noteToolbarProvider).hidden, isEmpty);
    });

    test('choices persist for a freshly-built notifier', () async {
      final container1 = ProviderContainer();
      final notifier1 = container1.read(noteToolbarProvider.notifier);
      await notifier1.setOrder([
        NoteToolbarTool.undo,
        NoteToolbarTool.paste,
        NoteToolbarTool.cutLine,
        NoteToolbarTool.checklist,
        NoteToolbarTool.bullet,
        NoteToolbarTool.moveUp,
        NoteToolbarTool.moveDown,
      ]);
      await notifier1.setHidden(NoteToolbarTool.moveDown, true);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      // NotifierProviders build lazily on first read - read once to
      // trigger build() (which kicks off an unawaited async load from
      // SharedPreferences), then give that load a turn to complete.
      container2.read(noteToolbarProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container2.read(noteToolbarProvider);
      expect(state.order, [
        NoteToolbarTool.undo,
        NoteToolbarTool.paste,
        NoteToolbarTool.cutLine,
        NoteToolbarTool.checklist,
        NoteToolbarTool.bullet,
        NoteToolbarTool.moveUp,
        NoteToolbarTool.moveDown,
      ]);
      expect(state.hidden, {NoteToolbarTool.moveDown});
    });

    test(
      'a persisted order missing a tool the app now defines appends it '
      'at the end, rather than silently dropping it from the toolbar '
      'entirely',
      () async {
        SharedPreferences.setMockInitialValues({
          'note_toolbar_order': NoteToolbarTool.values
              .where((t) => t != NoteToolbarTool.paste)
              .map((t) => t.name)
              .toList(),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(noteToolbarProvider);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final state = container.read(noteToolbarProvider);
        expect(state.order.last, NoteToolbarTool.paste);
        expect(state.order.toSet(), NoteToolbarTool.values.toSet());
      },
    );

    test(
      'a persisted order naming a tool the app no longer defines drops '
      'it silently, rather than crashing',
      () async {
        SharedPreferences.setMockInitialValues({
          'note_toolbar_order': [
            'someRemovedTool',
            ...NoteToolbarTool.values.map((t) => t.name),
          ],
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(noteToolbarProvider);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final state = container.read(noteToolbarProvider);
        expect(state.order.toSet(), NoteToolbarTool.values.toSet());
        expect(state.order, hasLength(NoteToolbarTool.values.length));
      },
    );

    test(
      'a persisted hidden entry naming a tool the app no longer defines '
      'is dropped silently too',
      () async {
        SharedPreferences.setMockInitialValues({
          'note_toolbar_hidden': ['someRemovedTool', 'undo'],
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(noteToolbarProvider);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final state = container.read(noteToolbarProvider);
        expect(state.hidden, {NoteToolbarTool.undo});
      },
    );
  });
}
