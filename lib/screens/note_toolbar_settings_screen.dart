import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/note_toolbar_provider.dart';

/// Lets the user reorder the note editor's bottom toolbar tools (see
/// note_editor_screen.dart) and toggle which ones are shown at all - a
/// global preference (see NoteToolbarNotifier), not per-note. Reached from
/// the note editor's own overflow menu ("Customize toolbar").
///
/// Every tool stays listed here even once hidden (just dimmed), so it can
/// still be reordered and re-shown - only note_editor_screen.dart's own
/// toolbar Row (via NoteToolbarState.visibleInOrder) actually omits
/// hidden tools.
class NoteToolbarSettingsScreen extends ConsumerWidget {
  const NoteToolbarSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noteToolbarProvider);
    final notifier = ref.read(noteToolbarProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Customize toolbar')),
      body: ReorderableListView.builder(
        key: const Key('note_toolbar_settings_list'),
        itemCount: state.order.length,
        onReorderItem: (oldIndex, newIndex) {
          final newOrder = [...state.order];
          final tool = newOrder.removeAt(oldIndex);
          newOrder.insert(newIndex, tool);
          notifier.setOrder(newOrder);
        },
        itemBuilder: (context, index) {
          final tool = state.order[index];
          final visible = !state.hidden.contains(tool);
          return ListTile(
            key: ValueKey(tool),
            leading: ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                key: Key('note_toolbar_drag_${tool.name}'),
              ),
            ),
            title: Opacity(
              opacity: visible ? 1 : 0.5,
              child: Row(
                children: [
                  noteToolbarIcon(tool, size: 20),
                  const SizedBox(width: 16),
                  Expanded(child: Text(tool.label)),
                ],
              ),
            ),
            trailing: Switch(
              key: Key('note_toolbar_visibility_${tool.name}'),
              value: visible,
              onChanged: (value) => notifier.setHidden(tool, !value),
            ),
          );
        },
      ),
    );
  }
}
