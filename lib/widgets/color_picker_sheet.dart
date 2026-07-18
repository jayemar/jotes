import 'package:flutter/material.dart';
import '../models/note.dart';

/// Shows a bottom sheet of [kNoteColors] swatches and resolves to the
/// tapped color's index, or null if dismissed without a selection.
Future<int?> showColorPickerSheet(BuildContext context, {int? selected}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(kNoteColors.length, (i) {
            final isSelected = selected == i;
            final swatchColor = noteColorFor(ctx, i);
            final isDark =
                ThemeData.estimateBrightnessForColor(swatchColor) ==
                    Brightness.dark;
            return GestureDetector(
              key: ValueKey('color_swatch_$i'),
              onTap: () => Navigator.pop(ctx, i),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: swatchColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.black26,
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: isDark ? Colors.white : Colors.black54,
                      )
                    : null,
              ),
            );
          }),
        ),
      ),
    ),
  );
}
