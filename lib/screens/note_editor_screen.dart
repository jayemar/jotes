import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../services/notification_service.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/note_body_editor.dart';

const _uuid = Uuid();

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note? existing;

  const NoteEditorScreen({super.key, this.existing});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _bodyEditorKey = GlobalKey<NoteBodyEditorState>();
  late TextEditingController _titleCtrl;
  late String _currentBody;
  late int _colorIndex;
  late String _noteId;
  DateTime? _reminderAt;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    _titleCtrl = TextEditingController(text: n?.title ?? '');
    _currentBody = n?.body ?? '';
    _colorIndex = n?.colorIndex ?? 0;
    _reminderAt = n?.reminderAt;
    // Generated once per editing session so repeated saves (e.g. multiple
    // back-button presses before the first save/pop completes) update the
    // same note instead of each minting a fresh id and creating a duplicate.
    _noteId = n?.id ?? _uuid.v4();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
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
    );
  }

  Future<String?> _save() async {
    final note = _buildNote();
    if (note.isEmpty && widget.existing == null) return null;
    return ref.read(notesProvider.notifier).addOrUpdate(note);
  }

  Future<void> _pickReminder() async {
    final initial = _reminderAt ?? DateTime.now().add(const Duration(hours: 1));
    final ctx = context;
    final date = await showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    // ignore: use_build_context_synchronously
    final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;

    final reminderAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      _reminderAt = reminderAt;
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
    final notifsEnabled = await NotificationService.instance.notificationsEnabled();
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

    final exactAlarmsPermitted =
        await NotificationService.instance.exactAlarmsPermitted();
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reminder set for ${DateFormat('MMM d, h:mm a').format(reminderAt)}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearReminder() {
    setState(() {
      _reminderAt = null;
      _dirty = true;
    });
  }

  Future<void> _pickColor() async {
    final index = await showColorPickerSheet(context, selected: _colorIndex);
    if (index == null || !mounted) return;
    setState(() {
      _colorIndex = index;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = noteColorFor(context, _colorIndex);
    final isDark =
        ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = textColor.withAlpha(100);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
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
            if (_reminderAt != null)
              TextButton.icon(
                icon: Icon(Icons.alarm, color: textColor, size: 16),
                label: Text(
                  DateFormat('MMM d, h:mm a').format(_reminderAt!),
                  style: TextStyle(color: textColor, fontSize: 12),
                ),
                onPressed: _clearReminder,
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('title_field'),
                controller: _titleCtrl,
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
                onChanged: (_) => _dirty = true,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NoteBodyEditor(
                  key: _bodyEditorKey,
                  initialBody: widget.existing?.body ?? '',
                  textColor: textColor,
                  hintColor: hintColor,
                  autofocusFirst: widget.existing == null,
                  onChanged: (body) {
                    _currentBody = body;
                    _dirty = true;
                  },
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: bgColor,
                border:
                    const Border(top: BorderSide(color: Colors.black12)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.palette_outlined, color: textColor),
                    onPressed: _pickColor,
                    tooltip: 'Change color',
                  ),
                  IconButton(
                    icon: Icon(Icons.check_box_outlined, color: textColor),
                    onPressed: () =>
                        _bodyEditorKey.currentState?.addChecklistItem(),
                    tooltip: 'Add checklist item',
                  ),
                  IconButton(
                    icon: Icon(Icons.alarm_add_outlined, color: textColor),
                    onPressed: _pickReminder,
                    tooltip: 'Set reminder',
                  ),
                  if (_reminderAt != null)
                    IconButton(
                      icon: Icon(Icons.alarm_off_outlined, color: textColor),
                      onPressed: _clearReminder,
                      tooltip: 'Remove reminder',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
