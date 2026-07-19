import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';

/// A section grouping's own name ("Appearance", "Data") - the most visually
/// prominent text when scanning the list, bar the brand lockup itself.
class SectionLabel extends StatelessWidget {
  final String label;

  const SectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.of(context).sectionLabel,
      ),
    );
  }
}

/// A caption naming what the control directly below it does ("Theme",
/// "Font", "Text size") - deliberately the smallest, most muted text on the
/// screen, since it's read once and then the control itself takes over.
class FieldLabel extends StatelessWidget {
  final String label;

  const FieldLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(label, style: AppTextStyles.of(context).fieldLabel),
    );
  }
}
