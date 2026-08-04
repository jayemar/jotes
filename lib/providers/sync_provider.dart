import 'dart:io' show HandshakeException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart' show ClientException;
import '../models/note.dart';
import '../services/db_service.dart';
import '../services/notification_service.dart';
import '../services/pb_service.dart';
import '../services/sync_engine.dart';
import '../services/unifiedpush_service.dart';
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
      state = SyncState(
        status: SyncStatus.error,
        errorMessage: describeConnectError(e),
      );
    }
  }

  Future<void> disconnect() async {
    await PbService.instance.unsubscribe();
    try {
      await UnifiedPushService.instance.unregister();
    } catch (_) {
      // Not fatal - see addOrUpdate in notes_provider.dart for the same
      // reasoning; disconnecting the sync session must still succeed.
    }
    await PbService.instance.disconnect();
    state = SyncState.initial;
  }

  /// Manually re-runs the same reconciliation _startSync already does on
  /// every connect/reconnect - e.g. a "Sync now" button in the UI. A
  /// realtime subscription only delivers while this device's app is
  /// actively open, and the background-push fallback (see
  /// UnifiedPushService) depends on a distributor being installed and
  /// registration having succeeded, which is best-effort and silently
  /// skipped if not - so a change made on another device (most notably a
  /// delete, since a missed one leaves a note lingering rather than just
  /// stale) can otherwise sit unseen indefinitely on a device that hasn't
  /// happened to reconnect since. This lets a stuck device force-pull the
  /// latest state without a full disconnect/reconnect.
  Future<void> resync() async {
    if (state.status != SyncStatus.connected) return;
    await mergeSync();
    ref.invalidate(notesProvider);
  }

  Future<void> _startSync() async {
    await mergeSync();
    ref.invalidate(notesProvider);
    await PbService.instance.subscribe(_handleRemoteEvent);
    try {
      await UnifiedPushService.instance.register();
    } catch (_) {
      // Push is a delivery-reliability improvement, not a requirement -
      // sync already works via _mergeSync/subscribe above without it.
    }
  }

  Future<void> _handleRemoteEvent(String action, Note? note) async {
    if (note == null) return;

    // A user-initiated delete now arrives as an 'update' event carrying
    // deleted:true (soft-delete via PbService.delete - see its own
    // comment for why), not PocketBase's own 'delete' action, though that
    // native action is still handled the same way in case a record is
    // ever actually hard-deleted some other way (e.g. directly in the
    // admin dashboard).
    if (action == 'delete' || note.deleted) {
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

/// PocketBase's ClientException.toString() is technically informative but
/// reads as a raw error dump ({url: ..., originalError: HandshakeException:
/// ... WRONG_VERSION_NUMBER ...}) - not something a self-hoster can act on.
/// A TLS handshake failure against a server actually speaking plain HTTP is
/// a mistake this project's own default deployment invites (backend/
/// Dockerfile starts PocketBase with --http, not --https), so that specific
/// case gets a clear, actionable message; everything else falls back to the
/// exception's own text.
String describeConnectError(Object error) {
  final original = error is ClientException ? error.originalError : null;
  final osErrorMessage = original is HandshakeException
      ? original.osError?.message
      : null;
  if (osErrorMessage?.contains('WRONG_VERSION_NUMBER') ?? false) {
    return "Couldn't establish a secure connection - the server appears to "
        'be speaking plain HTTP, not HTTPS, on this URL. Try http:// '
        'instead of https://.';
  }
  return error.toString();
}
