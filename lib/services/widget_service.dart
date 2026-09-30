import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:home_widget/home_widget.dart';
import '../models/note.dart';
import '../widgets/note_body_editor.dart'
    show
        BodyBlock,
        BulletBodyBlock,
        ChecklistBodyBlock,
        NumberedBodyBlock,
        TextBodyBlock,
        parseBody;
import '../widgets/note_inline_format.dart';
import '../widgets/note_links.dart';

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

  /// The reminders list payload for the home-screen widget - `isOverdue`
  /// mirrors NoteCard's own _ReminderChip convention (note_card.dart) so
  /// the widget can match its red/green styling. Which notes qualify (and
  /// their sort order) comes from [notesWithActiveOrPendingReminders] -
  /// see its own doc comment - shared with RemindersScreen's in-app
  /// equivalent so both always agree.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> buildReminderListPayload(
    List<Note> notes, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final qualifying = notesWithActiveOrPendingReminders(
      notes,
      now: effectiveNow,
    );
    return [
      for (final note in qualifying)
        {
          'id': note.id,
          'title': note.title,
          'reminderAtMillis': note.reminderAt!.millisecondsSinceEpoch,
          'isOverdue': !note.reminderAt!.isAfter(effectiveNow),
        },
    ];
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
      ..._styledText(block.text),
      'indent': block.indent,
    },
    // SingleNoteWidget.kt only knows "checklist"/"text" (see parseBlocks
    // there) - a plain bullet/numbered item isn't worth a third native
    // block type just for the home-screen widget, so its marker is folded
    // back into the displayed text instead of either crashing on an
    // unrecognized type or silently dropping the line. A bullet uses the
    // same "•" glyph note_card.dart/note_body_view.dart's own in-app
    // preview shows, not the raw "- " markdown syntax the note's body
    // carries - showing the literal hyphen was the actual bug this
    // replaced (a bullet is not itself something WidgetService otherwise
    // "supports" rendering, unlike checklist items, if it's left looking
    // like unrendered markdown). `indent` still carries through as its own
    // field (not folded into the text like the marker is) so Kotlin can
    // apply the same start-padding treatment the checklist row above
    // already gets. This does mean a bulleted/numbered line that's
    // otherwise nothing but a bare link loses the in-app "whole line is a
    // link" styling in the widget specifically, since the marker prefix
    // means _styledText's whole-link check no longer sees the *entire*
    // text as just a link.
    BulletBodyBlock() => {
      'type': 'text',
      ..._styledText('• ${block.text}'),
      'indent': block.indent,
    },
    NumberedBodyBlock() => {
      'type': 'text',
      ..._styledText('${block.number}. ${block.text}'),
      'indent': block.indent,
    },
    TextBodyBlock() => {'type': 'text', ..._styledText(block.text)},
  };

  /// Markdown links and inline formatting (`**bold**`/`*italic*`/
  /// `~~strike~~`/`` `code` ``) can't render as true mixed-style spans in
  /// the Android widget - Jetpack Glance's Text only takes one plain
  /// String + one TextStyle per call (no AnnotatedString/TextSpan
  /// equivalent), and RemoteViews has no span-level click target at all,
  /// only whole-view clicks (see SingleNoteWidget.kt). So [text] is always
  /// reduced to a fully plain string first - link syntax down to each
  /// link's own display label (matching what buildLinkSpans shows
  /// in-app), then any remaining formatting markers stripped too - and
  /// 'style' says the one way (if any) Kotlin can still style the whole
  /// block: 'link' when [text] was nothing but a single link (the
  /// existing, most-valuable case - kept taking priority over inline
  /// formatting, since a linked *and* bold run in the same block is rare
  /// enough not to chase), 'bold'/'italic'/'strikethrough'/'code' when
  /// what's left after link-stripping is nothing but a single one of
  /// those formatted runs (see [InlineFormat]), or 'plain' otherwise (a
  /// mix of formatting/plain text, or none at all) - still fully
  /// markdown-punctuation-free even though no particular style applies to
  /// the whole line.
  static Map<String, dynamic> _styledText(String text) {
    final linkSegments = parseLinks(text);
    if (linkSegments.length == 1 && linkSegments.single.isLink) {
      return {'text': linkSegments.single.text, 'style': 'link'};
    }

    final linkStripped = linkSegments.map((s) => s.text).join();
    final formatSegments = parseInlineFormatting(linkStripped);
    final nonEmpty = formatSegments.where((s) => s.text.isNotEmpty).toList();
    if (nonEmpty.length == 1 && nonEmpty.single.formats.isNotEmpty) {
      return {
        'text': nonEmpty.single.text,
        'style': nonEmpty.single.formats.single.name,
      };
    }

    return {'text': formatSegments.map((s) => s.text).join(), 'style': 'plain'};
  }
}
