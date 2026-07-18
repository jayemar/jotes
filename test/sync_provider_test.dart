@Tags(['integration'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/sync_provider.dart';
import 'package:jotes/services/db_service.dart';
import 'package:jotes/services/pb_service.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Exercises SyncNotifier's merge-on-connect logic against the same live
/// PocketBase instance used by pb_service_integration_test.dart (see
/// backend/Dockerfile), combined with a real local in-memory-backed
/// DbService - the merge algorithm's correctness depends on the
/// interaction between both real stores, not just one in isolation.
const _testServerUrl = 'http://localhost:18091';
const _uuid = Uuid();

Note _note({
  required String id,
  String title = 'Title',
  DateTime? updated,
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: title,
    body: '',
    colorIndex: 0,
    created: updated ?? now,
    updated: updated ?? now,
  );
}

void main() {
  setUpAll(() {
    DbService.instance.debugFactory = databaseFactoryMemory;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final existing = await DbService.instance.getAll();
    for (final note in existing) {
      await DbService.instance.delete(note.id);
    }
  });

  test('a remote-only note is pulled down into the local database',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Seed the remote side directly via PbService before the app "starts".
    final email = 'test-${_uuid.v4()}@example.com';
    await PbService.instance.connect(_testServerUrl);
    await PbService.instance.register(email, 'password123');
    final remoteOnlyId = _uuid.v4();
    await PbService.instance.upsert(_note(id: remoteOnlyId, title: 'From server'));
    await PbService.instance.disconnect();

    // Now connect for real through the notifier, as the app would.
    await container.read(syncProvider.notifier).connect(
          url: _testServerUrl,
          email: email,
          password: 'password123',
          register: false,
        );

    final local = await DbService.instance.getById(remoteOnlyId);
    expect(local, isNotNull);
    expect(local!.title, 'From server');
  });

  test('a local-only note is pushed up to the server', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final localOnlyId = _uuid.v4();
    await DbService.instance.upsert(_note(id: localOnlyId, title: 'From device'));

    await container.read(syncProvider.notifier).connect(
          url: _testServerUrl,
          email: 'test-${_uuid.v4()}@example.com',
          password: 'password123',
          register: true,
        );

    final remote = await PbService.instance.fetchAll();
    final match = remote.where((n) => n.id == localOnlyId);
    expect(match, hasLength(1));
    expect(match.single.title, 'From device');
  });

  test('when both sides have the same note, the more recently updated one '
      'wins, in either direction', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final newerLocalId = _uuid.v4();
    final newerRemoteId = _uuid.v4();
    final now = DateTime.now();

    // newerLocalId: local copy is deliberately far newer than what will be
    // pushed to the server first.
    await PbService.instance.connect(_testServerUrl);
    final email = 'test-${_uuid.v4()}@example.com';
    await PbService.instance.register(email, 'password123');
    await PbService.instance.upsert(
      _note(id: newerLocalId, title: 'Stale server copy'),
    );
    // newerRemoteId: local copy is deliberately far older; the version
    // that will exist on the server (created just now) must win.
    await PbService.instance.upsert(
      _note(id: newerRemoteId, title: 'Fresh server copy'),
    );
    await PbService.instance.disconnect();

    await DbService.instance.upsert(_note(
      id: newerLocalId,
      title: 'Fresh local edit',
      updated: now.add(const Duration(days: 1)),
    ));
    await DbService.instance.upsert(_note(
      id: newerRemoteId,
      title: 'Stale local copy',
      updated: now.subtract(const Duration(days: 1)),
    ));

    await container.read(syncProvider.notifier).connect(
          url: _testServerUrl,
          email: email,
          password: 'password123',
          register: false,
        );

    // Local's newer edit should have been pushed up, not overwritten.
    final remoteAfter = await PbService.instance.fetchAll();
    expect(
      remoteAfter.firstWhere((n) => n.id == newerLocalId).title,
      'Fresh local edit',
    );

    // The server's newer copy should have overwritten the stale local one.
    final localAfter = await DbService.instance.getById(newerRemoteId);
    expect(localAfter!.title, 'Fresh server copy');
  });

  test('a note deleted on another device while this one was offline is '
      'removed locally on reconnect, not resurrected by pushing the stale '
      'local copy back up', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final noteId = _uuid.v4();
    final email = 'test-${_uuid.v4()}@example.com';

    // Seed the note as already synced before this device went offline:
    // present both locally and on the server.
    await PbService.instance.connect(_testServerUrl);
    await PbService.instance.register(email, 'password123');
    await PbService.instance.upsert(_note(id: noteId, title: 'Shared note'));
    await DbService.instance.upsert(_note(id: noteId, title: 'Shared note'));

    // Another device deletes it while this one is offline - done directly
    // via PbService, bypassing this "device"'s local DB, exactly like a
    // delete it never saw happen.
    await PbService.instance.delete(noteId);
    await PbService.instance.disconnect();

    // This device reconnects and reconciles, still holding its stale
    // local copy.
    await container.read(syncProvider.notifier).connect(
          url: _testServerUrl,
          email: email,
          password: 'password123',
          register: false,
        );

    final localAfter = await DbService.instance.getById(noteId);
    expect(localAfter, isNull);

    // And the stale local copy must not have been pushed back up either,
    // un-deleting it on the server.
    final remoteAfter = await PbService.instance.fetchAll();
    final remoteNote = remoteAfter.firstWhere((n) => n.id == noteId);
    expect(remoteNote.deleted, isTrue);
  });

  test('when one device deletes a note and another edited it offline, a '
      'newer delete wins and discards the older edit', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final noteId = _uuid.v4();
    final email = 'test-${_uuid.v4()}@example.com';

    // Seed as already synced, then another device deletes it - the
    // tombstone's updated timestamp is server-assigned (autodate), so it's
    // "now" at the moment this call runs, slightly after the seed above.
    await PbService.instance.connect(_testServerUrl);
    await PbService.instance.register(email, 'password123');
    await PbService.instance.upsert(_note(id: noteId, title: 'Original'));
    await PbService.instance.delete(noteId);
    await PbService.instance.disconnect();

    // This device's own local edit happened well before that delete -
    // pinned to a full day in the past so there's no ambiguity about
    // ordering against the real-time tombstone above.
    await DbService.instance.upsert(_note(
      id: noteId,
      title: 'Local edit made before the delete',
      updated: DateTime.now().subtract(const Duration(days: 1)),
    ));

    await container.read(syncProvider.notifier).connect(
          url: _testServerUrl,
          email: email,
          password: 'password123',
          register: false,
        );

    // The delete is newer, so it wins: the older local edit is discarded
    // and the note ends up deleted, not pushed back up to resurrect it.
    final localAfter = await DbService.instance.getById(noteId);
    expect(localAfter, isNull);

    final remoteAfter = await PbService.instance.fetchAll();
    expect(remoteAfter.firstWhere((n) => n.id == noteId).deleted, isTrue);
  });

  test('when one device deletes a note and another edited it offline, a '
      'newer edit wins and undoes the older delete', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final noteId = _uuid.v4();
    final email = 'test-${_uuid.v4()}@example.com';

    // Seed as already synced, then another device deletes it - the
    // tombstone gets a server-assigned "now" timestamp.
    await PbService.instance.connect(_testServerUrl);
    await PbService.instance.register(email, 'password123');
    await PbService.instance.upsert(_note(id: noteId, title: 'Original'));
    await PbService.instance.delete(noteId);
    await PbService.instance.disconnect();

    // This device's own local edit happened after that delete - pinned to
    // a full day in the future so there's no ambiguity about ordering
    // against the real-time tombstone above.
    await DbService.instance.upsert(_note(
      id: noteId,
      title: 'Local edit made after the delete',
      updated: DateTime.now().add(const Duration(days: 1)),
    ));

    await container.read(syncProvider.notifier).connect(
          url: _testServerUrl,
          email: email,
          password: 'password123',
          register: false,
        );

    // The edit is newer, so it wins: it survives locally, and gets pushed
    // up, clearing the tombstone (Note.toPocketBase always sends
    // deleted:false) rather than being blocked by the older delete.
    final localAfter = await DbService.instance.getById(noteId);
    expect(localAfter, isNotNull);
    expect(localAfter!.title, 'Local edit made after the delete');

    final remoteAfter = await PbService.instance.fetchAll();
    final remoteNote = remoteAfter.firstWhere((n) => n.id == noteId);
    expect(remoteNote.deleted, isFalse);
    expect(remoteNote.title, 'Local edit made after the delete');
  });
}
