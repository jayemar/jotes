import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fontPrefsKey = 'appearance_font';
const _textScalePrefsKey = 'appearance_text_scale';

/// The 4 curated fonts bundled under assets/google_fonts/ (see main.dart's
/// GoogleFonts.config.allowRuntimeFetching = false - these are the only
/// choices because they're the only ones actually bundled offline).
enum AppFont {
  defaultFont('Default'),
  serif('Serif'),
  monospace('Monospace'),
  rounded('Rounded');

  const AppFont(this.label);

  /// Shown in the Settings picker.
  final String label;
}

/// Applies an [AppFont] via google_fonts' own per-font functions (not the
/// bare fontFamily string / GoogleFonts.getFont dynamic lookup) - the
/// dynamic lookup needs the font's official catalog name ("Roboto Mono",
/// with a space), which differs from the asset-matching name
/// ("RobotoMono", no space) used for the bundled files, and mixing the two
/// up is exactly what silently no-ops instead of applying the font: a bare
/// TextStyle(fontFamily: 'RobotoMono') never touches google_fonts' loading
/// path at all, so nothing ever registers that family with Flutter, and it
/// falls back to the ambient default with no error. Static per-font
/// functions sidestep name-matching entirely and are compiler-checked.
extension AppFontStyling on AppFont {
  TextStyle style([TextStyle? textStyle]) {
    switch (this) {
      case AppFont.defaultFont:
        return GoogleFonts.inter(textStyle: textStyle);
      case AppFont.serif:
        return GoogleFonts.lora(textStyle: textStyle);
      case AppFont.monospace:
        return GoogleFonts.robotoMono(textStyle: textStyle);
      case AppFont.rounded:
        return GoogleFonts.quicksand(textStyle: textStyle);
    }
  }

  TextTheme textTheme([TextTheme? base]) {
    switch (this) {
      case AppFont.defaultFont:
        return GoogleFonts.interTextTheme(base);
      case AppFont.serif:
        return GoogleFonts.loraTextTheme(base);
      case AppFont.monospace:
        return GoogleFonts.robotoMonoTextTheme(base);
      case AppFont.rounded:
        return GoogleFonts.quicksandTextTheme(base);
    }
  }
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
