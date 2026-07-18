@Tags(['integration'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/providers/sync_provider.dart';
import 'package:jotes/services/db_service.dart';
import 'package:jotes/services/pb_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Exercises SyncNotifier's merge-on-connect logic against the same live
/// PocketBase instance used by pb_service_integration_test.dart (see
/// backend/Dockerfile), combined with a real local FFI-backed DbService -
/// the merge algorithm's correctness depends on the interaction between
/// both real stores, not just one in isolation.
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
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
}
