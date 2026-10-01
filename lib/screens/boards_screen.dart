import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/board.dart';
import '../providers/boards_provider.dart';
import 'notes_screen.dart';

const _uuid = Uuid();

/// Lists every [Board] - tap one to view just its own notes (pushes
/// NotesScreen with that board), long-press for Rename/Delete, "+" to
/// create a new one. Reached from the drawer (see
/// NotesScreen._buildDrawer).
class BoardsScreen extends ConsumerWidget {
  const BoardsScreen({super.key});

  Future<void> _createBoard(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const BoardNameDialog(title: 'New board'),
    );
    if (name == null || name.trim().isEmpty) return;

    final now = DateTime.now();
    await ref.read(boardsProvider.notifier).addOrUpdate(
      Board(id: _uuid.v4(), name: name.trim(), created: now, updated: now),
    );
  }

  Future<void> _renameBoard(
    BuildContext context,
    WidgetRef ref,
    Board board,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          BoardNameDialog(title: 'Rename board', initialName: board.name),
    );
    if (name == null || name.trim().isEmpty) return;

    await ref.read(boardsProvider.notifier).addOrUpdate(
      board.copyWith(name: name.trim(), updated: DateTime.now()),
    );
  }

  Future<void> _deleteBoard(
    BuildContext context,
    WidgetRef ref,
    Board board,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${board.name}"?'),
        content: const Text(
          "This board's own notes are not deleted - they go back to "
          'unsorted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(boardsProvider.notifier).delete(board);
  }

  /// Anchored right next to whichever widget triggered it (see
  /// color_picker_sheet.dart's own doc comment for the same technique) -
  /// [anchorContext] should be the BuildContext of that specific tapped
  /// widget, not just any ancestor context, which is why every call site
  /// wraps its trigger in its own Builder.
  Future<void> _showBoardMenu(
    BuildContext anchorContext,
    WidgetRef ref,
    Board board,
  ) async {
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final button = anchorContext.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: anchorContext,
      position: position,
      items: const [
        PopupMenuItem(
          key: Key('board_menu_rename'),
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Rename'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          key: Key('board_menu_delete'),
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (!anchorContext.mounted) return;
    switch (action) {
      case 'rename':
        await _renameBoard(anchorContext, ref, board);
      case 'delete':
        await _deleteBoard(anchorContext, ref, board);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardsAsync = ref.watch(boardsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Boards')),
      body: boardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text("Couldn't load boards: $error")),
        data: (boards) {
          if (boards.isEmpty) {
            return const Center(
              child: Text(
                'No boards yet - tap + to create one',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: boards.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final board = boards[index];
              return Builder(
                builder: (tileContext) => ListTile(
                  key: ValueKey(board.id),
                  leading: const Icon(Icons.dashboard_outlined),
                  title: Text(board.name),
                  onTap: () => Navigator.push(
                    tileContext,
                    MaterialPageRoute(
                      builder: (_) => NotesScreen(board: board),
                    ),
                  ),
                  onLongPress: () => _showBoardMenu(tileContext, ref, board),
                  trailing: IconButton(
                    key: Key('board_menu_button_${board.id}'),
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Board options',
                    onPressed: () => _showBoardMenu(tileContext, ref, board),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('boards_create_fab'),
        onPressed: () => _createBoard(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class BoardNameDialog extends StatefulWidget {
  final String title;
  final String initialName;

  const BoardNameDialog({
    super.key,
    required this.title,
    this.initialName = '',
  });

  @override
  State<BoardNameDialog> createState() => _BoardNameDialogState();
}

class _BoardNameDialogState extends State<BoardNameDialog> {
  late final _nameCtrl = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('board_name_field'),
        controller: _nameCtrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('board_name_save'),
          onPressed: () => Navigator.pop(context, _nameCtrl.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
