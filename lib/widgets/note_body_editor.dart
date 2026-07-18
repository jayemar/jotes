import 'package:flutter/material.dart';

// Standard GitHub-Flavored-Markdown task list syntax ("- [ ] text" /
// "- [x] text"), so a note's body stays plain, portable Markdown rather
// than a jotes-specific convention - it renders correctly as checklists in
// other markdown tools too.
final RegExp _checklistLinePattern = RegExp(r'^- \[( |x)\] (.*)$');

/// A block of a note body: either a run of plain text (possibly spanning
/// several `\n`-joined lines) or a single checklist item. Notes can mix
/// both freely, unlike Google Keep, where a note is entirely a checklist
/// or entirely plain text.
sealed class BodyBlock {}

class TextBodyBlock extends BodyBlock {
  final String text;
  TextBodyBlock(this.text);
}

class ChecklistBodyBlock extends BodyBlock {
  final bool checked;
  final String text;
  ChecklistBodyBlock({required this.checked, required this.text});
}

/// Parses a stored [Note.body] string into blocks. A line matching
/// `- [ ] text` / `- [x] text` becomes its own [ChecklistBodyBlock]; runs
/// of non-matching lines are merged into a single [TextBodyBlock]. This is
/// the same Markdown task-list convention KeepImportService writes for
/// imported Keep checklists, so previously-imported checklists become
/// interactive here for free.
List<BodyBlock> parseBody(String body) {
  final blocks = <BodyBlock>[];
  final textLines = <String>[];

  void flushText() {
    if (textLines.isNotEmpty) {
      blocks.add(TextBodyBlock(textLines.join('\n')));
      textLines.clear();
    }
  }

  for (final line in body.split('\n')) {
    final match = _checklistLinePattern.firstMatch(line);
    if (match != null) {
      flushText();
      blocks.add(ChecklistBodyBlock(
        checked: match.group(1) == 'x',
        text: match.group(2) ?? '',
      ));
    } else {
      textLines.add(line);
    }
  }
  flushText();

  return blocks;
}

/// Inverse of [parseBody].
String serializeBody(List<BodyBlock> blocks) {
  return blocks.map((b) {
    if (b is ChecklistBodyBlock) {
      return '- [${b.checked ? 'x' : ' '}] ${b.text}';
    }
    return (b as TextBodyBlock).text;
  }).join('\n');
}

class _EditableBlock {
  final bool isChecklist;
  bool checked;
  final TextEditingController controller;
  final FocusNode focusNode = FocusNode();

  _EditableBlock._({
    required this.isChecklist,
    required this.checked,
    required String text,
  }) : controller = TextEditingController(text: text);

  factory _EditableBlock.text(String text) =>
      _EditableBlock._(isChecklist: false, checked: false, text: text);

  factory _EditableBlock.checklist({
    required bool checked,
    required String text,
  }) =>
      _EditableBlock._(isChecklist: true, checked: checked, text: text);

  factory _EditableBlock.from(BodyBlock b) {
    if (b is ChecklistBodyBlock) {
      return _EditableBlock.checklist(checked: b.checked, text: b.text);
    }
    return _EditableBlock.text((b as TextBodyBlock).text);
  }

  BodyBlock toBodyBlock() => isChecklist
      ? ChecklistBodyBlock(checked: checked, text: controller.text)
      : TextBodyBlock(controller.text);

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

/// Editable note body supporting mixed plain-text and checklist blocks.
/// Call [addChecklistItem] via a [GlobalKey] to append a new item (e.g.
/// from a toolbar button).
class NoteBodyEditor extends StatefulWidget {
  final String initialBody;
  final Color textColor;
  final Color hintColor;
  final ValueChanged<String> onChanged;
  final bool autofocusFirst;

  const NoteBodyEditor({
    super.key,
    required this.initialBody,
    required this.textColor,
    required this.hintColor,
    required this.onChanged,
    this.autofocusFirst = false,
  });

  @override
  State<NoteBodyEditor> createState() => NoteBodyEditorState();
}

class NoteBodyEditorState extends State<NoteBodyEditor> {
  late List<_EditableBlock> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = parseBody(widget.initialBody).map(_EditableBlock.from).toList();
    if (_blocks.isEmpty) {
      _blocks.add(_EditableBlock.text(''));
    }
  }

  @override
  void dispose() {
    for (final b in _blocks) {
      b.dispose();
    }
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(
      serializeBody(_blocks.map((b) => b.toBodyBlock()).toList()),
    );
  }

  /// Appends a new empty checklist item and focuses it. Exposed for a
  /// parent toolbar button via `GlobalKey<NoteBodyEditorState>`.
  void addChecklistItem() {
    final newBlock = _EditableBlock.checklist(checked: false, text: '');
    setState(() => _blocks.add(newBlock));
    _notifyChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) newBlock.focusNode.requestFocus();
    });
  }

  void _insertChecklistItemAfter(_EditableBlock after, String initialText) {
    final index = _blocks.indexOf(after);
    final newBlock =
        _EditableBlock.checklist(checked: false, text: initialText);
    setState(() => _blocks.insert(index + 1, newBlock));
    _notifyChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) newBlock.focusNode.requestFocus();
    });
  }

  void _handleChecklistTextChanged(_EditableBlock block, String value) {
    // A multi-line TextField doesn't call onSubmitted for Enter, so detect
    // an inserted newline here and treat it as "start a new item below"
    // (matching Keep), rather than let it become a literal newline inside
    // one checklist item's stored text.
    if (value.contains('\n')) {
      final parts = value.split('\n');
      final currentText = parts.first;
      final remainder = parts.skip(1).join('\n');
      block.controller.value = TextEditingValue(
        text: currentText,
        selection: TextSelection.collapsed(offset: currentText.length),
      );
      _insertChecklistItemAfter(block, remainder);
      return;
    }
    _notifyChanged();
  }

  void _toggleChecked(_EditableBlock block) {
    setState(() => block.checked = !block.checked);
    _notifyChanged();
  }

  void _removeBlock(_EditableBlock block) {
    setState(() {
      _blocks.remove(block);
      if (_blocks.isEmpty) _blocks.add(_EditableBlock.text(''));
    });
    block.dispose();
    _notifyChanged();
  }

  void _focusEnd() {
    final last = _blocks.last;
    last.focusNode.requestFocus();
    last.controller.selection = TextSelection.collapsed(
      offset: last.controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focusEnd,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _blocks.length,
        itemBuilder: (context, i) {
          final block = _blocks[i];
          if (block.isChecklist) {
            return _ChecklistRow(
              key: ValueKey(block),
              block: block,
              textColor: widget.textColor,
              hintColor: widget.hintColor,
              onToggle: () => _toggleChecked(block),
              onChanged: (value) =>
                  _handleChecklistTextChanged(block, value),
              onDelete: () => _removeBlock(block),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: TextField(
              key: ValueKey(block),
              controller: block.controller,
              focusNode: block.focusNode,
              style: TextStyle(fontSize: 15, color: widget.textColor),
              decoration: InputDecoration(
                hintText: i == 0 ? 'Note' : null,
                hintStyle: TextStyle(color: widget.hintColor),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              autofocus: widget.autofocusFirst && i == 0,
              onChanged: (_) => _notifyChanged(),
            ),
          );
        },
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final _EditableBlock block;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final VoidCallback onDelete;

  const _ChecklistRow({
    super.key,
    required this.block,
    required this.textColor,
    required this.hintColor,
    required this.onToggle,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: block.checked,
          onChanged: (_) => onToggle(),
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: TextField(
            controller: block.controller,
            focusNode: block.focusNode,
            style: TextStyle(
              fontSize: 15,
              color: block.checked ? hintColor : textColor,
              decoration:
                  block.checked ? TextDecoration.lineThrough : null,
            ),
            decoration: InputDecoration(
              hintText: 'List item',
              hintStyle: TextStyle(color: hintColor),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            onChanged: onChanged,
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, size: 18, color: hintColor),
          onPressed: onDelete,
          tooltip: 'Remove item',
        ),
      ],
    );
  }
}
