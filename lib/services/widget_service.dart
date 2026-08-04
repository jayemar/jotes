import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:home_widget/home_widget.dart';
import '../models/note.dart';
import '../widgets/note_body_editor.dart'
    show BodyBlock, ChecklistBodyBlock, TextBodyBlock, parseBody;
import 'notification_service.dart';

const _singleNoteReceiver = 'com.jayemar.jotes.SingleNoteWidgetReceiver';
const _reminderListReceiver = 'com.jayemar.jotes.ReminderListWidgetReceiver';
const _remindersDataKey = 'reminders_widget_data';

class WidgetService {
  static final WidgetService instance = WidgetService._();
  WidgetService._();

  /// Lets tests that exercise NotesNotifier/mergeSync without a Flutter
  /// test binding (no pumpWidget, so no platform channel messenger exists
  /// at all) substitute a no-op instead of hitting the real home_widget
  /// MethodChannel - same pattern as DbService.debugFactory and
  /// NotificationService.debugOnCancel.
  Future<void> Function(List<Note> notes)? debugSyncAll;

  /// Pushes current note data to every pinned home-screen widget: the
  /// combined upcoming+overdue reminders list, and each individually
  /// configured Single Note widget instance. Called from the two
  /// chokepoints that already cover every path note data can change
  /// through - NotesNotifier.build() (local mutations + realtime sync) and
  /// sync_engine.dart's mergeSync() (the headless background-push path,
  /// which has no Riverpod ProviderContainer to route through otherwise).
  ///
  /// Both call sites fire this without awaiting/reporting failures back to
  /// the user (unlike e.g. a reminder-schedule failure) - a widget that's
  /// briefly stale is a minor cosmetic issue, not something worth
  /// interrupting note loading or sync over.
  Future<void> syncAll(List<Note> notes) async {
    if (debugSyncAll != null) {
      await debugSyncAll!(notes);
      return;
    }

    // Widgets are an Android home-screen concept - there is nothing to sync
    // to on web, and home_widget has no web implementation to call into.
    if (kIsWeb) return;

    try {
      await _syncReminderList(notes);
      await _syncSingleNoteWidgets(notes);
    } catch (_) {
      // Best-effort - see doc comment above.
    }
  }

  Future<void> _syncReminderList(List<Note> notes) async {
    final payload = await buildReminderListPayload(notes);
    await HomeWidget.saveWidgetData<String>(
      _remindersDataKey,
      jsonEncode(payload),
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: _reminderListReceiver);
  }

  /// Only widget instances that have already been configured with a note
  /// (see widget_note_picker_screen.dart) are written - getInstalledWidgets
  /// is the live source of truth for which instances exist, so there is no
  /// separate registry to keep in sync when a widget is added or removed.
  Future<void> _syncSingleNoteWidgets(List<Note> notes) async {
    final notesById = {for (final n in notes) n.id: n};
    final installed = await HomeWidget.getInstalledWidgets();
    var didSyncAny = false;

    for (final widget in installed) {
      final widgetId = widget.androidWidgetId;
      if (widgetId == null) continue;
      final noteId = await HomeWidget.getWidgetData<String>(
        'note_id.$widgetId',
      );
      final note = noteId != null ? notesById[noteId] : null;
      // The configured note may have since been deleted - leave the
      // widget's last-known data in place rather than clearing it, since
      // there's nothing more current to show.
      if (note == null) continue;

      await HomeWidget.saveWidgetData<String>(
        'note_data.$widgetId',
        jsonEncode(buildSingleNoteJson(note)),
      );
      didSyncAny = true;
    }

    if (didSyncAny) {
      await HomeWidget.updateWidget(qualifiedAndroidName: _singleNoteReceiver);
    }
  }

  /// Every note with a reminder set that the user hasn't resolved yet
  /// (Dismiss or Snooze - see NotificationService.isReminderResolved),
  /// sorted oldest-first - an overdue reminder that's been sitting the
  /// longest sorts above one that just fired, and both sort above anything
  /// still upcoming, forming a single chronological list with no
  /// special-casing needed. `isOverdue` mirrors NoteCard's own
  /// _ReminderChip convention (note_card.dart) so the widget can match its
  /// red/green styling.
  ///
  /// Only overdue notes are checked against resolved state - an upcoming
  /// reminder hasn't fired yet, so "resolved" doesn't apply to it (and
  /// schedule() clears any stale resolution when a note's next cycle
  /// begins anyway - see its own comment), so this always shows it
  /// regardless.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> buildReminderListPayload(
    List<Note> notes, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final withReminders = notes.where((n) => n.reminderAt != null).toList()
      ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));

    final payload = <Map<String, dynamic>>[];
    for (final note in withReminders) {
      final isOverdue = !note.reminderAt!.isAfter(effectiveNow);
      if (isOverdue &&
          await NotificationService.instance.isReminderResolved(note.id)) {
        continue;
      }
      payload.add({
        'id': note.id,
        'title': note.title,
        'reminderAtMillis': note.reminderAt!.millisecondsSinceEpoch,
        'isOverdue': isOverdue,
      });
    }
    return payload;
  }

  /// Also called directly from widget_note_picker_screen.dart when a note
  /// is first chosen for a widget instance, not just internally here.
  static Map<String, dynamic> buildSingleNoteJson(Note note) {
    return {
      'id': note.id,
      'title': note.title,
      'body': note.body,
      // Pre-parsed so SingleNoteWidget.kt can render checklist items as
      // real checkbox glyphs (checked/unchecked, strikethrough), the same
      // way note_card.dart's own preview does, instead of the raw
      // "- [ ] "/"- [x] " markdown syntax [body] above still carries -
      // parsing happens once here rather than duplicating parseBody's
      // regex in Kotlin.
      'blocks': parseBody(note.body).map(_blockJson).toList(),
      'colorIndex': note.colorIndex,
      'reminderAtMillis': note.reminderAt?.millisecondsSinceEpoch,
    };
  }

  static Map<String, dynamic> _blockJson(BodyBlock block) => switch (block) {
    ChecklistBodyBlock() => {
      'type': 'checklist',
      'checked': block.checked,
      'text': block.text,
      'indent': block.indent,
    },
    TextBodyBlock() => {'type': 'text', 'text': block.text},
  };
}
