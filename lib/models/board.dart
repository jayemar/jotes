/// A named group notes can be filed under - a note belongs to at most one
/// board (or none, meaning "unsorted"), the same one-note-one-parent
/// convention a plain folder hierarchy uses, rather than tags/labels a note
/// could carry several of at once. See [BoardsScreen] for
/// create/rename/delete, and NotesScreen's own `board` parameter for
/// viewing just one board's notes.
class Board {
  final String id;
  final String name;
  final DateTime created;
  final DateTime updated;

  /// Only ever meaningful on a [Board] fetched via [Board.fromPocketBase]
  /// during a sync merge - a tombstone rather than a real delete, same
  /// reasoning as [Note.deleted]'s own doc comment (lib/models/note.dart):
  /// lets a device that was offline when a board was deleted elsewhere
  /// tell "deleted after I last saw it" apart from "never synced to begin
  /// with". Local storage (DbService) never persists a deleted board at
  /// all, so this is always false for a [Board] built from [Board.fromMap].
  final bool deleted;

  const Board({
    required this.id,
    required this.name,
    required this.created,
    required this.updated,
    this.deleted = false,
  });

  Board copyWith({String? name, DateTime? updated}) => Board(
    id: id,
    name: name ?? this.name,
    created: created,
    updated: updated ?? this.updated,
    deleted: deleted,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'created': created.millisecondsSinceEpoch,
    'updated': updated.millisecondsSinceEpoch,
  };

  factory Board.fromMap(Map<String, dynamic> map) => Board(
    id: map['id'] as String,
    name: (map['name'] as String?) ?? '',
    created: DateTime.fromMillisecondsSinceEpoch(map['created'] as int),
    updated: DateTime.fromMillisecondsSinceEpoch(map['updated'] as int),
  );

  Map<String, dynamic> toPocketBase() => {
    'name': name,
    // A local board is by definition active, not a tombstone - pushing
    // one up (e.g. from mergeSync's local-is-newer branch) must always
    // clear a stale remote tombstone rather than leave it set. Same
    // reasoning as Note.toPocketBase's own 'deleted' field.
    'deleted': false,
  };

  factory Board.fromPocketBase(Map<String, dynamic> r) {
    final now = DateTime.now();
    return Board(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? '',
      created: r['created'] != null
          ? DateTime.parse(r['created'] as String).toLocal()
          : now,
      updated: r['updated'] != null
          ? DateTime.parse(r['updated'] as String).toLocal()
          : now,
      deleted: r['deleted'] == true,
    );
  }
}
