import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

const _urlPrefsKey = 'pb_server_url';
const _authPrefsKey = 'pb_auth';

class PbService {
  static final PbService instance = PbService._();
  PbService._();

  PocketBase? _client;

  bool get isConfigured => _client != null;
  bool get isLoggedIn => _client?.authStore.isValid ?? false;
  String? get serverUrl => _client?.baseURL;
  String? get userEmail =>
      _client?.authStore.record?.data['email'] as String?;

  Future<AsyncAuthStore> _buildAuthStore(SharedPreferences prefs) async {
    return AsyncAuthStore(
      save: (data) async => prefs.setString(_authPrefsKey, data),
      initial: prefs.getString(_authPrefsKey),
      clear: () async => prefs.remove(_authPrefsKey),
    );
  }

  /// Restores a previously configured server + auth session, if any, so
  /// the app doesn't require logging in again after every restart. Call
  /// once at startup, before anything reads sync status.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_urlPrefsKey);
    if (url == null) return;

    _client = PocketBase(url, authStore: await _buildAuthStore(prefs));
  }

  /// Points the client at [url] and persists it for next launch. Does not
  /// authenticate - call [login] or [register] next.
  Future<void> connect(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlPrefsKey, url);
    _client = PocketBase(url, authStore: await _buildAuthStore(prefs));
  }

  Future<void> login(String email, String password) async {
    await _client!.collection('users').authWithPassword(email, password);
  }

  /// Creates a new account on the `users` collection, then logs into it.
  /// Lets a fresh self-hosted PocketBase instance be used entirely from
  /// within the app, without needing the admin dashboard to create a user
  /// first.
  Future<void> register(String email, String password) async {
    await _client!.collection('users').create(body: {
      'email': email,
      'password': password,
      'passwordConfirm': password,
    });
    await login(email, password);
  }

  /// Logs out and forgets the server entirely (URL and saved session).
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    _client?.authStore.clear();
    await prefs.remove(_urlPrefsKey);
    await prefs.remove(_authPrefsKey);
    _client = null;
  }

  Future<List<Note>> fetchAll() async {
    if (!isLoggedIn) return [];
    final records = await _client!.collection('notes').getFullList(
      sort: '-updated',
    );
    return records.map((r) => Note.fromPocketBase(r.toJson())).toList();
  }

  Future<void> upsert(Note note) async {
    if (!isLoggedIn) return;
    try {
      await _client!.collection('notes').update(
        note.id,
        body: note.toPocketBase(),
      );
    } on ClientException catch (e) {
      if (e.statusCode == 404) {
        await _client!.collection('notes').create(
          body: {'id': note.id, ...note.toPocketBase()},
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> delete(String id) async {
    if (!isLoggedIn) return;
    try {
      await _client!.collection('notes').delete(id);
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }

  void subscribe(void Function(String action, Note? note) onEvent) {
    if (!isLoggedIn) return;
    _client?.collection('notes').subscribe('*', (event) {
      final record = event.record;
      onEvent(
        event.action,
        record != null ? Note.fromPocketBase(record.toJson()) : null,
      );
    });
  }

  void unsubscribe() {
    _client?.collection('notes').unsubscribe();
  }
}
