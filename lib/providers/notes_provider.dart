import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../services/db_service.dart';
import '../services/notification_appearance_settings.dart';
import '../services/notification_service.dart';
import '../services/pb_service.dart';
import '../services/widget_service.dart';

class NotesNotifier extends AsyncNotifier<List<Note>> {
  @override
  Future<List<Note>> build() async {
    final notes = await DbService.instance.getAll();
    // Every local mutation and the realtime sync subscription both end in
    // an invalidation that reruns this build(), so this single call keeps
    // home-screen widgets current for both without touching either of
    // those call sites individually. Fire-and-forget: widget sync must
    // never delay the note list itself from loading.
    unawaited(WidgetService.instance.syncAll(notes));
    return notes;
  }

  /// Saves [note] and (re)schedules its reminder notification if the
  /// reminder itself actually changed (see NotificationService.reconcile -
  /// an edit to an unrelated field like title/body/color never touches
  /// notifications at all). Returns the scheduling error's description if
  /// scheduling failed, or null if it succeeded (or there was nothing to
  /// schedule) - the note itself is always saved either way, but callers
  /// that show the user a confirmation (see note_editor_screen.dart) need
  /// to know whether the schedule call actually worked rather than just
  /// assuming success from permission checks alone.
  Future<String?> addOrUpdate(Note note) async {
    final previous = await DbService.instance.getById(note.id);
    await DbService.instance.upsert(note);

    // The note above is already saved; a failed reminder schedule must not
    // block that or the caller's post-save navigation (see
    // note_editor_screen's save-then-pop), so reconcile reports any error
    // back rather than throwing.
    final scheduleError = await NotificationService.instance.reconcile(
      previous,
      note,
    );

    PbService.instance.upsert(note).ignore();

    ref.invalidateSelf();
    return scheduleError;
  }

  Future<void> addAllFromImport(List<Note> notes) async {
    for (final note in notes) {
      await DbService.instance.upsert(note);
      PbService.instance.upsert(note).ignore();
    }

    try {
      await NotificationService.instance.rescheduleAll();
    } catch (_) {
      // Notes are already saved; a failed reminder reschedule is not fatal.
    }

    ref.invalidateSelf();
  }

  Future<void> delete(Note note) async {
    await DbService.instance.delete(note.id);

    // Cancelling a reminder can throw and must never block the delete that
    // already succeeded above.
    try {
      await NotificationService.instance.cancel(note.notificationId);
    } catch (_) {
      // Note is already deleted; a failed notification cancel is not fatal.
    }

    // Best-effort cleanup of the per-note sound/icon entry (see
    // NotificationAppearanceSettings) so its local store doesn't grow
    // forever - not fatal on its own if it fails, same reasoning as the
    // notification cancel above.
    try {
      await NotificationAppearanceSettings.instance.clearForNote(note.id);
    } catch (_) {}

    PbService.instance.delete(note.id).ignore();
    ref.invalidateSelf();
  }
}

final notesProvider = AsyncNotifierProvider<NotesNotifier, List<Note>>(
  NotesNotifier.new,
);
