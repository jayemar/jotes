import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../services/db_service.dart';
import '../services/notification_service.dart';
import '../services/pb_service.dart';
import 'notes_provider.dart';

enum SyncStatus { disconnected, connecting, connected, error }

class SyncState {
  final SyncStatus status;
  final String? errorMessage;
  final String? serverUrl;
  final String? userEmail;

  const SyncState({
    required this.status,
    this.errorMessage,
    this.serverUrl,
    this.userEmail,
  });

  static const initial = SyncState(status: SyncStatus.disconnected);
}

class SyncNotifier extends Notifier<SyncState> {
  @override
  SyncState build() {
    _restore();
    return SyncState.initial;
  }

  Future<void> _restore() async {
    await PbService.instance.restore();
    if (!PbService.instance.isLoggedIn) return;

    state = SyncState(
      status: SyncStatus.connected,
      serverUrl: PbService.instance.serverUrl,
      userEmail: PbService.instance.userEmail,
    );
    await _startSync();
  }

  Future<void> connect({
    required String url,
    required String email,
    required String password,
    required bool register,
  }) async {
    state = const SyncState(status: SyncStatus.connecting);
    try {
      await PbService.instance.connect(url);
      if (register) {
        await PbService.instance.register(email, password);
      } else {
        await PbService.instance.login(email, password);
      }
      state = SyncState(
        status: SyncStatus.connected,
        serverUrl: url,
        userEmail: email,
      );
      await _startSync();
    } catch (e) {
      state = SyncState(status: SyncStatus.error, errorMessage: e.toString());
    }
  }

  Future<void> disconnect() async {
    PbService.instance.unsubscribe();
    await PbService.instance.disconnect();
    state = SyncState.initial;
  }

  Future<void> _startSync() async {
    await _mergeSync();
    PbService.instance.subscribe(_handleRemoteEvent);
  }

  /// One-time reconciliation on connect: newer-wins by `updated` timestamp
  /// in either direction, and anything local-only gets pushed up. After
  /// this, [PbService.subscribe] takes over for ongoing changes.
  Future<void> _mergeSync() async {
    final local = await DbService.instance.getAll();
    final localById = {for (final n in local) n.id: n};
    final remote = await PbService.instance.fetchAll();
    final remoteById = {for (final n in remote) n.id: n};

    for (final r in remote) {
      final l = localById[r.id];
      if (l == null || l.updated.isBefore(r.updated)) {
        await DbService.instance.upsert(r);
      }
    }

    for (final l in local) {
      final r = remoteById[l.id];
      if (r == null || l.updated.isAfter(r.updated)) {
        await PbService.instance.upsert(l);
      }
    }

    try {
      await NotificationService.instance.rescheduleAll();
    } catch (_) {
      // Notes are already saved; a failed reminder reschedule is not fatal.
    }

    ref.invalidate(notesProvider);
  }

  Future<void> _handleRemoteEvent(String action, Note? note) async {
    if (note == null) return;

    if (action == 'delete') {
      await DbService.instance.delete(note.id);
      try {
        await NotificationService.instance.cancel(note.notificationId);
      } catch (_) {
        // Not fatal - see addOrUpdate in notes_provider.dart for the same
        // reasoning.
      }
    } else {
      await DbService.instance.upsert(note);
      try {
        await NotificationService.instance.cancel(note.notificationId);
        if (note.reminderAt != null &&
            note.reminderAt!.isAfter(DateTime.now())) {
          await NotificationService.instance.schedule(note);
        }
      } catch (_) {
        // Not fatal - see addOrUpdate in notes_provider.dart for the same
        // reasoning.
      }
    }

    ref.invalidate(notesProvider);
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
