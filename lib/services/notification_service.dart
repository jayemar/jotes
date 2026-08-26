import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/note.dart';
import 'background_sync_service.dart';
import 'db_service.dart';
import 'snooze_settings.dart';

const _channelId = 'jotes_reminders';
const _channelName = 'Reminders';

// Ids for the notification actions below - reported back via
// NotificationResponse.actionId in handleBackgroundReminderAction.
const _dismissActionId = 'dismiss';
const _snoozeActionId = 'snooze';

/// Note ids whose reminder has already been handled once - either fired
/// normally via AlarmManager, or shown immediately as an overdue catch-up
/// (see showOverdueIfNotAlready) - so a reminder is never shown twice, and
/// a long-past reminder that already fired isn't mistaken for one that was
/// never delivered. Deliberately local/per-device (SharedPreferences, not
/// synced), matching how each device's own alarm delivery is independent.
///
/// Distinct from [Note.reminderResolved]: "handled" means delivery was
/// attempted for the current cycle on *this* device, "resolved" means the
/// user actually acted on it, from *any* device - see Note.reminderResolved's
/// own doc comment for why that one is synced instead. Keeping these
/// separate matters because "handled" is checked from a path that runs
/// often (every sync reconnect/push, via rescheduleAll), while a resolved
/// check is only meant to gate a once-per-app-launch restart-recovery check
/// - if they were the same flag, a still-unresolved reminder would get
/// re-posted (and likely re-alert) every time a sync cycle ran, not just
/// after an actual restart.
const _handledReminderIdsPrefsKey = 'handled_reminder_note_ids';

NotificationDetails _reminderNotificationDetails(Note note) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(note.body),
      category: AndroidNotificationCategory.alarm,
      // Deliberately false (the default) - a reminder should behave like
      // an ordinary high-importance notification (heads-up while
      // unlocked, sound/vibration plus whatever ambient/lock-screen peek
      // the device itself offers), not take over the screen and launch
      // the app on its own. This was briefly turned back on (see git
      // history) for the screen-off-wakes-up case Android's docs promise
      // for this flag, then reverted again: USE_FULL_SCREEN_INTENT is a
      // Settings-granted permission that a sideloaded (non-Play-Store)
      // install of this app appears to lose on every update, with no
      // fix available from app code - the OS, not jotes, decides whether
      // a previously-granted USE_FULL_SCREEN_INTENT survives an update,
      // so re-enabling it just means re-granting it after every future
      // build. Tapping the notification still opens the reminder popup as
      // before (see onNoteTapped/getLaunchNoteId in main.dart) - only the
      // automatic, un-tapped takeover is gone.
      fullScreenIntent: false,
      // Without this, merely tapping the notification to view it (which
      // the plugin treats as the same thing as opening it) auto-cancels it
      // before the user picks anything in the popup - silently breaking
      // "Ignore" (and "Open note," which also shouldn't clear it - opening
      // a note to look at it isn't deciding you're done with its
      // reminder). Only Dismiss/Snooze should ever clear the tray entry,
      // and they do so explicitly via cancel() instead.
      autoCancel: false,
      // A swipe otherwise removes the notification with no way for the
      // app to find out - Android has no callback for that - leaving
      // resolved/handled state permanently out of sync with what's
      // actually in the tray. Marking it ongoing disables swipe-to-dismiss
      // (and "Clear all") entirely, so the only way to remove it is
      // through Dismiss/Snooze, which already call cancel() explicitly and
      // keep that state correct.
      ongoing: true,
      // Real inline buttons on the notification itself, usable straight
      // from the shade with no app UI ever opening (showsUserInterface:
      // false routes the tap to handleBackgroundReminderAction below,
      // not onDidReceiveNotificationResponse). Snooze can't offer an
      // arbitrary date/time picker here - Android has no such picker UI
      // that renders inside a notification action - so it uses a single
      // fixed duration instead, configured once in Settings (see
      // SnoozeSettings) rather than as a per-action choice - three buttons
      // (Dismiss + two fixed-duration snoozes) didn't reliably fit
      // on-screen, so this collapsed to two. Distinct from Dismiss/Snooze
      // inside the reminder popup shown when the notification *body* is
      // tapped (see reminder_popup.dart), which is unaffected by this.
      actions: const [
        AndroidNotificationAction(
          _dismissActionId,
          'Dismiss',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _snoozeActionId,
          'Snooze',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    ),
  );
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _tapController = StreamController<String>.broadcast();

  /// Emits a note id whenever a delivered reminder notification is tapped
  /// while the app process is already running (foreground or background).
  /// A tap that cold-starts the app instead is handled by [getLaunchNoteId].
  Stream<String> get onNoteTapped => _tapController.stream;

  /// [requestPermissions] must be false when called from
  /// handleBackgroundReminderAction's background isolate - confirmed via
  /// on-device logcat that requestNotificationsPermission (and friends)
  /// crash native-side with a NullPointerException there (they need an
  /// Activity, and a background isolate only ever has an
  /// applicationContext). Worse than a normal crash: the native side never
  /// sends a platform-channel result back, so the `await` on it hangs
  /// forever rather than throwing something Dart could catch - silently
  /// stalling this function before it ever reaches
  /// markReminderResolved/cancel/schedule below. Requesting permissions is
  /// meaningless from a background isolate anyway (nothing there could
  /// show a system permission dialog even if the call worked), so this is
  /// skipped entirely rather than merely tolerated.
  Future<void> initialize({bool requestPermissions = true}) async {
    // flutter_local_notifications has no web platform implementation at
    // all - calling into it on web throws before runApp() ever gets a
    // chance to render, leaving a blank page. Reminders are an
    // Android-only feature, so just skip setup entirely on web.
    if (kIsWeb) return;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) {
        final noteId = response.payload;
        if (noteId != null) _tapController.add(noteId);
      },
      onDidReceiveBackgroundNotificationResponse:
          handleBackgroundReminderAction,
    );

    if (!requestPermissions) return;

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
    // No requestFullScreenIntentPermission() call here - fullScreenIntent
    // is deliberately false above, so there's nothing to request it for
    // (and requesting it anyway would just cost a permission prompt this
    // app can't reliably keep granted across updates - see
    // _reminderNotificationDetails' own doc comment on fullScreenIntent).
  }

  /// If the app process was cold-started by tapping a reminder notification,
  /// returns that note's id. Call once, after the navigator is ready to
  /// push a route (onDidReceiveNotificationResponse never fires for this
  /// case, since there's no running app instance yet to deliver it to).
  Future<String?> getLaunchNoteId() async {
    if (kIsWeb) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details?.notificationResponse?.payload;
    } catch (_) {
      // Called from an unawaited post-frame callback at startup; a plugin
      // failure here must not surface as an unhandled app-launch exception.
      return null;
    }
  }

  /// Whether the base notification permission is granted at all - without
  /// this, a scheduled alarm can still fire on time internally but Android
  /// will silently drop the actual notification, with no error surfaced to
  /// the app. This is a separate, more fundamental permission than exact
  /// alarms (see [exactAlarmsPermitted]) and must be checked independently.
  /// Defaults to true on platforms with no such platform-specific
  /// implementation (e.g. web), since the concept doesn't apply there.
  Future<bool> notificationsEnabled() async {
    if (kIsWeb) return true;
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidImpl?.areNotificationsEnabled() ?? true;
    } catch (_) {
      // Called from an unawaited post-frame callback on the main notes
      // list - a plugin failure here must not surface as an unhandled
      // exception, and there's nothing more useful to do than skip the
      // warning banner.
      return true;
    }
  }

  /// Re-prompts for the base notification permission. Android only shows
  /// the system dialog once per install; if the user already denied it,
  /// this silently no-ops rather than re-prompting, and the user must
  /// enable it manually via system Settings.
  Future<void> requestNotificationsAccess() async {
    if (kIsWeb) return;
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
  }

  /// Whether exact alarms are currently permitted, so reminders can
  /// actually fire at their scheduled time. Defaults to true on platforms
  /// (e.g. web) with no such platform-specific implementation, since the
  /// concept doesn't apply there.
  Future<bool> exactAlarmsPermitted() async {
    if (kIsWeb) return true;
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidImpl?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Re-prompts for exact-alarm access (on Android 12+ this opens the
  /// system "Alarms & reminders" settings screen, since it isn't grantable
  /// via a normal in-app permission dialog).
  Future<void> requestExactAlarmsAccess() async {
    if (kIsWeb) return;
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestExactAlarmsPermission();
  }

  /// Overridable by tests to observe schedule() without touching the real
  /// plugin - same reasoning as debugOnCancel/debugOnShow. Unlike those,
  /// most existing tests actually want the real (throwing) schedule() path
  /// - see notes_provider_test.dart - so this stays null by default and is
  /// only set where the resulting handled/resolved bookkeeping matters more
  /// than exercising the genuine plugin call.
  void Function(Note note)? debugOnSchedule;

  Future<void> schedule(Note note) async {
    if (kIsWeb) return;
    if (note.reminderAt == null) return;
    final fireTime = note.reminderAt!;
    if (!fireTime.isAfter(DateTime.now())) return;

    if (debugOnSchedule != null) {
      debugOnSchedule!(note);
    } else {
      await _plugin.zonedSchedule(
        note.notificationId,
        note.title.isEmpty ? 'Reminder' : note.title,
        note.body.isEmpty ? 'You have a note reminder.' : note.body,
        tz.TZDateTime.from(fireTime, tz.local),
        _reminderNotificationDetails(note),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: note.id,
      );
    }
    // Marked handled now (not only once it actually fires, which this
    // plugin gives no callback for) so that once its time eventually
    // passes, withOverdueReminders/showOverdueIfNotAlready don't mistake
    // an alarm Android already scheduled normally for one that was never
    // delivered at all.
    await _markReminderHandled(note.id);
    // Unlike the old local-only "resolved" flag, note.reminderResolved
    // doesn't need clearing here for a fresh cycle - whoever set this
    // note's new (future) reminderAt is responsible for also setting
    // reminderResolved: false on the same Note, so it already arrives here
    // correct (see Note.reminderResolved's own doc comment).
  }

  /// Shows a reminder immediately rather than scheduling it for later -
  /// for a note whose reminder time has already passed by the time this
  /// device learns about it (e.g. synced in via a push that arrived after
  /// a short-lead-time reminder's fire time), which schedule() above
  /// would otherwise silently never show at all, forever. A no-op if this
  /// note's reminder has already been handled once, whether by this same
  /// catch-up or by firing normally through schedule() earlier.
  Future<void> showOverdueIfNotAlready(Note note) async {
    if (kIsWeb) return;
    if (note.reminderAt == null) return;
    if (await _reminderAlreadyHandled(note.id)) return;
    await _showNow(note);
  }

  /// Overridable by tests to observe when a reminder is (re)shown, without
  /// touching the real plugin - same reasoning as debugOnCancel.
  void Function(Note note)? debugOnShow;

  Future<void> _showNow(Note note) async {
    if (debugOnShow != null) {
      debugOnShow!(note);
    } else {
      await _plugin.show(
        note.notificationId,
        note.title.isEmpty ? 'Reminder' : note.title,
        note.body.isEmpty ? 'You have a note reminder.' : note.body,
        _reminderNotificationDetails(note),
        payload: note.id,
      );
    }
    await _markReminderHandled(note.id);
  }

  Future<bool> _reminderAlreadyHandled(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final handled = prefs.getStringList(_handledReminderIdsPrefsKey) ?? [];
    return handled.contains(noteId);
  }

  Future<void> _markReminderHandled(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final handled = prefs.getStringList(_handledReminderIdsPrefsKey) ?? [];
    if (handled.contains(noteId)) return;
    await prefs.setStringList(_handledReminderIdsPrefsKey, [
      ...handled,
      noteId,
    ]);
  }

  /// Overridable by tests to observe cancel() calls without touching the
  /// real plugin, which throws with no platform implementation registered
  /// in flutter_test's VM environment (matching DbService.debugFactory's
  /// same reasoning) - set, this replaces the real plugin call entirely
  /// rather than just being notified alongside it.
  void Function(int notificationId)? debugOnCancel;

  Future<void> cancel(int notificationId) async {
    if (debugOnCancel != null) {
      debugOnCancel!(notificationId);
      return;
    }
    if (kIsWeb) return;
    await _plugin.cancel(notificationId);
  }

  /// Reconciles this device's local alarm/tray notification for [next]
  /// against [previous] (the locally-stored copy from just before this
  /// save - null for a brand-new note) - cancels and/or reschedules *only*
  /// if a reminder-relevant field actually changed (reminderAt or
  /// reminderResolved), leaving an edit to an unrelated field (title, body,
  /// color) from touching notifications at all. Used by both
  /// NotesNotifier.addOrUpdate (a local edit) and
  /// SyncNotifier._handleRemoteEvent (an incoming remote one), replacing
  /// what both used to do: cancel unconditionally on every single save,
  /// then reschedule only if a reminder was still due. That was riskier
  /// than it looked - a transient schedule() failure (or the app process
  /// dying between the two calls) silently dropped an otherwise-untouched
  /// reminder, and even without a failure, saving an unrelated field while
  /// an already-fired reminder sat visible in the tray cancelled that
  /// notification for no reason, with no reminderAt change to trigger a
  /// re-post. rescheduleAll/restoreUnresolvedReminders remain the periodic
  /// safety net for anything this diff-based check itself misses (e.g. an
  /// initial schedule() call that failed silently).
  ///
  /// Returns the scheduling error's description if scheduling failed, same
  /// contract as [schedule] - this method itself never throws, so callers
  /// don't need their own try/catch around it.
  Future<String?> reconcile(Note? previous, Note next) async {
    final reminderChanged = previous?.reminderAt != next.reminderAt;
    final resolvedChanged =
        previous?.reminderResolved != next.reminderResolved;
    if (!reminderChanged && !resolvedChanged) return null;

    try {
      await cancel(next.notificationId);
    } catch (_) {
      // Not meaningful on its own - proceed to (re)scheduling regardless.
    }

    final dueInFuture =
        next.reminderAt != null && next.reminderAt!.isAfter(DateTime.now());
    if (!dueInFuture || next.reminderResolved) return null;

    try {
      await schedule(next);
    } catch (e) {
      return e.toString();
    }
    return null;
  }

  /// Re-asserts every note's reminder state without ever wiping anything
  /// first: each future reminder's schedule() call naturally replaces
  /// whatever alarm already exists under that note's id (Android/
  /// flutter_local_notifications both treat a fresh zonedSchedule for the
  /// same id as superseding the old one), and showOverdueIfNotAlready
  /// already only re-posts an overdue reminder that hasn't been handled
  /// yet. This used to open with a blanket _plugin.cancelAll() "for good
  /// measure" - except that also wipes every currently *visible*
  /// notification for an already-fired, still-unresolved reminder, and
  /// since this runs on every sync (app open, pull-to-refresh, periodic
  /// background refresh, every incoming push), that meant a reminder you
  /// were actively looking at in the tray could vanish out from under you
  /// for no reason connected to anything you did. Cleaning up a genuinely
  /// stale alarm (the note itself deleted, or its reminder cleared/
  /// resolved) is instead each specific mutation's own job now - see
  /// NotificationService.reconcile, used by NotesNotifier.addOrUpdate,
  /// SyncNotifier._handleRemoteEvent, and mergeSync.
  Future<void> rescheduleAll() async {
    if (kIsWeb) return;
    final notes = await DbService.instance.withFutureReminders();
    for (final note in notes) {
      // One note failing to (re)schedule (e.g. a transient plugin error)
      // must not silently cost every other note later in this list its
      // alarm too, which an unguarded loop would do.
      try {
        await schedule(note);
      } catch (_) {
        // Nothing more useful to do here: this runs from a background
        // sync path with no UI to report a per-note failure through (see
        // addOrUpdate in notes_provider.dart for the interactive-path
        // equivalent, which does surface an error).
      }
    }

    final overdue = await DbService.instance.withOverdueReminders();
    for (final note in overdue) {
      try {
        await showOverdueIfNotAlready(note);
      } catch (_) {
        // Same reasoning as above.
      }
    }
  }

  /// Overridable by tests to stand in for the plugin's real
  /// getActiveNotifications() (which throws with no platform implementation
  /// registered under flutter_test) - same reasoning as debugOnCancel/
  /// debugOnShow. Returns the set of notification ids currently in the tray.
  Future<Set<int>> Function()? debugActiveNotificationIds;

  /// The notification ids currently showing in the system tray. Used by
  /// [restoreUnresolvedReminders] to avoid re-posting (and thus re-alerting)
  /// a reminder that's already visible. On any failure, returns an empty
  /// set so restore falls back to its old always-repost behavior - better a
  /// possible duplicate alert than a reminder that silently never reappears.
  Future<Set<int>> _activeNotificationIds() async {
    if (debugActiveNotificationIds != null) {
      return debugActiveNotificationIds!();
    }
    try {
      final active = await _plugin.getActiveNotifications();
      return {
        for (final n in active)
          if (n.id != null) n.id!,
      };
    } catch (_) {
      return <int>{};
    }
  }

  /// Re-posts any overdue reminder the user hasn't resolved yet (Dismiss or
  /// Snooze) - covers both "never delivered at all" and "was delivered but
  /// is still sitting unacknowledged," which look identical from here
  /// (resolved=false either way). Intended to be called exactly once, at
  /// genuine app process startup (see main.dart) - unlike
  /// showOverdueIfNotAlready/rescheduleAll, which run on every sync
  /// reconnect and every push and must not re-alert on every one of those
  /// for a reminder the user simply hasn't gotten to yet.
  ///
  /// A repeating reminder is treated exactly like a non-repeating one here -
  /// it only advances to its next occurrence via an explicit Dismiss (see
  /// [noteAfterDismiss]), never just because its own [Note.reminderAt] has
  /// passed. A previous version rolled an overdue repeating reminder
  /// forward on a timer regardless of whether the user had acted on it,
  /// which meant a reminder swiped away in the notification shade (a
  /// dismissal Android gives this app no callback for - see the `ongoing`
  /// flag in _reminderNotificationDetails) silently moved on to tomorrow
  /// instead of continuing to demand attention the way every other missed
  /// reminder in this app does.
  Future<void> restoreUnresolvedReminders() async {
    if (kIsWeb) return;
    final overdue = await DbService.instance.withOverdueReminders();
    if (overdue.isEmpty) return;
    // Skip anything already in the tray, so a normal app-open (where the
    // reminder is still showing) doesn't re-post and thus re-alert
    // (sound/vibrate/full-screen) something the user can already see.
    // After a reboot the tray is wiped, so this set is empty and the
    // reminders genuinely get re-posted - which is the whole point of
    // this method.
    final activeIds = await _activeNotificationIds();
    for (final note in overdue) {
      try {
        if (note.reminderResolved) continue;
        if (activeIds.contains(note.notificationId)) continue;
        await _showNow(note);
      } catch (_) {
        // Same reasoning as rescheduleAll's per-note isolation above.
      }
    }
  }
}

/// Handles a tap on Dismiss/Snooze directly on a fired reminder's
/// notification, entirely in the background - no app UI ever shows (see
/// the `actions` list in _reminderNotificationDetails and this function's
/// registration as onDidReceiveBackgroundNotificationResponse in
/// NotificationService.initialize). The plugin invokes this in its own
/// isolate, separate from - and not sharing state/singletons with - any
/// already-running main app isolate, so this re-initializes what it needs
/// itself, the same idea as main.dart's --boot-restore entrypoint.
///
/// Both actions explicitly cancel the tray notification via
/// NotificationService.cancel - the same call reminder_popup.dart's own
/// in-app Dismiss/Snooze make - rather than relying solely on the
/// `cancelNotification: true` already set on both AndroidNotificationActions
/// in _reminderNotificationDetails; that flag alone wasn't reliably
/// clearing the tray entry on-device. Both actions therefore need one DB
/// *read* to look up the note's notificationId (a stable hash of its id -
/// see Note.notificationId), which carries none of the cross-isolate risk
/// below (that only applies to concurrent writers).
///
/// Both actions now also write to the local notes DB (Dismiss to persist
/// reminderResolved: true, Snooze the note's new reminderAt) and enqueue a
/// [BackgroundSyncService] task to push that up, so acting on a reminder
/// here is visible to every other device, not just this one - see
/// Note.reminderResolved's own doc comment. Enqueuing (not pushing inline,
/// as this used to) is deliberate - see BackgroundSyncService's own doc
/// comment for why this isolate can't be trusted to survive long enough to
/// finish an HTTP request itself. sembast has no cross-isolate/cross-process
/// file locking (checked directly), so a concurrent write from here while
/// the main app might also have the DB open is a real if narrow risk,
/// accepted for both actions since there's no way to record either outcome
/// without persisting something. The snooze duration itself comes from
/// SnoozeSettings (plain SharedPreferences, not Riverpod - this isolate has
/// no ProviderScope to read from).
@pragma('vm:entry-point')
Future<void> handleBackgroundReminderAction(
  NotificationResponse response,
) async {
  final noteId = response.payload;
  final actionId = response.actionId;
  if (noteId == null || actionId == null) return;

  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Needed for schedule()'s real zonedSchedule call below to work
    // correctly on a real device, since this fresh isolate hasn't set up
    // the plugin's native side yet. Caught separately from the rest of
    // this function's logic: this throws under flutter_test (no platform
    // implementation registered there), but the rest of this function
    // stays directly unit-testable regardless, via the debug hooks
    // markReminderResolved/schedule/DbService already have.
    //
    // requestPermissions: false is required, not optional - see
    // initialize()'s own doc comment for why requesting permissions here
    // hangs this call forever on a real device instead of throwing.
    await NotificationService.instance.initialize(requestPermissions: false);
  } catch (_) {}

  try {
    final note = await DbService.instance.getById(noteId);

    if (actionId == _dismissActionId) {
      if (note == null) return; // deleted since the reminder fired - nothing to mark
      // Failure here must not skip persisting reminderResolved below - same
      // reasoning as the Snooze branch's own cancel-then-persist ordering.
      try {
        await NotificationService.instance.cancel(note.notificationId);
      } catch (_) {}

      // noteAfterDismiss rolls reminderAt forward (leaving
      // reminderResolved false) instead of marking this cycle resolved
      // when the note repeats - see its own doc comment.
      final resolved = noteAfterDismiss(note);
      await DbService.instance.upsert(resolved);
      if (!resolved.reminderResolved) {
        // The reminder repeats and just advanced to its next occurrence -
        // schedule it, same as the Snooze branch below does for its own
        // new reminderAt.
        await NotificationService.instance.schedule(resolved);
      }
      try {
        await BackgroundSyncService.instance.enqueue();
      } catch (_) {
        // Best-effort - the local DB write above already succeeded, and
        // the next foreground sync/reconnect will catch this up regardless.
      }
      return;
    }
    if (actionId != _snoozeActionId) return;
    if (note == null) return; // deleted since the reminder fired

    // Failure here must not skip the reschedule below - same reasoning as
    // the Dismiss branch above.
    try {
      await NotificationService.instance.cancel(note.notificationId);
    } catch (_) {}

    final newReminderAt = await SnoozeSettings.instance.resolveNext();

    final updated = note.copyWith(
      reminderAt: newReminderAt,
      reminderResolved: false,
      updated: DateTime.now(),
    );
    await DbService.instance.upsert(updated);
    await NotificationService.instance.schedule(updated);

    try {
      await BackgroundSyncService.instance.enqueue();
    } catch (_) {
      // Best-effort - the local DB write above already succeeded, and
      // the next foreground sync/reconnect will catch this up regardless.
    }
  } catch (_) {
    // Nothing more useful to do from a background isolate with no UI.
  }
}
