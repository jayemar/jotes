import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/board.dart';
import '../services/db_service.dart';
import '../services/pb_service.dart';
import 'notes_provider.dart';

class BoardsNotifier extends AsyncNotifier<List<Board>> {
  @override
  Future<List<Board>> build() async => DbService.instance.getAllBoards();

  Future<void> addOrUpdate(Board board) async {
    await DbService.instance.upsertBoard(board);
    PbService.instance.upsertBoard(board).ignore();
    ref.invalidateSelf();
  }

  /// Deletes [board] and un-files every note that was in it (set back to
  /// "unsorted", `boardId: null`) rather than leaving them pointing at a
  /// board id that no longer exists - each un-filing goes through
  /// notesProvider's own addOrUpdate so it's saved/synced/widget-refreshed
  /// the same way any other note edit is, not a raw DbService write that
  /// would skip all of that.
  Future<void> delete(Board board) async {
    final notes = await ref.read(notesProvider.future);
    final notesNotifier = ref.read(notesProvider.notifier);
    for (final note in notes.where((n) => n.boardId == board.id)) {
      await notesNotifier.addOrUpdate(note.copyWith(boardId: null));
    }

    await DbService.instance.deleteBoard(board.id);
    PbService.instance.deleteBoard(board.id).ignore();
    ref.invalidateSelf();
  }
}

final boardsProvider = AsyncNotifierProvider<BoardsNotifier, List<Board>>(
  BoardsNotifier.new,
);
