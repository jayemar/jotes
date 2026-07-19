import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/appearance_provider.dart';
import '../providers/theme_provider.dart';
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
        ],
      ),
    );
  }
}
