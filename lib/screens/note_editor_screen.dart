import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../services/markdown_export_service.dart';
import '../services/notification_service.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/note_body_editor.dart';

const _uuid = Uuid();

/// Human-readable "in X, Y, and Z" breakdown of how long until [reminderAt]
/// (e.g. "in 2 days, 4 hours, and 35 minutes"), used alongside the absolute
/// time in the confirmation snackbar so it's clear at a glance whether e.g.
/// "3:00 PM" means later today or a week away. Zero-valued units are
/// omitted rather than shown as "0 hours" etc. Always positive in practice -
/// reminders can only be set in the future (see _pickReminder's
/// firstDate: now).
@visibleForTesting
String formatTimeUntilReminder(DateTime reminderAt, {DateTime? now}) {
  final diff = reminderAt.difference(now ?? DateTime.now());
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;

  final parts = <String>[
    if (days > 0) '$days day${days == 1 ? '' : 's'}',
    if (hours > 0) '$hours hour${hours == 1 ? '' : 's'}',
    if (minutes > 0) '$minutes minute${minutes == 1 ? '' : 's'}',
  ];

  switch (parts.length) {
    case 0:
      return 'in less than a minute';
    case 1:
      return 'in ${parts[0]}';
    case 2:
      return 'in ${parts[0]} and ${parts[1]}';
    default:
      return 'in ${parts[0]}, ${parts[1]}, and ${parts[2]}';
  }
}

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note? existing;

  // Pre-fills a brand-new note (only meaningful together with existing:
  // null) - used when jotes is opened as a share target (see main.dart's
  // _openNoteFromShare/ShareIntentService): initialBody is the shared
  // text, initialTitle the shared subject, if the sending app provided
  // one.
  final String? initialTitle;
  final String? initialBody;

  const NoteEditorScreen({
    super.key,
    this.existing,
    this.initialTitle,
    this.initialBody,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _bodyEditorKey = GlobalKey<NoteBodyEditorState>();
  final _titleFocusNode = FocusNode();
  late TextEditingController _titleCtrl;
  late String _currentBody;
  late int _colorIndex;
  late String _noteId;
  DateTime? _reminderAt;
  bool _reminderResolved = false;
  RepeatInterval _repeatInterval = RepeatInterval.none;
  bool _dirty = false;
  bool _saving = false;

  // The most recent Note.updated this screen itself is responsible for -
  // either just saved locally or just applied from an incoming remote
  // update (see _maybeApplyRemoteUpdate). Distinguishes "this is our own
  // write echoing back through the realtime subscription" (updated is the
  // same instant, not after) from "a genuinely newer edit arrived from
  // another device" (updated is after) - without this, this screen would
  // reapply its own just-saved content to itself on every autosave.
  DateTime? _lastKnownUpdated;

  Timer? _autosaveTimer;
  static const _autosaveDebounce = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    _titleCtrl = TextEditingController(
      text: n?.title ?? widget.initialTitle ?? '',
    );
    _currentBody = n?.body ?? widget.initialBody ?? '';
    _colorIndex = n?.colorIndex ?? 0;
    _reminderAt = n?.reminderAt;
    _reminderResolved = n?.reminderResolved ?? false;
    _repeatInterval = n?.repeatInterval ?? RepeatInterval.none;
    _lastKnownUpdated = n?.updated;
    // Generated once per editing session so repeated saves (e.g. multiple
    // back-button presses before the first save/pop completes) update the
    // same note instead of each minting a fresh id and creating a duplicate.
    _noteId = n?.id ?? _uuid.v4();

    if (n == null &&
        widget.initialBody != null &&
        widget.initialBody!.isNotEmpty) {
      // A shared-in note counts as "content to save" the moment it lands,
      // unlike a genuinely blank new note - and, same reasoning as
      // _pickReminder/_clearReminder's own immediate saves, this can't
      // wait for PopScope's save-on-pop: leaving via the home button/app
      // switcher/OS process kill never triggers it, which would otherwise
      // silently discard a share the user never even got a chance to
      // reject.
      _dirty = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _save());
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _titleCtrl.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  Note _buildNote() {
    final now = DateTime.now();
    final existing = widget.existing;
    return Note(
      id: _noteId,
      title: _titleCtrl.text.trim(),
      body: _currentBody.trim(),
      colorIndex: _colorIndex,
      reminderAt: _reminderAt,
      created: existing?.created ?? now,
      updated: now,
      reminderResolved: _reminderResolved,
      repeatInterval: _repeatInterval,
    );
  }

  Future<String?> _save() async {
    final note = _buildNote();
    if (note.isEmpty && widget.existing == null) return null;
    final error = await ref.read(notesProvider.notifier).addOrUpdate(note);
    if (mounted) {
      setState(() {
        _dirty = false;
        _lastKnownUpdated = note.updated;
      });
    }
    return error;
  }

  /// Marks unsaved changes and (re)starts the autosave countdown - called
  /// on every keystroke/edit rather than saving immediately on each one, so
  /// typing doesn't hammer the notifier/network with a write per
  /// character. Previously this note only ever saved when the screen was
  /// popped, so a note left open and edited for a while never reached the
  /// server at all until closed - meaning a second device with the same
  /// note open had nothing to "follow along" with. This is what makes
  /// periodic saves happen while the note stays open.
  void _markDirty() {
    _dirty = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDebounce, () {
      if (!mounted || !_dirty || _saving) return;
      _save();
    });
  }

  /// Applies an update to this same note that arrived from another device
  /// (via the realtime sync subscription -> notesProvider, watched below in
  /// build()) while this screen has it open. Only takes effect if this
  /// device has nothing of its own at risk of being overwritten: no
  /// unsaved local edits, and neither text field is actively focused (even
  /// unchanged-but-focused is excluded, since resetting a focused
  /// TextField's controller out from under a live cursor is jarring
  /// regardless of whether anything was actually typed yet). This is what
  /// lets a device just viewing a note "follow along" as another device
  /// edits it, without a real operational-transform/merge system - still
  /// simple last-write-wins, consistent with SyncNotifier.mergeSync.
  void _maybeApplyRemoteUpdate(Note remote) {
    final lastKnown = _lastKnownUpdated;
    if (lastKnown != null && !remote.updated.isAfter(lastKnown)) {
      return; // our own write echoing back, or already-applied/stale
    }
    if (_dirty) return;
    if (_titleFocusNode.hasFocus) return;
    if (_bodyEditorKey.currentState?.isEditingBody == true) return;

    setState(() {
      _titleCtrl.text = remote.title;
      _currentBody = remote.body;
      _colorIndex = remote.colorIndex;
      _reminderAt = remote.reminderAt;
      _reminderResolved = remote.reminderResolved;
      _repeatInterval = remote.repeatInterval;
      _lastKnownUpdated = remote.updated;
    });
    _bodyEditorKey.currentState?.applyExternalBody(remote.body);
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    // An expired reminder can't be used as showDatePicker's initialDate -
    // it violates the picker's own firstDate: now constraint (initialDate
    // must be on or after firstDate), which would crash rather than let
    // you reset it. Fall back to the same "an hour from now" default used
    // when there's no reminder at all yet.
    final initial = (_reminderAt != null && _reminderAt!.isAfter(now))
        ? _reminderAt!
        : now.add(const Duration(hours: 1));
    final ctx = context;
    final date = await showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      // ignore: use_build_context_synchronously
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final reminderAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _reminderAt = reminderAt;
      // A fresh reminder cycle - see Note.reminderResolved's own doc
      // comment for why whoever sets a new reminderAt is responsible for
      // also clearing this, rather than something downstream inferring it.
      _reminderResolved = false;
      _dirty = true;
    });

    // Persist (and thus actually schedule the notification) right now,
    // rather than deferring to the pop-triggered autosave: leaving the
    // screen via the home button/app switcher/OS process kill never
    // triggers PopScope, so a reminder set here would otherwise silently
    // never be saved or scheduled at all, despite the confirmation message
    // below implying it was.
    final scheduleError = await _save();
    if (!mounted) return;

    await _showReminderFeedback(reminderAt, scheduleError);
  }

  /// Shows exactly one message after a reminder is set: the real error
  /// from the scheduling attempt itself if there was one (this is the
  /// actual outcome, not a guess - previously a permission check could
  /// claim success while the real zonedSchedule() call silently failed
  /// for an unrelated reason), else whichever permission problem would
  /// stop it from firing even though scheduling itself didn't throw, else
  /// a plain confirmation of the time it was set for.
  Future<void> _showReminderFeedback(
    DateTime reminderAt,
    String? scheduleError,
  ) async {
    if (scheduleError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reminder could not be scheduled: $scheduleError'),
          duration: const Duration(seconds: 10),
        ),
      );
      return;
    }

    // Notifications-disabled is checked first and takes priority: it's the
    // more fundamental blocker (nothing can show at all, regardless of
    // exact-alarm scheduling), and Android will silently drop a scheduled
    // notification with no error if this is off, so it needs its own
    // explicit check rather than assuming exact-alarm status covers it.
    final notifsEnabled = await NotificationService.instance
        .notificationsEnabled();
    if (!mounted) return;
    if (!notifsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Reminders won't fire - notifications are disabled for jotes.",
          ),
          action: SnackBarAction(
            label: 'Fix',
            onPressed: () =>
                NotificationService.instance.requestNotificationsAccess(),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    final exactAlarmsPermitted = await NotificationService.instance
        .exactAlarmsPermitted();
    if (!mounted) return;
    if (!exactAlarmsPermitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Reminders may not fire - this device hasn't granted exact "
            'alarm access.',
          ),
          action: SnackBarAction(
            label: 'Fix',
            onPressed: () =>
                NotificationService.instance.requestExactAlarmsAccess(),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    // A modal dialog requiring an explicit OK, not a SnackBar - the time
    // shown here is easy to misread in the split second before a toast
    // auto-dismisses, and unlike the two warning cases above (which have
    // their own "Fix" action forcing a deliberate read), a plain success
    // message was too easy to miss entirely.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reminder set'),
        content: Text(
          '${DateFormat('MMM d, h:mm a').format(reminderAt)} '
          '(${formatTimeUntilReminder(reminderAt)})',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Clears the reminder and saves immediately - same reasoning as
  /// _pickReminder's own immediate save: leaving the screen via the home
  /// button/app switcher/OS process kill never triggers PopScope, so a
  /// removed reminder would otherwise silently keep firing (its tray
  /// notification never actually cancelled - see NotesNotifier.addOrUpdate,
  /// which cancels the old alarm on every save) until the note happened to
  /// be saved some other way.
  Future<void> _clearReminder() async {
    setState(() {
      _reminderAt = null;
      _reminderResolved = false;
      // Meaningless with no reminderAt to advance - see RepeatInterval's own
      // doc comment.
      _repeatInterval = RepeatInterval.none;
      _dirty = true;
    });
    await _save();
  }

  /// Tapping the reminder chip used to remove it outright with no way to
  /// reconsider or edit it instead - this presents both choices explicitly,
  /// wording the first option around whichever is actually true (a past
  /// reminder can only be reset to a new time, not "edited" as if it were
  /// still pending). This is this note's own reminder settings, distinct
  /// from Snooze/Dismiss on an actually-fired reminder's notification
  /// itself (see NotificationService's notification action handling) -
  /// deliberately not reusing that wording here to avoid conflating the two.
  Future<void> _showReminderOptions() async {
    final reminderAt = _reminderAt;
    if (reminderAt == null) return;
    final isExpired = !reminderAt.isAfter(DateTime.now());

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(isExpired ? 'Reset reminder' : 'Edit reminder'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              key: const Key('reminder_options_repeat'),
              leading: const Icon(Icons.repeat),
              title: const Text('Repeat'),
              subtitle: Text(_repeatInterval.label),
              onTap: () => Navigator.pop(sheetContext, 'repeat'),
            ),
            ListTile(
              leading: const Icon(Icons.alarm_off_outlined),
              title: const Text('Remove reminder'),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    switch (action) {
      case 'edit':
        await _pickReminder();
      case 'remove':
        await _clearReminder();
      case 'repeat':
        await _pickRepeatInterval();
    }
  }

  /// Bottom sheet of [RepeatInterval] presets, reached via the reminder
  /// chip's "Repeat" option above - only meaningful together with an active
  /// [_reminderAt] (see RepeatInterval's own doc comment), so this is only
  /// ever reachable from there. Saves immediately, same reasoning as
  /// _pickReminder/_clearReminder's own immediate saves. Plain checkmarked
  /// ListTiles rather than RadioListTile, whose groupValue/onChanged are
  /// deprecated as of Flutter 3.32 in favor of a RadioGroup ancestor this
  /// codebase has no other use for yet.
  Future<void> _pickRepeatInterval() async {
    final selected = await showModalBottomSheet<RepeatInterval>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final interval in RepeatInterval.values)
              ListTile(
                key: Key('repeat_option_${interval.name}'),
                title: Text(interval.label),
                trailing: interval == _repeatInterval
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(sheetContext, interval),
              ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;
    setState(() {
      _repeatInterval = selected;
      _dirty = true;
    });
    await _save();
  }

  Future<void> _pickColor() async {
    final index = await showColorPickerSheet(context, selected: _colorIndex);
    if (index == null || !mounted) return;
    setState(() => _colorIndex = index);
    _markDirty();
  }

  /// Exports the note's current in-progress state (not just its last-saved
  /// version), so exporting works even before the note has ever been
  /// saved.
  Future<void> _exportToMarkdown() async {
    final note = _buildNote();
    await FilePicker.platform.saveFile(
      fileName: '${MarkdownExportService.instance.suggestedFilename(note)}.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
      bytes: utf8.encode(MarkdownExportService.instance.toMarkdown(note)),
    );
  }

  /// Shares the note's current in-progress state via the OS share sheet,
  /// same content/format as [_exportToMarkdown] (reusing
  /// MarkdownExportService.toMarkdown - one place decides how a note
  /// renders as text, whether it leaves the app as a .md file or a share
  /// intent) rather than opening a file picker.
  Future<void> _shareNote() async {
    final note = _buildNote();
    final text = MarkdownExportService.instance.toMarkdown(note);
    if (text.trim().isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(text: text, subject: note.title.isEmpty ? null : note.title),
    );
  }

  /// Duplicate/Delete both need a real persisted note to act on -
  /// widget.existing for a note this screen was opened on, or (now that
  /// both are offered right away, not just once widget.existing != null)
  /// an immediate save for a brand-new note that hasn't hit the ~2-second
  /// autosave debounce yet (see _markDirty) or been saved any other way.
  /// Returns null, meaning "nothing to act on", only for a genuinely empty
  /// new note - same guard _save() itself already applies, so this never
  /// persists a blank note just because the menu was opened.
  Future<Note?> _ensurePersisted() async {
    final existing = widget.existing;
    if (existing != null) return existing;
    await _save();
    final note = _buildNote();
    return note.isEmpty ? null : note;
  }

  /// Duplicates this note into a brand-new one with a fresh id, saved
  /// immediately once a title is confirmed - "Make a copy", matching Keep.
  /// Asks for the new note's title first (pre-filled with this note's own
  /// title) rather than silently reusing it verbatim, since two notes with
  /// an identical title sitting side by side in the grid would otherwise be
  /// hard to tell apart at a glance. Stays on this (the original) note
  /// rather than navigating to the duplicate, since jumping to a different
  /// note out from under whatever the user was just looking at would be
  /// more disorienting than useful. The reminder is deliberately not
  /// carried over - two notes silently sharing the same alert time would be
  /// confusing, and the user almost certainly wants to set a fresh one (or
  /// none) for the duplicate explicitly rather than have it inherited
  /// silently.
  Future<void> _duplicateNote() async {
    final source = await _ensurePersisted();
    if (source == null || !mounted) return;

    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _DuplicateTitleDialog(initialTitle: source.title),
    );
    if (newTitle == null || !mounted) return;

    final now = DateTime.now();
    final duplicate = Note(
      id: _uuid.v4(),
      title: newTitle.trim(),
      body: source.body,
      colorIndex: source.colorIndex,
      created: now,
      updated: now,
    );
    await ref.read(notesProvider.notifier).addOrUpdate(duplicate);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Note duplicated')));
  }

  /// Deletes this note after an explicit confirmation - unlike the bulk
  /// delete from the note grid's selection mode (see
  /// NotesScreen._deleteSelected, which doesn't confirm), reaching this is
  /// only a single tap away during normal browsing here, with no separate
  /// "enter selection mode" gesture already signaling deliberate intent -
  /// see DbService.delete, this is a real local delete, not a recoverable
  /// soft one.
  Future<void> _deleteNote() async {
    final source = await _ensurePersisted();
    if (!mounted) return;
    if (source == null) {
      // Never persisted and still empty - nothing to delete, so this is
      // just closing the screen, same as backing out of a blank new note
      // normally does (see PopScope below).
      Navigator.of(context).pop();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _autosaveTimer?.cancel();
    // Blocks PopScope's own save-on-pop from resurrecting this note if it
    // gets invoked again as part of the pop triggered below - same
    // reasoning as the real back-button path further down, which sets
    // this before its own nav.pop() for the same reason.
    _saving = true;
    await ref.read(notesProvider.notifier).delete(source);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = noteColorFor(context, _colorIndex);
    final isDark =
        ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = textColor.withAlpha(100);
    // A fixed link-blue (lighter on a dark note, darker on a light one, same
    // idea as textColor/hintColor above) rather than deriving it from the
    // note's own background color - links are conventionally blue
    // regardless of surrounding color, and this app's note backgrounds span
    // ten different hues (see kNoteColors/kNoteColorsDark in note.dart) that
    // a single derived tint couldn't reliably stay legible against.
    final linkColor = isDark ? Colors.lightBlueAccent : Colors.blue;

    // Live "follow along on another device" - see _maybeApplyRemoteUpdate.
    // Watched here (not just from NotesScreen) so an update to this note
    // specifically is picked up while it's open, not only once the list
    // screen underneath happens to rebuild.
    ref.listen<AsyncValue<List<Note>>>(notesProvider, (previous, next) {
      final notes = next.value;
      if (notes == null) return;
      for (final note in notes) {
        if (note.id == _noteId) {
          _maybeApplyRemoteUpdate(note);
          break;
        }
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        // A pop attempt while the body editor is mid-edit (its raw-text
        // TextField is showing, not the normal view) should back out of
        // that first, not save-and-leave the whole note screen - without
        // this there'd be no way to "cancel out of" edit mode via the
        // back button short of tapping elsewhere first.
        if (_bodyEditorKey.currentState?.isEditingBody == true) {
          _bodyEditorKey.currentState?.exitEditMode();
          return;
        }
        _autosaveTimer?.cancel();
        _saving = true;
        final nav = Navigator.of(context);
        try {
          if (_dirty || widget.existing != null) await _save();
        } finally {
          _saving = false;
        }
        if (mounted) nav.pop();
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          foregroundColor: textColor,
          actions: [
            _ReminderPillButton(
              reminderAt: _reminderAt,
              iconColor: textColor,
              onPressed: _reminderAt == null
                  ? _pickReminder
                  : _showReminderOptions,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('title_field'),
                controller: _titleCtrl,
                focusNode: _titleFocusNode,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(color: hintColor),
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => _markDirty(),
                onSubmitted: (_) => _bodyEditorKey.currentState?.focusBody(),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NoteBodyEditor(
                  key: _bodyEditorKey,
                  initialBody:
                      widget.existing?.body ?? widget.initialBody ?? '',
                  textColor: textColor,
                  hintColor: hintColor,
                  linkColor: linkColor,
                  autofocusFirst: widget.existing == null,
                  onChanged: (body) {
                    _currentBody = body;
                    _markDirty();
                    // Every structural checklist change (the only kind
                    // that pushes an undo step - see NoteBodyEditorState)
                    // also fires this, so it doubles as the trigger to
                    // re-check canUndo for the toolbar button below.
                    setState(() {});
                  },
                  // Keeps the move-up/move-down buttons' enabled state (see
                  // isEditingBody below) in sync with every view/edit mode
                  // transition, not just the next unrelated rebuild -
                  // separate from onChanged above since switching modes
                  // alone shouldn't mark the note dirty or restart autosave.
                  onModeChanged: () => setState(() {}),
                ),
              ),
            ),
            SafeArea(
              top: false,
              // On a device with an on-screen nav bar, this row otherwise
              // sits flush against it with no margin, the same class of
              // problem seen in the drawer's pinned bottom section.
              minimum: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  border: const Border(top: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.check_box_outlined, color: textColor),
                      onPressed: () =>
                          _bodyEditorKey.currentState?.toggleChecklistLine(),
                      tooltip: 'Toggle checklist item',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.format_list_bulleted_outlined,
                        color: textColor,
                      ),
                      onPressed: () =>
                          _bodyEditorKey.currentState?.toggleBulletLine(),
                      tooltip: 'Toggle list item',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.arrow_upward_outlined,
                        color: textColor,
                      ),
                      onPressed:
                          _bodyEditorKey.currentState?.isEditingBody == true
                          ? () => _bodyEditorKey.currentState?.moveLineUp()
                          : null,
                      tooltip: 'Move line up',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.arrow_downward_outlined,
                        color: textColor,
                      ),
                      onPressed:
                          _bodyEditorKey.currentState?.isEditingBody == true
                          ? () => _bodyEditorKey.currentState?.moveLineDown()
                          : null,
                      tooltip: 'Move line down',
                    ),
                    IconButton(
                      icon: Icon(Icons.undo, color: textColor),
                      onPressed: _bodyEditorKey.currentState?.canUndo == true
                          ? () => _bodyEditorKey.currentState?.undo()
                          : null,
                      tooltip: 'Undo last checklist change',
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      key: const Key('note_more_menu'),
                      icon: Icon(Icons.more_vert, color: textColor),
                      tooltip: 'More options',
                      onSelected: (value) {
                        switch (value) {
                          case 'color':
                            _pickColor();
                          case 'export':
                            _exportToMarkdown();
                          case 'share':
                            _shareNote();
                          case 'duplicate':
                            _duplicateNote();
                          case 'delete':
                            _deleteNote();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'color',
                          child: ListTile(
                            leading: Icon(Icons.palette_outlined),
                            title: Text('Change color'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export',
                          child: ListTile(
                            leading: Icon(Icons.ios_share_outlined),
                            title: Text('Export as Markdown'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: ListTile(
                            leading: Icon(Icons.share_outlined),
                            title: Text('Share'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        // Offered right away, even for a brand-new note
                        // that hasn't autosaved yet - _duplicateNote/
                        // _deleteNote persist it immediately via
                        // _ensurePersisted rather than requiring
                        // widget.existing != null first.
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: ListTile(
                            leading: Icon(Icons.copy_outlined),
                            title: Text('Duplicate'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Delete'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Always-present rounded-square icon button in the editor's top app bar,
/// matching Keep's pin/reminder/archive pill convention - jotes only has
/// a reminder toggle, so this is the sole pill rather than one of several.
class _ReminderPillButton extends StatelessWidget {
  final DateTime? reminderAt;
  final Color iconColor;
  final VoidCallback onPressed;

  const _ReminderPillButton({
    required this.reminderAt,
    required this.iconColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final reminderAt = this.reminderAt;
    final IconData icon;
    final String tooltip;
    if (reminderAt == null) {
      icon = Icons.add_alert_outlined;
      tooltip = 'Set reminder';
    } else if (reminderAt.isAfter(DateTime.now())) {
      icon = Icons.alarm;
      tooltip = 'Reminder options';
    } else {
      icon = Icons.alarm_off;
      tooltip = 'Reminder options';
    }

    return Material(
      color: iconColor.withAlpha(25),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Title prompt shown by _duplicateNote. A dedicated StatefulWidget rather
/// than a bare TextEditingController built inline in _duplicateNote - the
/// latter was tried first and disposed the controller itself right after
/// showDialog returned, which crashed ("used after being disposed")
/// because the dialog route's closing animation was still rebuilding this
/// field for a few more frames after that. Owning the controller here ties
/// its lifecycle to this widget's own dispose(), which the framework only
/// calls once the route is actually gone.
class _DuplicateTitleDialog extends StatefulWidget {
  final String initialTitle;

  const _DuplicateTitleDialog({required this.initialTitle});

  @override
  State<_DuplicateTitleDialog> createState() => _DuplicateTitleDialogState();
}

class _DuplicateTitleDialogState extends State<_DuplicateTitleDialog> {
  late final _titleCtrl = TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Duplicate note'),
      content: TextField(
        key: const Key('duplicate_note_title_field'),
        controller: _titleCtrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Title'),
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _titleCtrl.text),
          child: const Text('Duplicate'),
        ),
      ],
    );
  }
}
