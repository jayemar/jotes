import 'package:flutter/material.dart';

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

  const Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.colorIndex = 0,
    this.reminderAt,
    required this.created,
    required this.updated,
    this.deleted = false,
  });

  bool get isEmpty => title.isEmpty && body.isEmpty && reminderAt == null;

  int get notificationId => id.hashCode.abs() % (1 << 30);

  Note copyWith({
    String? title,
    String? body,
    int? colorIndex,
    Object? reminderAt = _sentinel,
    DateTime? updated,
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
    );
  }
}

const Object _sentinel = Object();
