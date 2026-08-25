import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/repeat_rule.dart';
import 'custom_recurrence_screen.dart';

/// What [ReminderEditScreen] hands back via Navigator.pop - null (no
/// result at all) means the user backed out without changing anything.
sealed class ReminderEditResult {
  const ReminderEditResult();
}

class ReminderSet extends ReminderEditResult {
  final DateTime reminderAt;
  final RepeatRule? repeatRule;

  const ReminderSet(this.reminderAt, this.repeatRule);
}

class ReminderRemoved extends ReminderEditResult {
  const ReminderRemoved();
}

/// Label for one of the 6 quick presets in the Repeat picker sheet (the
/// original 5 fixed daily/weekly/monthly/yearly presets plus "Every
/// weekday") - shared with the Repeat row's own subtitle below, so both
/// agree on the same wording for the same rule.
String _quickPresetLabel(RepeatFrequency frequency) {
  return switch (frequency) {
    RepeatFrequency.daily => 'Daily',
    RepeatFrequency.weekly => 'Weekly',
    RepeatFrequency.monthly => 'Monthly',
    RepeatFrequency.yearly => 'Yearly',
  };
}

/// The Repeat row's own subtitle for the current [rule] - a quick preset's
/// plain name, "Every weekday", or (for anything reached via Custom
/// recurrence) [RepeatRule.summary]'s fuller description.
String repeatRuleLabel(RepeatRule? rule) {
  if (rule == null) return 'Does not repeat';
  if (rule.isEveryWeekday) return 'Every weekday';
  if (rule.isSimplePreset) return _quickPresetLabel(rule.frequency);
  return rule.summary;
}

/// One combined screen for setting or editing a note's reminder - date,
/// time, and repeat all shown together as tappable rows, with an explicit
/// checkmark to save - deliberately modeled on Google Calendar's own "New
/// event"/"Edit event" screen (on request), rather than the chain of
/// separate date/time/repeat popups this replaced, each of which closed
/// and immediately auto-advanced into the next with no single point to
/// review everything together before committing. The Repeat row's own
/// picker (see _pickRepeat below) is likewise modeled on Calendar's own
/// repeat picker: the same 5 fixed presets this app always had, plus
/// "Every weekday" and a "Custom recurrence" option (see
/// custom_recurrence_screen.dart) for interval counts, specific weekdays,
/// and an end condition.
///
/// Reached from note_editor_screen.dart's reminder pill regardless of
/// whether a reminder already exists - unlike the old flow, there's no
/// separate "Set reminder" vs "reminder options" entry point, since this
/// screen already covers editing and removing an existing reminder too.
class ReminderEditScreen extends StatefulWidget {
  final DateTime? initialReminderAt;
  final RepeatRule? initialRepeatRule;

  const ReminderEditScreen({
    super.key,
    this.initialReminderAt,
    this.initialRepeatRule,
  });

  @override
  State<ReminderEditScreen> createState() => _ReminderEditScreenState();
}

class _ReminderEditScreenState extends State<ReminderEditScreen> {
  late DateTime _reminderAt;
  RepeatRule? _repeatRule;

  bool get _isEditingExisting => widget.initialReminderAt != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initial = widget.initialReminderAt;
    // An already-past reminder (the "reset an expired reminder" case)
    // can't be used as showDatePicker's own initialDate below - it
    // violates that picker's firstDate: now constraint, which would crash
    // rather than let it be reset. Falls back to the same "an hour from
    // now" default a genuinely new reminder starts with.
    _reminderAt = (initial != null && initial.isAfter(now))
        ? initial
        : now.add(const Duration(hours: 1));
    _repeatRule = widget.initialRepeatRule;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        _reminderAt.hour,
        _reminderAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _reminderAt = DateTime(
        _reminderAt.year,
        _reminderAt.month,
        _reminderAt.day,
        time.hour,
        time.minute,
      );
    });
  }

  bool _isQuickPreset(RepeatFrequency frequency) =>
      _repeatRule?.frequency == frequency &&
      (_repeatRule?.isSimplePreset ?? false);

  ListTile _repeatOptionTile({
    required String keySuffix,
    required String label,
    required bool selected,
    required BuildContext sheetContext,
  }) {
    return ListTile(
      key: Key('repeat_option_$keySuffix'),
      title: Text(label),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: () => Navigator.pop(sheetContext, keySuffix),
    );
  }

  /// Mirrors Google Calendar's own repeat picker: the original 5 fixed
  /// presets, "Every weekday" as a 6th quick option, and a trailing
  /// "Custom recurrence..." entry for anything more specific (see
  /// custom_recurrence_screen.dart). Plain checkmarked ListTiles rather
  /// than RadioListTile, whose groupValue/onChanged are deprecated as of
  /// Flutter 3.32 in favor of a RadioGroup ancestor - not worth wrapping
  /// this transient bottom sheet in one just for that (unlike
  /// CustomRecurrenceScreen's own persistent, inline "Ends" choice, which
  /// does use RadioGroup).
  Future<void> _pickRepeat() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            _repeatOptionTile(
              keySuffix: 'none',
              label: 'Does not repeat',
              selected: _repeatRule == null,
              sheetContext: sheetContext,
            ),
            for (final frequency in RepeatFrequency.values)
              _repeatOptionTile(
                keySuffix: frequency.name,
                label: _quickPresetLabel(frequency),
                selected: _isQuickPreset(frequency),
                sheetContext: sheetContext,
              ),
            _repeatOptionTile(
              keySuffix: 'everyWeekday',
              label: 'Every weekday',
              selected: _repeatRule?.isEveryWeekday ?? false,
              sheetContext: sheetContext,
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('repeat_option_custom'),
              title: const Text('Custom recurrence...'),
              onTap: () => Navigator.pop(sheetContext, 'custom'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'none':
        setState(() => _repeatRule = null);
      case 'everyWeekday':
        setState(() => _repeatRule = RepeatRule.everyWeekday());
      case 'custom':
        await _openCustomRecurrence();
      default:
        final frequency = RepeatFrequency.values.firstWhere(
          (f) => f.name == action,
        );
        setState(() => _repeatRule = RepeatRule.preset(frequency));
    }
  }

  Future<void> _openCustomRecurrence() async {
    final result = await Navigator.push<RepeatRule>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomRecurrenceScreen(
          initialRule: _repeatRule,
          startDate: _reminderAt,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _repeatRule = result);
  }

  void _save() {
    if (!_reminderAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a time that is still ahead.')),
      );
      return;
    }
    Navigator.pop(context, ReminderSet(_reminderAt, _repeatRule));
  }

  void _remove() => Navigator.pop(context, const ReminderRemoved());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEditingExisting ? 'Edit reminder' : 'New reminder'),
        actions: [
          // Only offered once there's an actual existing reminder to
          // remove - a brand-new one hasn't been saved anywhere yet, so
          // "remove" would be meaningless (see the close button above for
          // "never mind" in that case instead).
          if (_isEditingExisting)
            IconButton(
              key: const Key('reminder_edit_delete'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove reminder',
              onPressed: _remove,
            ),
          IconButton(
            key: const Key('reminder_edit_save'),
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            key: const Key('reminder_edit_date'),
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(DateFormat('EEE, MMM d, yyyy').format(_reminderAt)),
            onTap: _pickDate,
          ),
          ListTile(
            key: const Key('reminder_edit_time'),
            leading: const Icon(Icons.access_time),
            title: Text(DateFormat('h:mm a').format(_reminderAt)),
            onTap: _pickTime,
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('reminder_edit_repeat'),
            leading: const Icon(Icons.repeat),
            title: const Text('Repeat'),
            subtitle: Text(repeatRuleLabel(_repeatRule)),
            onTap: _pickRepeat,
          ),
        ],
      ),
    );
  }
}
