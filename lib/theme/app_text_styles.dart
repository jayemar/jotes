import 'package:flutter/material.dart';

/// Text styles shared by the drawer and the Settings screen, registered per
/// [ThemeData] (see main.dart) so they stay colorScheme-aware without every
/// screen re-deriving them from ad-hoc helper methods of its own.
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  final TextStyle sectionLabel;
  final TextStyle fieldLabel;
  final TextStyle item;

  const AppTextStyles({
    required this.sectionLabel,
    required this.fieldLabel,
    required this.item,
  });

  factory AppTextStyles.fromColorScheme(ColorScheme scheme) {
    return AppTextStyles(
      sectionLabel: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: scheme.primary,
      ),
      fieldLabel: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
      item: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
    );
  }

  /// Falls back to deriving styles from the ambient colorScheme if no
  /// extension is registered (e.g. a test harness that builds a screen
  /// under a plain MaterialApp rather than through JotesApp's ThemeData),
  /// rather than asserting - the fallback matches what main.dart registers
  /// anyway, so this only ever differs in tests, never in the real app.
  static AppTextStyles of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppTextStyles>() ??
        AppTextStyles.fromColorScheme(theme.colorScheme);
  }

  @override
  AppTextStyles copyWith({
    TextStyle? sectionLabel,
    TextStyle? fieldLabel,
    TextStyle? item,
  }) {
    return AppTextStyles(
      sectionLabel: sectionLabel ?? this.sectionLabel,
      fieldLabel: fieldLabel ?? this.fieldLabel,
      item: item ?? this.item,
    );
  }

  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    return AppTextStyles(
      sectionLabel: TextStyle.lerp(sectionLabel, other.sectionLabel, t)!,
      fieldLabel: TextStyle.lerp(fieldLabel, other.fieldLabel, t)!,
      item: TextStyle.lerp(item, other.item, t)!,
    );
  }
}
