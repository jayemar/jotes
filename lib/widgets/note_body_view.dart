import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

import 'note_body_editor.dart'
    show
        BodyBlock,
        BulletBodyBlock,
        ChecklistBodyBlock,
        NumberedBodyBlock,
        ParsedBlock,
        TextBodyBlock,
        checklistIndentStepPx,
        maxChecklistIndent,
        parseBodyWithOffsets;
import 'note_link_spans.dart';

/// How long a checked-off item stays put, still visibly showing its new
/// checked state, before actually sinking to the bottom of its checklist
/// run - see _ChecklistViewRowState._handleToggleTap. Long enough that the
/// tap's own result (checkbox filled in, text struck through) is clearly
/// visible before the item jumps away, matching the reasoning Keep's own
/// "check, pause, then sink" behavior already relies on; short enough not
/// to feel like a stuck tap.
const checklistToggleCommitDelay = Duration(milliseconds: 450);

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
  final Color linkColor;
  final ValueChanged<int> onEnterEditAt;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onDelete;
  final void Function(int fromIndex, int toIndex, int newIndent) onDragCommit;

  const NoteBodyView({
    super.key,
    required this.body,
    required this.textColor,
    required this.hintColor,
    required this.linkColor,
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
          if (segment.isChecklistRun) {
            return _buildChecklistRun(context, viewBlocks, segment);
          }
          final viewBlock = viewBlocks[segment.start];
          return switch (viewBlock.block) {
            BulletBodyBlock(:final text, :final indent) =>
              _buildListMarkerBlock(
                context,
                viewBlock,
                marker: '•',
                text: text,
                indent: indent,
              ),
            NumberedBodyBlock(:final number, :final text, :final indent) =>
              _buildListMarkerBlock(
                context,
                viewBlock,
                marker: '$number.',
                text: text,
                indent: indent,
              ),
            _ => _buildTextBlock(context, viewBlock),
          };
        },
      ),
    );
  }

  Widget _buildTextBlock(BuildContext context, ViewBlock viewBlock) {
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
                  children: buildLinkSpans(
                    text: text,
                    baseStyle: TextStyle(fontSize: 15, color: textColor),
                    linkColor: linkColor,
                    onTapLink: (url) => openLink(context, url),
                  ),
                ),
              ),
      ),
    );
  }

  /// Read-only row for a [BulletBodyBlock]/[NumberedBodyBlock] - a plain
  /// [marker] ("•" or "N.") followed by the item's text, tap-to-edit only
  /// (no checkbox/drag handle - those are checklist-specific, see
  /// _buildChecklistRun/_ChecklistViewRow).
  Widget _buildListMarkerBlock(
    BuildContext context,
    ViewBlock viewBlock, {
    required String marker,
    required String text,
    required int indent,
  }) {
    final parsed = viewBlock.parsed;
    final textKey = GlobalKey();
    return Padding(
      padding: EdgeInsets.only(
        left: indent * checklistIndentStepPx,
        top: 2,
        bottom: 2,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _tapToOffset(
          textKey: textKey,
          globalPosition: details.globalPosition,
          textStart: parsed.textStart,
          onOffset: onEnterEditAt,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // minWidth only, no maxWidth - a bullet ("•") is narrow enough
            // to need padding out to a consistent minimum, but a numbered
            // marker has no upper bound on digit count ("10.", "100.", ...)
            // and must never be squeezed into a fixed width, which would
            // wrap it onto multiple lines instead of clipping.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 18),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  marker,
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: text.isEmpty
                  ? const SizedBox(height: 20, width: double.infinity)
                  : Text.rich(
                      key: textKey,
                      TextSpan(
                        children: buildLinkSpans(
                          text: text,
                          baseStyle: TextStyle(fontSize: 15, color: textColor),
                          linkColor: linkColor,
                          onTapLink: (url) => openLink(context, url),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistRun(
    BuildContext context,
    List<ViewBlock> viewBlocks,
    RenderSegment segment,
  ) {
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
            linkColor: linkColor,
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
  final Color linkColor;
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
    required this.linkColor,
    required this.onToggle,
    required this.onDelete,
    required this.onDragEnd,
    required this.onTapText,
  });

  @override
  State<_ChecklistViewRow> createState() => _ChecklistViewRowState();
}

class _ChecklistViewRowState extends State<_ChecklistViewRow>
    with SingleTickerProviderStateMixin {
  // Non-zero only while a drag is actively in progress, so the row can
  // live-preview its new indent as soon as it's dragged, before the drag
  // ends and the change actually commits.
  bool _dragging = false;
  double _dragDx = 0;
  double _dragDy = 0;
  final GlobalKey _textKey = GlobalKey();

  // The checked state actually shown while a toggle is pending commit (see
  // _handleToggleTap) - null once there's nothing pending, meaning the
  // real widget.viewBlock.block.checked is shown directly. Overriding the
  // *display* rather than committing immediately is what buys the pause
  // before the item sinks to the bottom of its run: the checkbox/text
  // already show the new state, but the actual reorder (and the jump that
  // comes with it) waits for [_pendingCommitTimer].
  bool? _displayCheckedOverride;
  Timer? _pendingCommitTimer;

  // A brief scale pulse on tap, independent of the commit delay above -
  // concrete, immediate confirmation that this exact checkbox registered
  // the tap, which is the other half of what made a fast sink-to-bottom
  // feel uncertain (was that even the row I meant to tap?).
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pulseScale = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 1),
      ],
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    // Loses whatever toggle is still pending rather than force-committing
    // it - same tradeoff note_editor_screen.dart's own autosave timer
    // already makes on dispose, and for the same reason: this row is gone
    // (note closed, or view mode torn down) well before the short delay
    // above would elapse in any normal tap, so there's nothing meaningful
    // left to flush.
    _pendingCommitTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// The checked state to actually display - the real, current value
  /// unless a not-yet-committed toggle (see [_displayCheckedOverride])
  /// says otherwise.
  bool _displayChecked(ChecklistBodyBlock block) =>
      _displayCheckedOverride ?? block.checked;

  /// Handles a tap on this row's checkbox - see the class-level doc
  /// comments on [_displayCheckedOverride]/[_pulseController] for the two
  /// things this does: an immediate visual pulse + display flip (so the
  /// tap itself is unmistakable), and a delayed commit of the real toggle
  /// (so the resulting sink-to-bottom reorder doesn't happen until well
  /// after that's visible). Tapping again before the delay elapses cancels
  /// whatever was pending - if that lands back on the real, current
  /// checked state, there's nothing left to commit at all, the same as if
  /// neither tap had happened; otherwise a fresh delay starts for the new
  /// (still-uncommitted) state. This mirrors toggleLineMarker/toggleInline
  /// Marker's own "the latest state wins" reasoning elsewhere in this
  /// editor, just applied to a debounced commit instead of an immediate
  /// one.
  void _handleToggleTap() {
    final block = widget.viewBlock.block as ChecklistBodyBlock;
    _pulseController.forward(from: 0);
    _pendingCommitTimer?.cancel();

    final newDisplay = !_displayChecked(block);
    if (newDisplay == block.checked) {
      setState(() => _displayCheckedOverride = null);
      return;
    }

    setState(() => _displayCheckedOverride = newDisplay);
    _pendingCommitTimer = Timer(checklistToggleCommitDelay, () {
      if (!mounted) return;
      // Cleared *before* the real toggle commits, not after - once
      // widget.onToggle() below runs, this row's key may end up matching a
      // completely different block after the resulting reorder (checking
      // sinks the item to the bottom of its run), and that block's own
      // ground-truth checked state - not this now-stale override - is
      // what belongs on display then.
      setState(() => _displayCheckedOverride = null);
      widget.onToggle();
    });
  }

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

    final displayChecked = _displayChecked(block);

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
          ScaleTransition(
            scale: _pulseScale,
            child: Checkbox(
              value: displayChecked,
              onChanged: (_) => _handleToggleTap(),
              visualDensity: VisualDensity.compact,
            ),
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
                          children: buildLinkSpans(
                            text: block.text,
                            baseStyle: TextStyle(
                              fontSize: 15,
                              color: displayChecked
                                  ? widget.hintColor
                                  : widget.textColor,
                              decoration: displayChecked
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            linkColor: widget.linkColor,
                            onTapLink: (url) => openLink(context, url),
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
