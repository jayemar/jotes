import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';
import '../models/note.dart';

class DbService {
  static final DbService instance = DbService._();
  DbService._();

  static final _store = StoreRef<String, Map<String, Object?>>('notes');

  Database? _db;

  /// Overridable by tests so they never touch the real filesystem/IndexedDB
  /// or need platform-channel mocking - set (e.g. to [databaseFactoryMemory])
  /// before the first call, since the connection is opened lazily and
  /// cached afterward.
  DatabaseFactory? debugFactory;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    if (debugFactory != null) {
      return debugFactory!.openDatabase('jotes-test.db');
    }
    // sqflite (and thus a single shared SQL codepath) has no web
    // implementation at all - browsers only expose IndexedDB, not real
    // file-based SQLite. sembast abstracts over both with one API: a
    // file-backed store via sembast_io off-web, IndexedDB via sembast_web
    // on web, mirroring how Google Keep itself uses SQLite on Android and
    // IndexedDB in its own web client.
    if (kIsWeb) {
      return databaseFactoryWeb.openDatabase('jotes.db');
    }
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'jotes.db');
    return databaseFactoryIo.openDatabase(path);
  }

  Future<List<Note>> getAll() async {
    final db = await _database;
    final records = await _store.find(
      db,
      finder: Finder(sortOrders: [SortOrder('updated', false)]),
    );
    return records.map((r) => Note.fromMap(r.value)).toList();
  }

  Future<Note?> getById(String id) async {
    final db = await _database;
    final value = await _store.record(id).get(db);
    if (value == null) return null;
    return Note.fromMap(value);
  }

  Future<List<Note>> withFutureReminders() async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = await _store.find(
      db,
      finder: Finder(filter: Filter.greaterThan('reminder_at', now)),
    );
    return records.map((r) => Note.fromMap(r.value)).toList();
  }

  Future<void> upsert(Note note) async {
    final db = await _database;
    await _store.record(note.id).put(db, note.toMap());
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await _store.record(id).delete(db);
  }
}
