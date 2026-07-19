import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/note.dart';
import 'db_service.dart';

const _channelId = 'jotes_reminders';
const _channelName = 'Reminders';

/// Note ids whose reminder has already been handled once - either fired
/// normally via AlarmManager, or shown immediately as an overdue catch-up
/// (see showOverdueIfNotAlready) - so a reminder is never shown twice, and
/// a long-past reminder that already fired isn't mistaken for one that was
/// never delivered. Deliberately local/per-device (SharedPreferences, not
/// synced), matching how each device's own alarm delivery is independent.
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
      // Takes over the screen (even locked/app closed) the same way a
      // real alarm clock does, rather than only ever showing a tray
      // notification that's easy to miss. The plugin then treats this
      // exactly like a normal notification tap - see onNoteTapped/
      // getLaunchNoteId in main.dart, which already handle that.
      fullScreenIntent: true,
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

  Future<void> initialize() async {
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
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
    // Needed for the full-screen takeover in schedule() below to actually
    // show over the lock screen on Android 14+; granted by default there
    // for apps with alarm functionality, but requesting explicitly is
    // still the documented, defensive thing to do (see
    // requestFullScreenIntentPermission's own doc comment).
    await androidImpl?.requestFullScreenIntentPermission();
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
              AndroidFlutterLocalNotificationsPlugin>();
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
            AndroidFlutterLocalNotificationsPlugin>();
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
              AndroidFlutterLocalNotificationsPlugin>();
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
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestExactAlarmsPermission();
  }

  Future<void> schedule(Note note) async {
    if (kIsWeb) return;
    if (note.reminderAt == null) return;
    final fireTime = note.reminderAt!;
    if (!fireTime.isAfter(DateTime.now())) return;

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
    // Marked handled now (not only once it actually fires, which this
    // plugin gives no callback for) so that once its time eventually
    // passes, withOverdueReminders/showOverdueIfNotAlready don't mistake
    // an alarm Android already scheduled normally for one that was never
    // delivered at all.
    await _markReminderHandled(note.id);
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

    await _plugin.show(
      note.notificationId,
      note.title.isEmpty ? 'Reminder' : note.title,
      note.body.isEmpty ? 'You have a note reminder.' : note.body,
      _reminderNotificationDetails(note),
      payload: note.id,
    );
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
    await prefs.setStringList(_handledReminderIdsPrefsKey, [...handled, noteId]);
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

  Future<void> rescheduleAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
    final notes = await DbService.instance.withFutureReminders();
    for (final note in notes) {
      // cancelAll() above already wiped every previously scheduled alarm -
      // one note failing to (re)schedule (e.g. a transient plugin error)
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
}
