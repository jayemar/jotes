import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fontPrefsKey = 'appearance_font';
const _textScalePrefsKey = 'appearance_text_scale';

/// The 4 curated fonts bundled under assets/google_fonts/ (see main.dart's
/// GoogleFonts.config.allowRuntimeFetching = false - these are the only
/// choices because they're the only ones actually bundled offline).
enum AppFont {
  defaultFont('Default', 'Inter'),
  serif('Serif', 'Lora'),
  monospace('Monospace', 'RobotoMono'),
  rounded('Rounded', 'Quicksand');

  const AppFont(this.label, this.fontFamily);

  /// Shown in the Settings picker.
  final String label;

  /// Matches the bundled asset filenames (e.g. "Inter-Regular.ttf") and the
  /// family name google_fonts registers them under.
  final String fontFamily;
}

/// A small set of named steps rather than a free slider - easier to reason
/// about ("Large" always means the same thing) and to persist/restore.
enum TextSizeOption {
  small('Small', 0.85),
  medium('Medium', 1.0),
  large('Large', 1.15),
  extraLarge('Extra large', 1.3);

  const TextSizeOption(this.label, this.scale);

  final String label;
  final double scale;
}

class AppearanceState {
  final AppFont font;
  final TextSizeOption textSize;

  const AppearanceState({required this.font, required this.textSize});

  static const initial =
      AppearanceState(font: AppFont.defaultFont, textSize: TextSizeOption.medium);
}

class AppearanceNotifier extends Notifier<AppearanceState> {
  @override
  AppearanceState build() {
    _load();
    return AppearanceState.initial;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedFont = prefs.getString(_fontPrefsKey);
    final font = AppFont.values.firstWhere(
      (f) => f.name == storedFont,
      orElse: () => AppFont.defaultFont,
    );
    final storedTextSize = prefs.getString(_textScalePrefsKey);
    final textSize = TextSizeOption.values.firstWhere(
      (t) => t.name == storedTextSize,
      orElse: () => TextSizeOption.medium,
    );
    state = AppearanceState(font: font, textSize: textSize);
  }

  Future<void> setFont(AppFont font) async {
    state = AppearanceState(font: font, textSize: state.textSize);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontPrefsKey, font.name);
  }

  Future<void> setTextSize(TextSizeOption textSize) async {
    state = AppearanceState(font: state.font, textSize: textSize);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textScalePrefsKey, textSize.name);
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, AppearanceState>(
  AppearanceNotifier.new,
);
