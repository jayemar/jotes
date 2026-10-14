import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/note.dart';

const _enabledPrefsKey = 'calendar_sync_enabled';
const _calendarIdPrefsKey = 'calendar_sync_calendar_id';
const _eventLinksPrefsKey = 'calendar_sync_event_links';

/// One-way mirror (jotes -> device calendar) of every note with an
/// active/pending reminder (see [notesWithActiveOrPendingReminders]) into
/// one calendar on this device, via the native Calendar Provider
/// (device_calendar plugin) - so a reminder also shows up wherever that
/// calendar is already being synced (Google Calendar, etc.), without jotes
/// needing its own account/OAuth integration. Deliberately one-way: a
/// calendar app has no way to tell jotes "the user changed this event,"
/// and reconciling that would mean polling/watching the whole calendar for
/// changes just to recognize the handful of events jotes itself created -
/// disproportionate for what this is meant to be (a convenience mirror,
/// not a second source of truth).
///
/// Off by default - this needs calendar read/write permission, which is
/// requested the first time the user actually turns the Settings toggle
/// on, not unprompted at app launch. [reconcile] (called from the same
/// three sites that already call NotificationService.reconcile - see its
/// own doc comment) is a no-op whenever this is off, so nothing in the
/// normal note-save/sync path needs its own "is calendar sync even
/// enabled" check.
///
/// Each calendar event's id is purely local bookkeeping (the native
/// Calendar Provider mints it per-device, so there's nothing to sync here
/// even if jotes wanted to - two devices each create their own separate
/// event for the same note) - kept in SharedPreferences, not the synced
/// [Note] itself.
class CalendarSyncService {
  static final CalendarSyncService instance = CalendarSyncService._();
  CalendarSyncService._();

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledPrefsKey) ?? false;
  }

  Future<String?> selectedCalendarId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_calendarIdPrefsKey);
  }

  /// Checks (and if needed, asks for) calendar read/write permission -
  /// every other method here that touches the native calendar calls this
  /// first, so Settings' own enable flow is the only place that needs to
  /// think about the permission prompt directly.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    if (debugRequestPermission != null) return debugRequestPermission!();
    final existing = await _plugin.hasPermissions();
    if (existing.isSuccess && existing.data == true) return true;
    final requested = await _plugin.requestPermissions();
    return requested.isSuccess && requested.data == true;
  }

  /// Every writable calendar on this device - the choices Settings' own
  /// calendar picker offers. Empty (rather than throwing) if permission
  /// was denied or the plugin otherwise fails, so the picker can just show
  /// "no calendars available" instead of crashing the Settings screen.
  Future<List<Calendar>> availableCalendars() async {
    if (kIsWeb) return [];
    if (debugAvailableCalendars != null) return debugAvailableCalendars!();
    if (!await requestPermission()) return [];
    try {
      final result = await _plugin.retrieveCalendars();
      final calendars = result.data?.toList() ?? <Calendar>[];
      return calendars.where((c) => c.isReadOnly != true).toList();
    } catch (_) {
      return [];
    }
  }

  /// Turns calendar sync on (backfilling [notesWithActiveOrPendingReminders]
  /// into [calendarId]) or off (removing every event this device has ever
  /// created for jotes and forgetting the mapping, rather than leaving
  /// them to drift out of sync with notes that keep changing while this
  /// is off). [calendarId] is required when enabling; ignored when
  /// disabling.
  Future<void> setEnabled(bool enabled, {String? calendarId, List<Note>? notes}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await _removeAllEvents();
      await prefs.setBool(_enabledPrefsKey, false);
      return;
    }
    if (calendarId != null) {
      await prefs.setString(_calendarIdPrefsKey, calendarId);
    }
    await prefs.setBool(_enabledPrefsKey, true);
    if (notes != null) await _backfill(notes);
  }

  Future<void> _backfill(List<Note> notes) async {
    for (final note in notesWithActiveOrPendingReminders(notes)) {
      try {
        await _upsertEvent(note);
      } catch (_) {
        // Best-effort - one note's calendar event failing to create must
        // not stop the rest of the backfill.
      }
    }
  }

  Future<void> _removeAllEvents() async {
    final calendarId = await selectedCalendarId();
    final links = await _allLinks();
    if (calendarId != null) {
      for (final eventId in links.values) {
        try {
          await _deleteEvent(calendarId, eventId);
        } catch (_) {}
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_eventLinksPrefsKey);
  }

  /// Mirrors a note's current reminder state into its calendar event -
  /// called from the same three sites that already call
  /// NotificationService.reconcile (NotesNotifier.addOrUpdate,
  /// SyncNotifier._handleRemoteEvent, mergeSync's pull loop), so a
  /// calendar event tracks a note exactly as promptly/consistently as its
  /// tray notification already does. A no-op whenever sync is off, the
  /// note has no active reminder, or nothing calendar-relevant (reminder
  /// time, title, body) actually changed.
  Future<void> reconcile(Note? previous, Note next) async {
    if (!await isEnabled()) return;
    if (next.deleted || next.reminderAt == null) {
      await removeForNote(next);
      return;
    }
    final changed =
        previous == null ||
        previous.reminderAt != next.reminderAt ||
        previous.title != next.title ||
        previous.body != next.body;
    if (!changed) return;
    try {
      await _upsertEvent(next);
    } catch (_) {
      // Best-effort - the note/notification side of this save already
      // succeeded regardless of whether its calendar mirror does too.
    }
  }

  /// Removes [note]'s calendar event, if this device ever created one -
  /// called on note delete (same call sites as
  /// NotificationService.instance.cancel) and from [reconcile] once a
  /// note's reminder is cleared entirely. A harmless no-op if sync is off
  /// or nothing was ever linked.
  Future<void> removeForNote(Note note) async {
    final calendarId = await selectedCalendarId();
    final eventId = await _linkFor(note.id);
    if (calendarId == null || eventId == null) return;
    try {
      await _deleteEvent(calendarId, eventId);
    } catch (_) {
      // Best-effort - still forget the mapping below regardless, so a
      // stale link doesn't linger pointing at an event that (for all we
      // know) no longer exists anyway.
    }
    await _clearLink(note.id);
  }

  Future<void> _upsertEvent(Note note) async {
    final calendarId = await selectedCalendarId();
    final reminderAt = note.reminderAt;
    if (calendarId == null || reminderAt == null) return;
    if (!await requestPermission()) return;

    final existingEventId = await _linkFor(note.id);
    final start = tz.TZDateTime.from(reminderAt, tz.local);
    final event = Event(
      calendarId,
      eventId: existingEventId,
      title: note.title.isEmpty ? 'Reminder' : note.title,
      description: note.body,
      start: start,
      // The native calendar provider rejects a zero-length event on at
      // least some devices - 30 minutes is an arbitrary but harmless
      // placeholder duration, same as jotes' own reminders having no
      // concept of an "end time" to begin with.
      end: start.add(const Duration(minutes: 30)),
    );
    final newEventId = await _createOrUpdateEvent(event);
    if (newEventId != null) await _setLink(note.id, newEventId);
  }

  // --- Thin wrappers around the actual plugin calls, so tests can
  // override just these rather than needing a working platform
  // implementation (which throws under flutter_test) - same reasoning as
  // NotificationService's own debugOnSchedule/debugOnCancel. ---

  /// Overridable by tests to bypass the permission check entirely.
  Future<bool> Function()? debugRequestPermission;

  /// Overridable by tests to stand in for retrieveCalendars().
  Future<List<Calendar>> Function()? debugAvailableCalendars;

  /// Overridable by tests to observe/stand in for createOrUpdateEvent(),
  /// returning the (possibly new) event id.
  Future<String?> Function(Event event)? debugCreateOrUpdateEvent;

  /// Overridable by tests to observe/stand in for deleteEvent().
  Future<void> Function(String calendarId, String eventId)? debugDeleteEvent;

  Future<String?> _createOrUpdateEvent(Event event) async {
    if (debugCreateOrUpdateEvent != null) {
      return debugCreateOrUpdateEvent!(event);
    }
    final result = await _plugin.createOrUpdateEvent(event);
    return (result?.isSuccess ?? false) ? result?.data : null;
  }

  Future<void> _deleteEvent(String calendarId, String eventId) async {
    if (debugDeleteEvent != null) {
      await debugDeleteEvent!(calendarId, eventId);
      return;
    }
    await _plugin.deleteEvent(calendarId, eventId);
  }

  // --- Local-only noteId -> calendar eventId mapping. ---

  Future<Map<String, String>> _allLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_eventLinksPrefsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as String));
    } catch (_) {
      return {};
    }
  }

  Future<String?> _linkFor(String noteId) async => (await _allLinks())[noteId];

  Future<void> _setLink(String noteId, String eventId) async {
    final links = await _allLinks();
    links[noteId] = eventId;
    await _saveLinks(links);
  }

  Future<void> _clearLink(String noteId) async {
    final links = await _allLinks();
    if (links.remove(noteId) == null) return;
    await _saveLinks(links);
  }

  Future<void> _saveLinks(Map<String, String> links) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_eventLinksPrefsKey, jsonEncode(links));
  }
}
