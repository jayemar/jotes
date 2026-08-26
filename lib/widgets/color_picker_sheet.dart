import 'package:flutter/material.dart';
import '../models/note.dart';

/// Shows a popup of [kNoteColors] swatches, anchored right next to
/// whichever widget triggered it, resolving to the tapped color's index
/// (or null if dismissed without a selection). [anchorContext] should be
/// the BuildContext of the specific tapped widget (see call sites, each
/// wrapping their trigger in a Builder to get one), so the popup lands
/// beside it rather than at some fixed screen position - same reasoning,
/// same technique, as notes_screen.dart's own anchored pickers (Filter/
/// Layout/Sort).
///
/// Each swatch pops the menu itself (via its own nested GestureDetector,
/// not PopupMenuItem's built-in tap-to-select) since they're all packed
/// into a single Wrap rather than one PopupMenuItem per color - PopupMenu
/// entries otherwise always stack in a plain vertical Column, which would
/// turn this compact grid into a tall list. The wrapping PopupMenuItem is
/// `enabled: false` purely so its own InkWell doesn't compete with (and
/// swallow) those nested taps - Flutter leaves the child fully hit-testable
/// either way (see PopupMenuItemState.build: enabled:false only nulls out
/// InkWell's onTap and dims IconTheme, it doesn't wrap in IgnorePointer).
Future<int?> showColorPickerSheet(
  BuildContext anchorContext, {
  int? selected,
}) {
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

  return showMenu<int>(
    context: anchorContext,
    position: position,
    items: [
      PopupMenuItem<int>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 220,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(kNoteColors.length, (i) {
                final isSelected = selected == i;
                final swatchColor = noteColorFor(anchorContext, i);
                final isDark =
                    ThemeData.estimateBrightnessForColor(swatchColor) ==
                    Brightness.dark;
                return Builder(
                  builder: (menuContext) => GestureDetector(
                    key: ValueKey('color_swatch_$i'),
                    onTap: () => Navigator.pop(menuContext, i),
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
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    ],
  );
}
