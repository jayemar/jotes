import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

import 'note_body_editor.dart'
    show
        BodyBlock,
        ChecklistBodyBlock,
        ParsedBlock,
        TextBodyBlock,
        checklistIndentStepPx,
        maxChecklistIndent,
        parseBodyWithOffsets;

/// One block as rendered in view mode - wraps a [ParsedBlock] with a
/// [GlobalKey] used only for the duration of a single drag gesture (see
/// _handleDragEnd below) to look up its currently-rendered position. A
/// fresh set of these is created on every parse, same as [RenderSegment] -
/// view mode has no per-item state to preserve across rebuilds, since
/// nothing is being typed here (that only happens in edit mode - see
/// NoteBodyEditorState in note_body_editor.dart).
class ViewBlock {
  final ParsedBlock parsed;
  final GlobalKey rowKey = GlobalKey();

  ViewBlock(this.parsed);

  BodyBlock get block => parsed.block;
  bool get isChecklist => block is ChecklistBodyBlock;
}

/// One item in the flattened list [NoteBodyView] actually renders: either
/// a single plain-text block, or a whole contiguous run of checklist
/// blocks (rendered together - see _buildChecklistRun - so dragging to
/// reorder one checklist item can only ever land among the other items in
/// the same run, never past a paragraph that splits two separate
/// checklist groups apart).
class RenderSegment {
  final int start;
  final int end; // exclusive
  final bool isChecklistRun;

  RenderSegment.single(int index)
    : start = index,
      end = index + 1,
      isChecklistRun = false;

  RenderSegment.run(this.start, this.end) : isChecklistRun = true;
}

List<RenderSegment> computeSegments(List<ViewBlock> blocks) {
  final segments = <RenderSegment>[];
  var i = 0;
  while (i < blocks.length) {
    if (!blocks[i].isChecklist) {
      segments.add(RenderSegment.single(i));
      i += 1;
    } else {
      final start = i;
      while (i < blocks.length && blocks[i].isChecklist) {
        i += 1;
      }
      segments.add(RenderSegment.run(start, i));
    }
  }
  return segments;
}

/// Maps a tap at [globalPosition] on the text rendered under [textKey] to
/// an absolute offset in the raw body, via [textStart] (see ParsedBlock) -
/// the offset where that block's own text begins in the raw string. Falls
/// back to [textStart] itself if the text hasn't been laid out yet (e.g.
/// an empty block with nothing rendered to hit-test against).
void _tapToOffset({
  required GlobalKey textKey,
  required Offset globalPosition,
  required int textStart,
  required ValueChanged<int> onOffset,
}) {
  final renderParagraph =
      textKey.currentContext?.findRenderObject() as RenderParagraph?;
  if (renderParagraph == null) {
    onOffset(textStart);
    return;
  }
  final local = renderParagraph.globalToLocal(globalPosition);
  final position = renderParagraph.getPositionForOffset(local);
  onOffset(textStart + position.offset);
}

/// Read-only(-ish) rendering of a note body: plain text as static text,
/// checklist items as a tappable [Checkbox] + draggable handle (reorder
/// vertically, indent horizontally - see _ChecklistViewRow) + static text.
/// Tapping a block's text - or the blank space below the last one -
/// switches to edit mode via [onEnterEditAt], with the raw-body cursor
/// offset to place the cursor at. Toggling/dragging/deleting act
/// immediately (through [onToggle]/[onDragCommit]/[onDelete]) and stay in
/// view mode - see note_body_editor.dart's NoteBodyEditorState for why.
class NoteBodyView extends StatelessWidget {
  final String body;
  final Color textColor;
  final Color hintColor;
  final ValueChanged<int> onEnterEditAt;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onDelete;
  final void Function(int fromIndex, int toIndex, int newIndent) onDragCommit;

  const NoteBodyView({
    super.key,
    required this.body,
    required this.textColor,
    required this.hintColor,
    required this.onEnterEditAt,
    required this.onToggle,
    required this.onDelete,
    required this.onDragCommit,
  });

  @override
  Widget build(BuildContext context) {
    // An entirely empty note has nothing to render or tap into
    // block-by-block - just a hint, tapping anywhere on it starts editing
    // at the beginning. A brand-new note skips view mode entirely (see
    // NoteBodyEditorState.initState's autofocusFirst handling), so this
    // only shows up for an existing note whose body became fully empty.
    if (body.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onEnterEditAt(0),
        // Without SizedBox.expand, this GestureDetector's hit area shrinks
        // to the "Note" text's own intrinsic size - just that one word,
        // wherever this widget's parent happens to position it (typically
        // centered, since Column defaults to centering a shrink-wrapped
        // child) - rather than the full Expanded box this sits in (see
        // note_editor_screen.dart), leaving the rest of the visible note
        // area untappable. Same fix, same reasoning, as edit mode's own
        // TextField.expands (see note_body_editor.dart's build method).
        child: SizedBox.expand(
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              'Note',
              style: TextStyle(fontSize: 15, color: hintColor),
            ),
          ),
        ),
      );
    }

    final viewBlocks = parseBodyWithOffsets(body).map(ViewBlock.new).toList();
    final segments = computeSegments(viewBlocks);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onEnterEditAt(body.length),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: segments.length,
        itemBuilder: (context, segIndex) {
          final segment = segments[segIndex];
          return segment.isChecklistRun
              ? _buildChecklistRun(viewBlocks, segment)
              : _buildTextBlock(viewBlocks[segment.start]);
        },
      ),
    );
  }

  Widget _buildTextBlock(ViewBlock viewBlock) {
    final parsed = viewBlock.parsed;
    final text = (parsed.block as TextBodyBlock).text;
    final textKey = GlobalKey();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _tapToOffset(
          textKey: textKey,
          globalPosition: details.globalPosition,
          textStart: parsed.textStart,
          onOffset: onEnterEditAt,
        ),
        child: text.isEmpty
            ? const SizedBox(height: 20, width: double.infinity)
            : Text.rich(
                key: textKey,
                TextSpan(
                  text: text,
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
      ),
    );
  }

  Widget _buildChecklistRun(List<ViewBlock> viewBlocks, RenderSegment segment) {
    // Resolves one drag-handle gesture's raw (dx, dy) into an absolute
    // (fromIndex, toIndex, newIndent) instruction for onDragCommit - the
    // position geometry lives here, where the run's rowKeys are in scope,
    // rather than in NoteBodyEditorState, which only owns the resulting
    // data mutation.
    void handleDragEnd(int localIndex, double dx, double dy) {
      final runBlocks = viewBlocks.sublist(segment.start, segment.end);
      final draggedViewBlock = runBlocks[localIndex];
      final block = draggedViewBlock.block as ChecklistBodyBlock;

      var newLocalIndex = localIndex;
      final draggedBox =
          draggedViewBlock.rowKey.currentContext?.findRenderObject()
              as RenderBox?;
      if (draggedBox != null && draggedBox.hasSize) {
        final draggedMidY =
            draggedBox.localToGlobal(Offset(0, draggedBox.size.height / 2)).dy +
            dy;
        var bestIndex = localIndex;
        var bestDistance = double.infinity;
        for (var i = 0; i < runBlocks.length; i++) {
          final siblingBox =
              runBlocks[i].rowKey.currentContext?.findRenderObject()
                  as RenderBox?;
          if (siblingBox == null || !siblingBox.hasSize) continue;
          final siblingMidY = siblingBox
              .localToGlobal(Offset(0, siblingBox.size.height / 2))
              .dy;
          final distance = (siblingMidY - draggedMidY).abs();
          if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = i;
          }
        }
        newLocalIndex = bestIndex;
      }

      final newIndent =
          ((block.indent * checklistIndentStepPx + dx) / checklistIndentStepPx)
              .round()
              .clamp(0, maxChecklistIndent);

      onDragCommit(
        segment.start + localIndex,
        segment.start + newLocalIndex,
        newIndent,
      );
    }

    return Column(
      children: [
        for (var i = segment.start; i < segment.end; i++)
          _ChecklistViewRow(
            key: ValueKey(i),
            viewBlock: viewBlocks[i],
            textColor: textColor,
            hintColor: hintColor,
            onToggle: () => onToggle(i),
            onDelete: () => onDelete(i),
            onDragEnd: (dx, dy) => handleDragEnd(i - segment.start, dx, dy),
            onTapText: onEnterEditAt,
          ),
      ],
    );
  }
}

class _ChecklistViewRow extends StatefulWidget {
  final ViewBlock viewBlock;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  // Total (dx, dy) since the drag-handle gesture started - see
  // NoteBodyView._buildChecklistRun.handleDragEnd, which interprets dy as
  // a reorder target and dx as an indent level from the same single drag.
  final void Function(double dx, double dy) onDragEnd;
  // Absolute offset in the raw body where the tapped text position maps
  // to - see _tapToOffset.
  final ValueChanged<int> onTapText;

  const _ChecklistViewRow({
    super.key,
    required this.viewBlock,
    required this.textColor,
    required this.hintColor,
    required this.onToggle,
    required this.onDelete,
    required this.onDragEnd,
    required this.onTapText,
  });

  @override
  State<_ChecklistViewRow> createState() => _ChecklistViewRowState();
}

class _ChecklistViewRowState extends State<_ChecklistViewRow> {
  // Non-zero only while a drag is actively in progress, so the row can
  // live-preview its new indent as soon as it's dragged, before the drag
  // ends and the change actually commits.
  bool _dragging = false;
  double _dragDx = 0;
  double _dragDy = 0;
  final GlobalKey _textKey = GlobalKey();

  void _onDragStarted() {
    setState(() {
      _dragging = true;
      _dragDx = 0;
      _dragDy = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragDx += details.delta.dx;
      _dragDy += details.delta.dy;
    });
  }

  void _onDragEnd(DraggableDetails _) {
    widget.onDragEnd(_dragDx, _dragDy);
    setState(() {
      _dragging = false;
      _dragDx = 0;
      _dragDy = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.viewBlock.block as ChecklistBodyBlock;
    final parsed = widget.viewBlock.parsed;

    // Live-previews the drag's horizontal axis as indent while it's in
    // progress, same as the committed result will be; the vertical axis
    // only matters once the drag ends (see handleDragEnd) - Keep's own
    // reordering doesn't live-reflow sibling rows mid-drag either, just
    // the dragged item's own feedback following the finger (below).
    final liveIndentPx = _dragging
        ? (block.indent * checklistIndentStepPx + _dragDx).clamp(
            0.0,
            maxChecklistIndent * checklistIndentStepPx,
          )
        : block.indent * checklistIndentStepPx;

    final handleIcon = Icon(
      Icons.drag_indicator,
      size: 18,
      color: widget.hintColor,
    );

    // A plain GestureDetector's PanGestureRecognizer reliably loses the
    // gesture arena to the ambient ListView's own vertical scroll
    // recognizer when nested inside one - Draggable instead uses the
    // MultiDragGestureRecognizer family (the same mechanism behind
    // Flutter's drag-and-drop widgets generally), which is specifically
    // built to win against an ambient Scrollable rather than compete with
    // it, so this is the one part of the row that reliably starts a drag
    // no matter where it sits in the note.
    final handle = Draggable<Object>(
      feedback: Material(
        elevation: 4,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              handleIcon,
              const SizedBox(width: 8),
              Icon(
                block.checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: widget.hintColor,
              ),
              const SizedBox(width: 8),
              Text(block.text.isEmpty ? 'List item' : block.text),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: handleIcon),
      onDragStarted: _onDragStarted,
      onDragUpdate: _onDragUpdate,
      onDragEnd: _onDragEnd,
      // No top offset needed now that the row centers its children (see
      // the Row below) - the old top: 14 was hand-tuned to compensate for
      // that previously being top-aligned instead.
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: handleIcon,
      ),
    );

    return Padding(
      key: widget.viewBlock.rowKey,
      padding: EdgeInsets.only(left: liveIndentPx),
      child: Row(
        // .start (top-aligned) left the checkbox visibly higher than its
        // text - the text sits inside its own Padding(vertical: 12) below,
        // so top-aligning the row put the checkbox at the very top of a
        // taller box than the text occupies, rather than level with it.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          handle,
          Checkbox(
            value: block.checked,
            onChanged: (_) => widget.onToggle(),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _tapToOffset(
                  textKey: _textKey,
                  globalPosition: details.globalPosition,
                  textStart: parsed.textStart,
                  onOffset: widget.onTapText,
                ),
                child: block.text.isEmpty
                    ? const SizedBox(height: 20, width: double.infinity)
                    : Text.rich(
                        key: _textKey,
                        TextSpan(
                          text: block.text,
                          style: TextStyle(
                            fontSize: 15,
                            color: block.checked
                                ? widget.hintColor
                                : widget.textColor,
                            decoration: block.checked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: widget.hintColor),
            onPressed: widget.onDelete,
            tooltip: 'Remove item (copies its text to the clipboard)',
          ),
        ],
      ),
    );
  }
}
