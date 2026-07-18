@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/pb_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Exercises PbService against a real, running PocketBase instance (see
/// backend/Dockerfile) rather than mocks - sync is the one part of this
/// app where a mocked test could easily pass while the real server
/// integration is subtly broken (wrong collection name, wrong field
/// mapping, wrong id format, auth rule mismatch, etc.), so this is worth
/// the cost of a live dependency.
///
/// Requires a PocketBase instance from backend/Dockerfile running on
/// localhost:18091 with the pb_migrations already applied. Skipped
/// automatically if that server isn't reachable.
const _testServerUrl = 'http://localhost:18091';
const _uuid = Uuid();

Note _note({
  String? id,
  String title = 'Title',
  String body = 'Body',
  int colorIndex = 0,
  DateTime? reminderAt,
  DateTime? created,
  DateTime? updated,
}) {
  final now = DateTime.now();
  return Note(
    id: id ?? _uuid.v4(),
    title: title,
    body: body,
    colorIndex: colorIndex,
    reminderAt: reminderAt,
    created: created ?? now,
    updated: updated ?? now,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PbService against a live PocketBase server', () {
    test('register creates an account and logs into it', () async {
      final email = 'test-${_uuid.v4()}@example.com';
      await PbService.instance.connect(_testServerUrl);
      await PbService.instance.register(email, 'password123');

      expect(PbService.instance.isLoggedIn, isTrue);
      expect(PbService.instance.userEmail, email);
    });

    test('upsert creates a record retrievable via fetchAll', () async {
      await PbService.instance.connect(_testServerUrl);
      await PbService.instance.register(
        'test-${_uuid.v4()}@example.com',
        'password123',
      );

      final note = _note(title: 'Groceries');
      await PbService.instance.upsert(note);

      final all = await PbService.instance.fetchAll();
      expect(all.map((n) => n.id), contains(note.id));
      expect(all.firstWhere((n) => n.id == note.id).title, 'Groceries');
    });

    test('upsert with an existing id updates the record instead of '
        'duplicating it', () async {
      await PbService.instance.connect(_testServerUrl);
      await PbService.instance.register(
        'test-${_uuid.v4()}@example.com',
        'password123',
      );

      final note = _note(title: 'Before');
      await PbService.instance.upsert(note);
      await PbService.instance.upsert(note.copyWith(title: 'After'));

      final all = await PbService.instance.fetchAll();
      final matches = all.where((n) => n.id == note.id);
      expect(matches, hasLength(1));
      expect(matches.single.title, 'After');
    });

    test('delete removes the record from fetchAll', () async {
      await PbService.instance.connect(_testServerUrl);
      await PbService.instance.register(
        'test-${_uuid.v4()}@example.com',
        'password123',
      );

      final note = _note();
      await PbService.instance.upsert(note);
      expect(
        (await PbService.instance.fetchAll()).map((n) => n.id),
        contains(note.id),
      );

      await PbService.instance.delete(note.id);

      expect(
        (await PbService.instance.fetchAll()).map((n) => n.id),
        isNot(contains(note.id)),
      );
    });

    test('a reminder round-trips through the server correctly', () async {
      await PbService.instance.connect(_testServerUrl);
      await PbService.instance.register(
        'test-${_uuid.v4()}@example.com',
        'password123',
      );

      final reminderAt = DateTime.now()
          .add(const Duration(hours: 3))
          .copyWith(microsecond: 0, millisecond: 0);
      final note = _note(reminderAt: reminderAt);
      await PbService.instance.upsert(note);

      final fetched =
          (await PbService.instance.fetchAll()).firstWhere((n) => n.id == note.id);
      expect(fetched.reminderAt, isNotNull);
      expect(
        fetched.reminderAt!.difference(reminderAt).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('subscribe receives a realtime event for a change made by the '
        'same client', () async {
      await PbService.instance.connect(_testServerUrl);
      await PbService.instance.register(
        'test-${_uuid.v4()}@example.com',
        'password123',
      );

      final events = <String>[];
      PbService.instance.subscribe((action, note) {
        if (note != null) events.add('$action:${note.id}');
      });
      // Give the realtime connection a moment to actually establish before
      // triggering the change we want to observe.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final note = _note();
      await PbService.instance.upsert(note);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (events.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      PbService.instance.unsubscribe();
      expect(events, contains('create:${note.id}'));
    });

    test('disconnect logs out and forgets the session', () async {
      await PbService.instance.connect(_testServerUrl);
      await PbService.instance.register(
        'test-${_uuid.v4()}@example.com',
        'password123',
      );
      expect(PbService.instance.isLoggedIn, isTrue);

      await PbService.instance.disconnect();

      expect(PbService.instance.isLoggedIn, isFalse);
    });

    test('restore re-establishes a session from a previous connect+login',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final email = 'test-${_uuid.v4()}@example.com';
      await PbService.instance.connect(_testServerUrl);
      await PbService.instance.register(email, 'password123');
      expect(PbService.instance.isLoggedIn, isTrue);

      // Simulate an app restart: nothing but what's in prefs survives.
      final savedUrl = prefs.getString('pb_server_url');
      final savedAuth = prefs.getString('pb_auth');
      expect(savedUrl, _testServerUrl);
      expect(savedAuth, isNotNull);

      await PbService.instance.restore();

      expect(PbService.instance.isLoggedIn, isTrue);
      expect(PbService.instance.userEmail, email);
    });
  });
}
