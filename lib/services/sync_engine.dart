import 'db_service.dart';
import 'notification_service.dart';
import 'pb_service.dart';
import 'snooze_settings.dart';
import 'widget_service.dart';

/// One-time reconciliation between local and remote storage: newer-wins by
/// `updated` timestamp in either direction, and anything local-only gets
/// pushed up. Used by the live app on connect/reconnect (see SyncNotifier
/// in sync_provider.dart, which also refreshes Riverpod state afterward),
/// by [UnifiedPushService]'s background message handler (which has no
/// widget tree / ProviderContainer to route through - a push notification
/// only carries a lightweight "something changed" hint, see backend/push.go,
/// not the changed data itself, so reacting to one always means doing this
/// same full reconciliation rather than a targeted update), and by
/// main.dart's `--periodic-refresh` headless entrypoint (best-effort there,
/// specifically so a device whose push delivery isn't working reliably -
/// e.g. no UnifiedPush distributor installed - still catches up on
/// cross-device changes, like another device's Dismiss, within one
/// ~15-minute cycle instead of only on next app open).
Future<void> mergeSync() async {
  if (!PbService.instance.isLoggedIn) return;
  await PbService.instance.refreshAuth();
  try {
    await SnoozeSettings.instance.pullFromServer();
  } catch (_) {
    // Not fatal - see below for the same reasoning; the note sync this
    // function exists for must proceed regardless.
  }

  final local = await DbService.instance.getAll();
  final localById = {for (final n in local) n.id: n};
  final remote = await PbService.instance.fetchAll();
  final remoteById = {for (final n in remote) n.id: n};

  for (final r in remote) {
    final l = localById[r.id];
    if (l == null || l.updated.isBefore(r.updated)) {
      if (r.deleted) {
        await DbService.instance.delete(r.id);
        try {
          await NotificationService.instance.cancel(r.notificationId);
        } catch (_) {
          // Not fatal - the note is already deleted either way.
        }
      } else {
        await DbService.instance.upsert(r);
        // Only touches this note's notification if its reminder actually
        // changed (see reconcile's own doc comment) - without this, a
        // reminder change pulled in by a full reconciliation (e.g. this
        // device was offline when it happened) would silently never reach
        // this device's own alarm/tray state at all.
        await NotificationService.instance.reconcile(l, r);
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

  // This is the one path that changes note data with no Riverpod
  // ProviderContainer available at all (see the class doc above) - a
  // headless push-driven merge would otherwise leave home-screen widgets
  // showing stale data until the app is next foregrounded. NotesNotifier
  // .build() covers every other path (see notes_provider.dart).
  await WidgetService.instance.syncAll(await DbService.instance.getAll());
}
