import 'dart:convert';

import 'package:flutter/material.dart';
import 'repeat_rule.dart';

const List<Color> kNoteColors = [
  Color(0xFFFFFFFF),
  Color(0xFFF28B82),
  Color(0xFFFBBC04),
  Color(0xFFFFF475),
  Color(0xFFCCFF90),
  Color(0xFFCBF0F8),
  Color(0xFFAECBFA),
  Color(0xFFD7AEFB),
  Color(0xFFFDCFE8),
  Color(0xFFE6C9A8),
];

/// Muted dark-theme counterparts of [kNoteColors] (same order/index
/// meaning), matching Google Keep's own dark-mode note palette so cards
/// stay low-glare and readable against a dark background instead of
/// keeping the light palette's bright pastels.
const List<Color> kNoteColorsDark = [
  Color(0xFF202124),
  Color(0xFF5C2B29),
  Color(0xFF614A19),
  Color(0xFF635D19),
  Color(0xFF345920),
  Color(0xFF16504B),
  Color(0xFF2D555E),
  Color(0xFF42275E),
  Color(0xFF5B2245),
  Color(0xFF442F19),
];

/// Resolves a note's [colorIndex] to the palette entry matching the
/// current theme brightness (light vs dark), rather than always using the
/// light palette regardless of theme.
Color noteColorFor(BuildContext context, int colorIndex) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final palette = isDark ? kNoteColorsDark : kNoteColors;
  return palette[colorIndex.clamp(0, palette.length - 1)];
}

class Note {
  final String id;
  final String title;
  final String body;
  final int colorIndex;
  final DateTime? reminderAt;
  final DateTime created;
  final DateTime updated;

  /// Only ever meaningful on a [Note] fetched via [Note.fromPocketBase]
  /// during a sync merge (see SyncNotifier.mergeSync) - a tombstone rather
  /// than a real delete, so a device that was offline when another device
  /// deleted this note can tell "this was deleted after I last saw it"
  /// apart from "this note was never synced to begin with", which a hard
  /// delete is indistinguishable from. Local storage (DbService) never
  /// persists a deleted note at all, so this is always false for a [Note]
  /// built from [Note.fromMap].
  final bool deleted;

  /// Whether the user has explicitly acted on (Dismissed or Snoozed) the
  /// current reminder cycle - see NotificationService's Dismiss/Snooze
  /// handling. Synced like any other field (unlike the separate, genuinely
  /// per-device "handled" bookkeeping in NotificationService, which tracks
  /// each device's own independent alarm delivery) so that resolving a
  /// reminder on one device clears it everywhere: acting on this note
  /// elsewhere pushes reminderResolved up, the realtime subscription
  /// carries it to every other device, and SyncNotifier._handleRemoteEvent
  /// already cancels that device's own tray notification on any note
  /// update, resolved or not. Meaningless (and always false) once
  /// [reminderAt] is null or in the future - only an already-fired
  /// reminder can be "resolved" - and reset to false whenever a fresh
  /// [reminderAt] is set (see NoteEditorScreen._openReminderEditor and the
  /// Snooze paths), so a reused reminder starts its new cycle unresolved.
  final bool reminderResolved;

  /// The recurrence rule this reminder repeats under - see [RepeatRule].
  /// Null means "does not repeat" (also its own end state once a rule with
  /// a [RepeatEnd] condition runs its course - see
  /// NotificationService.advanceOverdueRepeatingReminders). Rolled forward
  /// automatically on Dismiss (not Snooze, which only delays this one
  /// occurrence without advancing the cycle - see reminder_popup.dart)
  /// rather than marking [reminderResolved] and stopping there: Dismissing
  /// a repeating reminder computes the next [reminderAt] from the current
  /// one via [nextRuleOccurrence] and clears [reminderResolved] for that
  /// fresh cycle, the same way setting a brand new reminderAt already
  /// does. Only ever meaningful together with a non-null [reminderAt].
  final RepeatRule? repeatRule;

  /// Which occurrence of [repeatRule] the current [reminderAt] represents,
  /// counting the very first (original) occurrence as 1 - meaningless
  /// (and always 1) when [repeatRule] is null. Only exists to let a
  /// [RepeatEndAfterCount] end condition know when it's been exhausted
  /// (see [nextRuleOccurrence]); a [RepeatEndNever] or [RepeatEndOnDate]
  /// rule never actually reads this.
  final int repeatOccurrenceNumber;

  const Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.colorIndex = 0,
    this.reminderAt,
    required this.created,
    required this.updated,
    this.deleted = false,
    this.reminderResolved = false,
    this.repeatRule,
    this.repeatOccurrenceNumber = 1,
  });

  bool get isEmpty => title.isEmpty && body.isEmpty && reminderAt == null;

  int get notificationId => id.hashCode.abs() % (1 << 30);

  Note copyWith({
    String? title,
    String? body,
    int? colorIndex,
    Object? reminderAt = _sentinel,
    DateTime? updated,
    bool? reminderResolved,
    Object? repeatRule = _sentinel,
    int? repeatOccurrenceNumber,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      colorIndex: colorIndex ?? this.colorIndex,
      reminderAt:
          identical(reminderAt, _sentinel) ? this.reminderAt : reminderAt as DateTime?,
      created: created,
      updated: updated ?? this.updated,
      reminderResolved: reminderResolved ?? this.reminderResolved,
      repeatRule: identical(repeatRule, _sentinel)
          ? this.repeatRule
          : repeatRule as RepeatRule?,
      repeatOccurrenceNumber:
          repeatOccurrenceNumber ?? this.repeatOccurrenceNumber,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'color_index': colorIndex,
        'reminder_at': reminderAt?.millisecondsSinceEpoch,
        'created': created.millisecondsSinceEpoch,
        'updated': updated.millisecondsSinceEpoch,
        'reminder_resolved': reminderResolved,
        'repeat_rule': repeatRule == null ? null : jsonEncode(repeatRule!.toJson()),
        'repeat_occurrence_number': repeatOccurrenceNumber,
      };

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'] as String,
        title: (map['title'] as String?) ?? '',
        body: (map['body'] as String?) ?? '',
        colorIndex: (map['color_index'] as int?) ?? 0,
        reminderAt: map['reminder_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['reminder_at'] as int)
            : null,
        created: DateTime.fromMillisecondsSinceEpoch(map['created'] as int),
        updated: DateTime.fromMillisecondsSinceEpoch(map['updated'] as int),
        reminderResolved: (map['reminder_resolved'] as bool?) ?? false,
        repeatRule: RepeatRule.fromJson(map['repeat_rule'] as String?),
        repeatOccurrenceNumber: (map['repeat_occurrence_number'] as int?) ?? 1,
      );

  Map<String, dynamic> toPocketBase() => {
        'title': title,
        'body': body,
        'color_index': colorIndex,
        'reminder_at': reminderAt?.toUtc().toIso8601String() ?? '',
        // A local note is by definition active, not a tombstone - pushing
        // one up (e.g. from mergeSync's local-is-newer branch) must always
        // clear a stale remote tombstone rather than leave it set.
        'deleted': false,
        'reminder_resolved': reminderResolved,
        'repeat_rule': repeatRule == null ? '' : jsonEncode(repeatRule!.toJson()),
        'repeat_occurrence_number': repeatOccurrenceNumber,
      };

  factory Note.fromPocketBase(Map<String, dynamic> r) {
    final now = DateTime.now();
    final reminderRaw = r['reminder_at'] as String?;
    return Note(
      id: r['id'] as String,
      title: (r['title'] as String?) ?? '',
      body: (r['body'] as String?) ?? '',
      colorIndex: (r['color_index'] as int?) ?? 0,
      reminderAt: (reminderRaw != null && reminderRaw.isNotEmpty)
          ? DateTime.parse(reminderRaw).toLocal()
          : null,
      created: r['created'] != null
          ? DateTime.parse(r['created'] as String).toLocal()
          : now,
      updated: r['updated'] != null
          ? DateTime.parse(r['updated'] as String).toLocal()
          : now,
      deleted: r['deleted'] == true,
      reminderResolved: r['reminder_resolved'] == true,
      repeatRule: RepeatRule.fromJson(r['repeat_rule'] as String?),
      repeatOccurrenceNumber: (r['repeat_occurrence_number'] as num?)?.toInt() ?? 1,
    );
  }
}

const Object _sentinel = Object();

/// The [Note] that should result from Dismissing its current reminder - if
/// it repeats (see [Note.repeatRule]) and hasn't run its own course yet,
/// rolls [Note.reminderAt] forward to its next occurrence via
/// [nextRuleOccurrence] and starts that fresh cycle unresolved, the same
/// as setting a brand new reminderAt already does (see
/// [Note.reminderResolved]'s own doc comment); otherwise (no rule, or the
/// rule's own [RepeatEnd] condition has now been reached) just marks this
/// cycle resolved and clears [Note.repeatRule], same as a non-repeating
/// reminder always has - a rule that's run its course behaves identically
/// to one that never repeated at all from this point on. Shared by
/// reminder_popup.dart's in-app Dismiss button and
/// notification_service.dart's background one (handleBackgroundReminderAction),
/// so dismissing a repeating reminder behaves identically from either path.
Note noteAfterDismiss(Note note) {
  final reminderAt = note.reminderAt;
  final rule = note.repeatRule;
  if (rule == null || reminderAt == null) {
    return note.copyWith(reminderResolved: true, updated: DateTime.now());
  }

  final next = nextRuleOccurrence(reminderAt, note.repeatOccurrenceNumber, rule);
  if (next == null) {
    return note.copyWith(
      reminderResolved: true,
      repeatRule: null,
      updated: DateTime.now(),
    );
  }
  return note.copyWith(
    reminderAt: next.reminderAt,
    reminderResolved: false,
    repeatOccurrenceNumber: next.occurrenceNumber,
    updated: DateTime.now(),
  );
}

/// Which of [notes] have a reminder that should still be surfaced to the
/// user, sorted oldest-first - an overdue reminder that's been sitting the
/// longest sorts above one that just fired, and both sort above anything
/// still upcoming. Shared by WidgetService.buildReminderListPayload (the
/// home-screen widget) and RemindersScreen (its in-app equivalent, reached
/// from the drawer), so both always agree on what counts as "active or
/// pending": an upcoming reminder (not yet fired) always qualifies; an
/// already-fired one only while still unresolved (see
/// [Note.reminderResolved]'s own doc comment) - a reminder exactly at
/// [now] (defaults to the real current time) counts as already fired, not
/// upcoming.
List<Note> notesWithActiveOrPendingReminders(
  List<Note> notes, {
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final withReminders = notes.where((n) => n.reminderAt != null).toList()
    ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));

  final result = <Note>[];
  for (final note in withReminders) {
    final isOverdue = !note.reminderAt!.isAfter(effectiveNow);
    if (isOverdue && note.reminderResolved) continue;
    result.add(note);
  }
  return result;
}
