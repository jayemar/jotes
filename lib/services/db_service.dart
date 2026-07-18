import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/note.dart';

class DbService {
  static final DbService instance = DbService._();
  DbService._();

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'jotes.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE notes (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL DEFAULT '',
          body TEXT NOT NULL DEFAULT '',
          color_index INTEGER NOT NULL DEFAULT 0,
          reminder_at INTEGER,
          created INTEGER NOT NULL,
          updated INTEGER NOT NULL
        )
      '''),
    );
  }

  Future<List<Note>> getAll() async {
    final db = await _database;
    final rows = await db.query('notes', orderBy: 'updated DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<Note?> getById(String id) async {
    final db = await _database;
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Note.fromMap(rows.first);
  }

  Future<List<Note>> withFutureReminders() async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'notes',
      where: 'reminder_at > ?',
      whereArgs: [now],
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> upsert(Note note) async {
    final db = await _database;
    await db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}
