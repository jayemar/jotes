import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/board.dart';

Board _board({
  String id = 'b1',
  String name = 'Groceries',
  bool deleted = false,
}) {
  final now = DateTime.now();
  return Board(
    id: id,
    name: name,
    created: now,
    updated: now,
    deleted: deleted,
  );
}

void main() {
  group('Board.copyWith', () {
    test('sets name independently of other fields', () {
      final board = _board(name: 'Old name');
      final renamed = board.copyWith(name: 'New name');

      expect(renamed.name, 'New name');
      expect(renamed.id, board.id);
      expect(renamed.created, board.created);
    });

    test('with no updated argument keeps the original updated timestamp', () {
      final board = _board();
      final renamed = board.copyWith(name: 'New name');

      expect(renamed.updated, board.updated);
    });

    test('sets updated when explicitly passed', () {
      final board = _board();
      final later = board.updated.add(const Duration(minutes: 5));

      final renamed = board.copyWith(name: 'New name', updated: later);

      expect(renamed.updated, later);
    });
  });

  group('Board JSON round-trip', () {
    test('round-trips through toMap/fromMap (local storage)', () {
      final board = _board(name: 'Work');

      final restored = Board.fromMap(board.toMap());

      expect(restored.id, board.id);
      expect(restored.name, 'Work');
      // Millisecond precision only (see toMap's own millisecondsSinceEpoch)
      // - comparing full DateTime equality here would spuriously fail on
      // the sub-millisecond difference DateTime.now() itself can carry.
      expect(
        restored.created.millisecondsSinceEpoch,
        board.created.millisecondsSinceEpoch,
      );
      expect(
        restored.updated.millisecondsSinceEpoch,
        board.updated.millisecondsSinceEpoch,
      );
      // Local storage never persists a deleted board at all (see
      // DbService.deleteBoard) - fromMap always reads false.
      expect(restored.deleted, isFalse);
    });

    test('round-trips through toPocketBase/fromPocketBase (server sync)', () {
      final board = _board(name: 'Work');

      final restored = Board.fromPocketBase({
        'id': board.id,
        'created': board.created.toUtc().toIso8601String(),
        'updated': board.updated.toUtc().toIso8601String(),
        ...board.toPocketBase(),
      });

      expect(restored.id, board.id);
      expect(restored.name, 'Work');
      expect(restored.deleted, isFalse);
    });

    test('toPocketBase always clears a stale tombstone - a local board is '
        'by definition active', () {
      final board = _board(deleted: true);

      expect(board.toPocketBase()['deleted'], isFalse);
    });

    test('fromPocketBase reads a tombstoned record as deleted', () {
      final restored = Board.fromPocketBase({
        'id': 'b1',
        'name': 'Gone',
        'deleted': true,
      });

      expect(restored.deleted, isTrue);
    });

    test('fromMap/fromPocketBase fall back to an empty name rather than '
        'throwing when absent', () {
      expect(
        Board.fromMap({
          'id': 'b1',
          'created': DateTime.now().millisecondsSinceEpoch,
          'updated': DateTime.now().millisecondsSinceEpoch,
        }).name,
        isEmpty,
      );
      expect(Board.fromPocketBase({'id': 'b1'}).name, isEmpty);
    });
  });
}
