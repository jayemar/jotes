import 'package:workmanager/workmanager.dart';

/// The name WorkManager reports back to backgroundSyncCallbackDispatcher's
/// task handler (see main.dart) - shared with [BackgroundSyncService.enqueue]
/// so both sides agree on the same string without duplicating a literal.
const backgroundSyncTaskName = 'background_sync';

/// A single, replaceable unit of work (see [ExistingWorkPolicy.replace] in
/// [BackgroundSyncService.enqueue]) - callers only ever want "make sure a
/// sync happens soon", not a growing queue of redundant ones.
const _backgroundSyncUniqueName = 'background-sync';

/// Hands a full sync off to Android's WorkManager instead of trying to run
/// it inline in whatever isolate happens to be asking for one.
///
/// Exists specifically for NotificationService.handleBackgroundReminderAction:
/// that function runs in a background isolate flutter_local_notifications
/// itself spins up for a Dismiss/Snooze notification-action tap, and that
/// isolate has no completion guarantee at all - confirmed by reading the
/// plugin's own source (its callback_dispatcher.dart calls the registered
/// callback without awaiting it, and the Android receiver that hosts the
/// isolate holds no wake lock/goAsync() token keeping the process alive).
/// The local DB write in that same function is fast enough to reliably
/// finish regardless, but a network push after it was racing against
/// however long Android happened to leave the process running - usually
/// long enough, but with no actual guarantee, which is why a dismiss could
/// silently never reach the server until some later, unrelated sync caught
/// it. WorkManager gives the actual guarantee: the request is persisted to
/// its own on-disk queue before this method even returns, so the sync it
/// describes survives the isolate dying (or the whole process being killed)
/// and is retried automatically - including simply waiting for connectivity
/// via the networkType constraint below - until it succeeds. This mirrors
/// the same reasoning BootRestoreWorker.kt already relies on for a
/// different trigger (device boot), just reached from Dart instead of
/// Kotlin since there's no jotes-owned native receiver in this path to hook
/// a WorkManager enqueue into directly.
///
/// Deliberately has no dependency on sync_engine.dart itself (that lives in
/// main.dart's backgroundSyncCallbackDispatcher instead, which is what
/// actually runs when this task fires) - sync_engine.dart imports
/// notification_service.dart, so this file doing the same would create an
/// import cycle back through NotificationService.handleBackgroundReminderAction,
/// the only caller that needs it.
class BackgroundSyncService {
  static final BackgroundSyncService instance = BackgroundSyncService._();
  BackgroundSyncService._();

  /// Lets tests observe/skip the real Workmanager plugin call, the same way
  /// NotificationService.debugOnCancel etc. do - registerOneOffTask has no
  /// platform implementation under flutter_test.
  Future<void> Function()? debugEnqueue;

  Future<void> enqueue() async {
    if (debugEnqueue != null) {
      await debugEnqueue!();
      return;
    }
    await Workmanager().registerOneOffTask(
      _backgroundSyncUniqueName,
      backgroundSyncTaskName,
      // A second Dismiss/Snooze (or anything else that wants a sync soon)
      // before the first request has run yet should just collapse into it -
      // the eventual mergeSync() already covers everything pending, not
      // just whatever triggered this particular call, so there's nothing to
      // gain from keeping both queued.
      existingWorkPolicy: ExistingWorkPolicy.replace,
      // Lets WorkManager hold the request until connectivity is actually
      // available instead of running (and failing) immediately - the exact
      // gap that silently dropped a push before.
      constraints: Constraints(networkType: NetworkType.connected),
      // High priority: this is a user-visible action (Dismiss/Snooze) that
      // should reach other devices promptly, not whenever WorkManager would
      // otherwise get around to a plain background task.
      expedited: true,
    );
  }
}
