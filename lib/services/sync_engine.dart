import 'db_service.dart';
import 'notification_service.dart';
import 'pb_service.dart';

/// One-time reconciliation between local and remote storage: newer-wins by
/// `updated` timestamp in either direction, and anything local-only gets
/// pushed up. Used both by the live app on connect/reconnect (see
/// SyncNotifier in sync_provider.dart, which also refreshes Riverpod state
/// afterward) and by [UnifiedPushService]'s background message handler,
/// which has no widget tree / ProviderContainer to route through - a push
/// notification only carries a lightweight "something changed" hint (see
/// backend/push.go), not the changed data itself, so reacting to one always
/// means doing this same full reconciliation rather than a targeted update.
Future<void> mergeSync() async {
  if (!PbService.instance.isLoggedIn) return;

  final local = await DbService.instance.getAll();
  final localById = {for (final n in local) n.id: n};
  final remote = await PbService.instance.fetchAll();
  final remoteById = {for (final n in remote) n.id: n};

  for (final r in remote) {
    final l = localById[r.id];
    if (l == null || l.updated.isBefore(r.updated)) {
      if (r.deleted) {
        await DbService.instance.delete(r.id);
      } else {
        await DbService.instance.upsert(r);
      }
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
}
