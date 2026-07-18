import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../services/db_service.dart';
import '../services/notification_service.dart';
import '../services/pb_service.dart';

class NotesNotifier extends AsyncNotifier<List<Note>> {
  @override
  Future<List<Note>> build() async {
    return DbService.instance.getAll();
  }

  /// Saves [note] and (re)schedules its reminder notification if it has
  /// one. Returns the scheduling error's description if scheduling failed,
  /// or null if it succeeded (or there was no reminder to schedule) - the
  /// note itself is always saved either way, but callers that show the
  /// user a confirmation (see note_editor_screen.dart) need to know
  /// whether the schedule call actually worked rather than just assuming
  /// success from permission checks alone.
  Future<String?> addOrUpdate(Note note) async {
    await DbService.instance.upsert(note);

    // Cancel and schedule are attempted independently: if cancelling a
    // stale/nonexistent alarm ever throws, that must not silently prevent
    // the schedule attempt below from running at all.
    try {
      await NotificationService.instance.cancel(note.notificationId);
    } catch (_) {
      // Not meaningful on its own - proceed to (re)scheduling regardless.
    }

    String? scheduleError;
    if (note.reminderAt != null && note.reminderAt!.isAfter(DateTime.now())) {
      try {
        await NotificationService.instance.schedule(note);
      } catch (e) {
        // The note above is already saved; a failed reminder schedule must
        // not block that or the caller's post-save navigation (see
        // note_editor_screen's save-then-pop), so this is reported back
        // rather than rethrown.
        scheduleError = e.toString();
      }
    }

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

    // See addOrUpdate: cancelling a reminder can throw and must never block
    // the delete that already succeeded above.
    try {
      await NotificationService.instance.cancel(note.notificationId);
    } catch (_) {
      // Note is already deleted; a failed notification cancel is not fatal.
    }

    PbService.instance.delete(note.id).ignore();
    ref.invalidateSelf();
  }
}

final notesProvider = AsyncNotifierProvider<NotesNotifier, List<Note>>(
  NotesNotifier.new,
);
