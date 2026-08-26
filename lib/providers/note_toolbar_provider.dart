import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _orderPrefsKey = 'note_toolbar_order';
const _hiddenPrefsKey = 'note_toolbar_hidden';

/// One customizable tool in the note editor's bottom toolbar (see
/// note_editor_screen.dart) - deliberately just the text-editing tools
/// that operate on the body while typing, not the whole-note actions
/// (Pin/Change color/Export/Share/Duplicate/Delete) that live in the
/// overflow menu instead and aren't part of this customization.
enum NoteToolbarTool {
  checklist(Icons.check_box_outlined, 'Toggle checklist item'),
  bullet(Icons.format_list_bulleted_outlined, 'Toggle list item'),
  moveUp(Icons.arrow_upward_outlined, 'Move line up'),
  moveDown(Icons.arrow_downward_outlined, 'Move line down'),
  cutLine(Icons.content_cut, 'Cut line'),
  paste(Icons.content_paste, 'Paste'),
  undo(Icons.undo, 'Undo');

  const NoteToolbarTool(this.icon, this.label);

  /// The tool's own glyph - for most tools this is exactly what's shown,
  /// but see [noteToolbarIcon] for the one exception ([cutLine], which
  /// pairs this with a line underneath it) actually rendered in the
  /// toolbar and NoteToolbarSettingsScreen.
  final IconData icon;
  final String label;
}

/// Builds the icon widget for [tool] - [NoteToolbarTool.icon] itself for
/// every tool except [NoteToolbarTool.cutLine], which pairs the usual
/// scissors glyph with a short horizontal line beneath it, the same "cut
/// along this line" motif as a coupon's own dashed-line-and-scissors icon.
/// Bare scissors alone reads as "cut the current selection" (the far more
/// common meaning of that glyph); this tool actually cuts the whole
/// current line instead (see NoteBodyEditorState.cutLine), which the
/// bare icon doesn't convey. Shared by note_editor_screen.dart's own
/// toolbar and NoteToolbarSettingsScreen, so both show the same glyph.
Widget noteToolbarIcon(NoteToolbarTool tool, {double size = 24, Color? color}) {
  if (tool != NoteToolbarTool.cutLine) {
    return Icon(tool.icon, size: size, color: color);
  }
  return SizedBox(
    width: size,
    height: size,
    // The line beneath the scissors needs a color even when [color] isn't
    // given - a bare Icon resolves that same case via the ambient
    // IconTheme automatically, so this does too (via Builder, to reach
    // the surrounding IconTheme.of(context)) rather than falling back to
    // a hardcoded color that would go invisible against a dark note.
    child: Builder(
      builder: (context) {
        final lineColor =
            color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            Icon(tool.icon, size: size * 0.78, color: color),
            Positioned(
              bottom: size * 0.08,
              child: Container(
                width: size * 0.8,
                height: size * 0.07,
                color: lineColor,
              ),
            ),
          ],
        );
      },
    ),
  );
}

class NoteToolbarState {
  /// Every tool, in the user's chosen display order - includes hidden
  /// ones too, so re-showing one restores it to wherever it last was
  /// rather than always landing back at the end.
  final List<NoteToolbarTool> order;
  final Set<NoteToolbarTool> hidden;

  const NoteToolbarState({required this.order, required this.hidden});

  static const initial = NoteToolbarState(
    order: NoteToolbarTool.values,
    hidden: {},
  );

  /// What note_editor_screen.dart's own toolbar Row actually builds from -
  /// [order] with anything in [hidden] filtered out.
  List<NoteToolbarTool> get visibleInOrder =>
      order.where((t) => !hidden.contains(t)).toList();
}

/// Persisted (SharedPreferences, same pattern as NotesViewNotifier) so the
/// note editor's own toolbar customization survives an app restart.
class NoteToolbarNotifier extends Notifier<NoteToolbarState> {
  @override
  NoteToolbarState build() {
    _load();
    return NoteToolbarState.initial;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final byName = {for (final t in NoteToolbarTool.values) t.name: t};

    final savedOrder = prefs.getStringList(_orderPrefsKey);
    final order = savedOrder != null
        ? _resolveOrder(savedOrder, byName)
        : NoteToolbarTool.values;

    final savedHidden = prefs.getStringList(_hiddenPrefsKey) ?? const [];
    final hidden = savedHidden
        .map((name) => byName[name])
        .whereType<NoteToolbarTool>()
        .toSet();

    state = NoteToolbarState(order: order, hidden: hidden);
  }

  /// Resolves a persisted order list back into [NoteToolbarTool]s,
  /// tolerating drift between what was saved and what the app currently
  /// defines: an unrecognized saved name (e.g. a tool removed in a later
  /// version) is silently dropped, and a tool the saved order doesn't
  /// mention at all (e.g. one added in a later version) is appended at
  /// the end - never crashes or silently loses a whole tool either way.
  List<NoteToolbarTool> _resolveOrder(
    List<String> saved,
    Map<String, NoteToolbarTool> byName,
  ) {
    final result = <NoteToolbarTool>[for (final name in saved) ?byName[name]];
    for (final tool in NoteToolbarTool.values) {
      if (!result.contains(tool)) result.add(tool);
    }
    return result;
  }

  Future<void> setOrder(List<NoteToolbarTool> order) async {
    state = NoteToolbarState(order: order, hidden: state.hidden);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _orderPrefsKey,
      order.map((t) => t.name).toList(),
    );
  }

  Future<void> setHidden(NoteToolbarTool tool, bool hidden) async {
    final newHidden = {...state.hidden};
    if (hidden) {
      newHidden.add(tool);
    } else {
      newHidden.remove(tool);
    }
    state = NoteToolbarState(order: state.order, hidden: newHidden);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _hiddenPrefsKey,
      newHidden.map((t) => t.name).toList(),
    );
  }
}

final noteToolbarProvider =
    NotifierProvider<NoteToolbarNotifier, NoteToolbarState>(
      NoteToolbarNotifier.new,
    );
