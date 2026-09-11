import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/repeat_rule.dart';
import '../services/notification_appearance_settings.dart';
import 'custom_recurrence_screen.dart';

/// What [ReminderEditScreen] hands back via Navigator.pop - null (no
/// result at all) means the user backed out without changing anything.
sealed class ReminderEditResult {
  const ReminderEditResult();
}

class ReminderSet extends ReminderEditResult {
  final DateTime reminderAt;
  final RepeatRule? repeatRule;
  final String? soundUri;
  final String? soundTitle;
  final NotificationIconOption icon;

  const ReminderSet(
    this.reminderAt,
    this.repeatRule, {
    this.soundUri,
    this.soundTitle,
    this.icon = NotificationIconOption.defaultIcon,
  });
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

/// A Flutter-side stand-in for each [NotificationIconOption]'s actual
/// Android drawable (a native resource this UI can't render directly) -
/// shown both as the Icon row's own leading icon and to the left of each
/// option's name in its picker, so the choice is recognizable at a glance
/// rather than by label text alone. A plain Material icon works fine as a
/// stand-in for [bell]/[star]/[pin]/[pencil], which already have an
/// obvious Material equivalent; [defaultIcon]'s real native drawable is
/// jotes' own "J" mark instead (see ic_stat_default.png), which no
/// Material icon resembles, so [iconPreviewWidget] below renders the same
/// glyph directly as an image rather than falling back to some unrelated
/// stand-in shape.
IconData _iconPreview(NotificationIconOption icon) => switch (icon) {
  NotificationIconOption.defaultIcon => Icons.notifications_none,
  NotificationIconOption.bell => Icons.notifications,
  NotificationIconOption.star => Icons.star,
  NotificationIconOption.pin => Icons.location_on,
  NotificationIconOption.pencil => Icons.edit,
};

/// The actual widget shown for [icon]'s preview - see [_iconPreview]'s own
/// doc comment for why [NotificationIconOption.defaultIcon] is special-cased
/// to an image instead. Tinted via [BlendMode.srcIn] against the ambient
/// icon color (same as how an [Icon] tints its glyph) so it matches the
/// other four options' color in both light and dark themes, rather than
/// showing this asset's own baked-in (white) pixels regardless of theme.
Widget _iconPreviewWidget(BuildContext context, NotificationIconOption icon) {
  if (icon == NotificationIconOption.defaultIcon) {
    return Image.asset(
      'assets/icon/notification_glyph.png',
      width: 24,
      height: 24,
      color: IconTheme.of(context).color,
      colorBlendMode: BlendMode.srcIn,
    );
  }
  return Icon(_iconPreview(icon));
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
  final String? initialSoundUri;
  final String? initialSoundTitle;
  final NotificationIconOption initialIcon;

  const ReminderEditScreen({
    super.key,
    this.initialReminderAt,
    this.initialRepeatRule,
    this.initialSoundUri,
    this.initialSoundTitle,
    this.initialIcon = NotificationIconOption.defaultIcon,
  });

  @override
  State<ReminderEditScreen> createState() => _ReminderEditScreenState();
}

class _ReminderEditScreenState extends State<ReminderEditScreen> {
  late DateTime _reminderAt;
  RepeatRule? _repeatRule;
  String? _soundUri;
  String? _soundTitle;
  late NotificationIconOption _icon;

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
    _soundUri = widget.initialSoundUri;
    _soundTitle = widget.initialSoundTitle;
    _icon = widget.initialIcon;
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

  PopupMenuItem<String> _repeatOptionTile({
    required String keySuffix,
    required String label,
    required bool selected,
  }) {
    return PopupMenuItem<String>(
      key: Key('repeat_option_$keySuffix'),
      value: keySuffix,
      child: ListTile(
        title: Text(label),
        trailing: selected ? const Icon(Icons.check) : null,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  /// Mirrors Google Calendar's own repeat picker: the original 5 fixed
  /// presets, "Every weekday" as a 6th quick option, and a trailing
  /// "Custom recurrence..." entry for anything more specific (see
  /// custom_recurrence_screen.dart). A popup anchored right next to the
  /// Repeat row itself (see [anchorContext]) rather than a bottom sheet -
  /// same technique, same reasoning, as notes_screen.dart's own anchored
  /// pickers (Filter/Layout/Sort).
  Future<void> _pickRepeat(BuildContext anchorContext) async {
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final button = anchorContext.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: anchorContext,
      position: position,
      items: [
        _repeatOptionTile(
          keySuffix: 'none',
          label: 'Does not repeat',
          selected: _repeatRule == null,
        ),
        for (final frequency in RepeatFrequency.values)
          _repeatOptionTile(
            keySuffix: frequency.name,
            label: _quickPresetLabel(frequency),
            selected: _isQuickPreset(frequency),
          ),
        _repeatOptionTile(
          keySuffix: 'everyWeekday',
          label: 'Every weekday',
          selected: _repeatRule?.isEveryWeekday ?? false,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: const Key('repeat_option_custom'),
          value: 'custom',
          child: const ListTile(
            title: Text('Custom recurrence...'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
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

  /// Offers this device's own notification sounds (see
  /// NotificationAppearanceSettings.systemSoundOptions - queried fresh on
  /// each tap rather than once in initState, so a platform failure only
  /// costs this one tap being a no-op rather than gating the whole row
  /// behind an async load). Anchored next to the Sound row, same technique
  /// as [_pickRepeat].
  Future<void> _pickSound(BuildContext anchorContext) async {
    // Computed before the systemSoundOptions() await below, same as
    // _pickRepeat's own (synchronous) position calc - avoids carrying a
    // BuildContext-derived RenderBox across an async gap.
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final button = anchorContext.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final options = await NotificationAppearanceSettings.instance
        .systemSoundOptions();
    if (!anchorContext.mounted || options.isEmpty) return;

    final selected = await showMenu<NotificationSoundOption>(
      context: anchorContext,
      position: position,
      items: [
        for (final option in options)
          PopupMenuItem<NotificationSoundOption>(
            key: Key('reminder_sound_option_${option.uri}'),
            value: option,
            // Fixed width, same reasoning (and same value) as the icon
            // picker's own options below - a system sound's title can be
            // just as short as "Default", and PopupMenuItem's intrinsic
            // sizing can squeeze a short label into an unwanted wrap.
            child: SizedBox(
              width: 220,
              child: ListTile(
                title: Text(option.title),
                trailing:
                    NotificationAppearanceSettings.instance.isSelectedSound(
                      _soundUri,
                      option.uri,
                    )
                    ? const Icon(Icons.check)
                    : null,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() {
      _soundUri = selected.uri;
      _soundTitle = selected.title;
    });
  }

  /// Anchored next to the Icon row, same technique as [_pickRepeat].
  Future<void> _pickIcon(BuildContext anchorContext) async {
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final button = anchorContext.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<NotificationIconOption>(
      context: anchorContext,
      position: position,
      items: [
        for (final option in NotificationIconOption.values)
          PopupMenuItem<NotificationIconOption>(
            key: Key('reminder_icon_option_${option.name}'),
            value: option,
            // A fixed width, not just contentPadding: EdgeInsets.zero like
            // the other pickers' plain-text options - PopupMenuItem sizes
            // itself to its child's intrinsic width, and a ListTile with a
            // leading icon (unlike Repeat's own icon-less options above)
            // reports a narrower one than it actually needs, squeezing
            // even a short label like "Default" into an unwanted two-line
            // wrap ("Defaul" / "t").
            child: SizedBox(
              width: 220,
              child: ListTile(
                leading: _iconPreviewWidget(context, option),
                title: Text(option.label),
                trailing: option == _icon ? const Icon(Icons.check) : null,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() => _icon = selected);
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
    Navigator.pop(
      context,
      ReminderSet(
        _reminderAt,
        _repeatRule,
        soundUri: _soundUri,
        soundTitle: _soundTitle,
        icon: _icon,
      ),
    );
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
          Builder(
            builder: (repeatRowContext) => ListTile(
              key: const Key('reminder_edit_repeat'),
              leading: const Icon(Icons.repeat),
              title: const Text('Repeat'),
              subtitle: Text(repeatRuleLabel(_repeatRule)),
              onTap: () => _pickRepeat(repeatRowContext),
            ),
          ),
          const Divider(height: 1),
          Builder(
            builder: (soundRowContext) => ListTile(
              key: const Key('reminder_edit_sound'),
              leading: const Icon(Icons.volume_up_outlined),
              title: const Text('Notification sound'),
              subtitle: Text(_soundTitle ?? 'Default'),
              onTap: () => _pickSound(soundRowContext),
            ),
          ),
          Builder(
            builder: (iconRowContext) => ListTile(
              key: const Key('reminder_edit_icon'),
              leading: _iconPreviewWidget(iconRowContext, _icon),
              title: const Text('Notification icon'),
              subtitle: Text(_icon.label),
              onTap: () => _pickIcon(iconRowContext),
            ),
          ),
        ],
      ),
    );
  }
}
