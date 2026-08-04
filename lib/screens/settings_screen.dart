import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/appearance_provider.dart';
import '../providers/theme_provider.dart';
import '../services/autostart_service.dart';
import '../services/snooze_settings.dart';
import '../theme/app_text_styles.dart';
import '../widgets/settings_labels.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final appearance = ref.watch(appearanceProvider);
    final itemStyle = AppTextStyles.of(context).item;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SectionLabel('Appearance'),
          const FieldLabel('Theme'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: LayoutBuilder(
              builder: (context, constraints) => DropdownMenu<ThemeMode>(
                key: const Key('theme_dropdown'),
                width: constraints.maxWidth,
                textStyle: itemStyle,
                initialSelection: themeMode,
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: ThemeMode.light, label: 'Light'),
                  DropdownMenuEntry(value: ThemeMode.dark, label: 'Dark'),
                  DropdownMenuEntry(value: ThemeMode.system, label: 'System'),
                ],
                onSelected: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).setThemeMode(mode);
                  }
                },
              ),
            ),
          ),
          const FieldLabel('Font'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: LayoutBuilder(
              builder: (context, constraints) => DropdownMenu<AppFont>(
                key: const Key('font_dropdown'),
                width: constraints.maxWidth,
                textStyle: itemStyle,
                initialSelection: appearance.font,
                dropdownMenuEntries: [
                  for (final font in AppFont.values)
                    DropdownMenuEntry(
                      value: font,
                      label: font.label,
                      labelWidget: Text(
                        font.label,
                        style: font.style(itemStyle),
                      ),
                    ),
                ],
                onSelected: (font) {
                  if (font != null) {
                    ref.read(appearanceProvider.notifier).setFont(font);
                  }
                },
              ),
            ),
          ),
          const FieldLabel('Text size'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: LayoutBuilder(
              builder: (context, constraints) => DropdownMenu<TextSizeOption>(
                key: const Key('text_size_dropdown'),
                width: constraints.maxWidth,
                textStyle: itemStyle,
                initialSelection: appearance.textSize,
                dropdownMenuEntries: [
                  for (final size in TextSizeOption.values)
                    DropdownMenuEntry(value: size, label: size.label),
                ],
                onSelected: (size) {
                  if (size != null) {
                    ref.read(appearanceProvider.notifier).setTextSize(size);
                  }
                },
              ),
            ),
          ),
          const SectionLabel('Reminders'),
          const _SnoozeDurationSetting(),
          const _AutostartSetting(),
        ],
      ),
    );
  }
}

/// Configures the Snooze action button on a fired reminder's notification
/// (see handleBackgroundReminderAction in notification_service.dart) -
/// that background isolate has no UI of its own to offer a choice at the
/// time, so the choice is made once here instead. A few fixed presets cover
/// the common case with no extra setup; "Custom delay" and "Time of day"
/// reveal an extra field for anything else. Backed directly by
/// SnoozeSettings' own SharedPreferences storage, not a Riverpod provider,
/// since that same background isolate has no ProviderScope to read a
/// provider from either - this screen just happens to be the one place in
/// the app that also touches it directly.
class _SnoozeDurationSetting extends StatefulWidget {
  const _SnoozeDurationSetting();

  @override
  State<_SnoozeDurationSetting> createState() => _SnoozeDurationSettingState();
}

class _SnoozeDurationSettingState extends State<_SnoozeDurationSetting> {
  SnoozeMode? _mode;
  TimeOfDay? _timeOfDay;
  final _customHoursController = TextEditingController();
  final _customMinutesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await SnoozeSettings.instance.getMode();
    final customMinutes = await SnoozeSettings.instance.getCustomDelayMinutes();
    final timeOfDayMinutes = await SnoozeSettings.instance
        .getTimeOfDayMinutes();
    if (!mounted) return;
    _customHoursController.text = (customMinutes ~/ 60).toString();
    _customMinutesController.text = (customMinutes % 60).toString();
    setState(() {
      _mode = mode;
      _timeOfDay = TimeOfDay(
        hour: timeOfDayMinutes ~/ 60,
        minute: timeOfDayMinutes % 60,
      );
    });
  }

  @override
  void dispose() {
    _customHoursController.dispose();
    _customMinutesController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomDelay() async {
    final hours = int.tryParse(_customHoursController.text) ?? 0;
    final minutes = int.tryParse(_customMinutesController.text) ?? 0;
    await SnoozeSettings.instance.setCustomDelayMinutes(hours * 60 + minutes);
  }

  Future<void> _pickTimeOfDay() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDay ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null) return;
    setState(() => _timeOfDay = picked);
    await SnoozeSettings.instance.setTimeOfDayMinutes(
      picked.hour * 60 + picked.minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemStyle = AppTextStyles.of(context).item;
    final mode = _mode;
    if (mode == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Snooze'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) => DropdownMenu<SnoozeMode>(
              key: const Key('snooze_mode_dropdown'),
              width: constraints.maxWidth,
              textStyle: itemStyle,
              initialSelection: mode,
              dropdownMenuEntries: [
                for (final option in SnoozeMode.values)
                  DropdownMenuEntry(value: option, label: option.label),
              ],
              onSelected: (selected) {
                if (selected == null) return;
                setState(() => _mode = selected);
                SnoozeSettings.instance.setMode(selected);
              },
            ),
          ),
        ),
        if (mode == SnoozeMode.custom)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('snooze_custom_hours_field'),
                    controller: _customHoursController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Hours'),
                    onChanged: (_) => _saveCustomDelay(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('snooze_custom_minutes_field'),
                    controller: _customMinutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes'),
                    onChanged: (_) => _saveCustomDelay(),
                  ),
                ),
              ],
            ),
          ),
        if (mode == SnoozeMode.timeOfDay)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ListTile(
              key: const Key('snooze_time_of_day_tile'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Time'),
              subtitle: Text(_timeOfDay?.format(context) ?? ''),
              trailing: const Icon(Icons.access_time),
              onTap: _pickTimeOfDay,
            ),
          ),
      ],
    );
  }
}

/// A persistent entry point to this device's autostart/background-restriction
/// settings, shown only on manufacturers known to ship such a screen (the
/// same gate as the one-time banner in notes_screen.dart - so Pixel and
/// other non-restrictive devices don't see an irrelevant control). Unlike
/// that banner, this is always available here rather than dismissable once,
/// so the deep-link stays reachable after the banner is gone. Renders
/// nothing while the (async, method-channel) manufacturer check is in
/// flight or on a non-restrictive device.
class _AutostartSetting extends StatelessWidget {
  const _AutostartSetting();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AutostartService.instance.isKnownRestrictiveManufacturer(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return ListTile(
          key: const Key('autostart_setting'),
          title: const Text('Reminder auto-start'),
          subtitle: const Text(
            "Your device may stop reminders from reappearing after a "
            "restart unless jotes is allowed to auto-start. Opens your "
            "device's background-activity settings.",
          ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => AutostartService.instance.openAutostartSettings(),
        );
      },
    );
  }
}
