import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/note.dart';

class MarkdownImportResult {
  final List<Note> notes;
  final int failed;

  const MarkdownImportResult({required this.notes, required this.failed});

  int get imported => notes.length;
}

/// Parses one or more picked .md files into jotes [Note]s. Pure parsing
/// only - no DB/notification/sync side effects, so callers control
/// batching (mirrors KeepImportService).
///
/// One file becomes one note, the inverse of MarkdownExportService: a
/// leading "# Heading" line becomes the title (matching what export
/// produces), an optional "Reminder: `<ISO8601>`" line right after it (or
/// as the very first content line, if there's no heading) becomes
/// [Note.reminderAt], and everything else becomes the body untouched -
/// note bodies already use GitHub-Flavored-Markdown checklist syntax (see
/// note_body_editor.dart), so no conversion is needed either direction.
class MarkdownImportService {
  static final MarkdownImportService instance = MarkdownImportService._();

  MarkdownImportService._();

  final Uuid _uuid = const Uuid();

  // Matches exactly what MarkdownExportService.toMarkdown writes; a line
  // that doesn't match just becomes part of the body like any other line,
  // no crash or data loss either way.
  static final RegExp _reminderLinePattern = RegExp(r'^Reminder:\s*(.+)$');

  /// [filesByName] maps each picked file's display name (used to derive a
  /// fallback title when there's no heading) to its raw bytes.
  MarkdownImportResult parseFiles(Map<String, Uint8List> filesByName) {
    final notes = <Note>[];
    var failed = 0;

    for (final entry in filesByName.entries) {
      try {
        notes.add(_noteFromMarkdown(entry.key, utf8.decode(entry.value)));
      } catch (_) {
        failed++;
      }
    }

    return MarkdownImportResult(notes: notes, failed: failed);
  }

  Note _noteFromMarkdown(String filename, String content) {
    final now = DateTime.now();
    final lines = content.split('\n');

    var i = 0;
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }

    String title;
    int bodyStartIndex;
    if (i < lines.length && lines[i].trimLeft().startsWith('# ')) {
      title = lines[i].trimLeft().substring(2).trim();
      bodyStartIndex = i + 1;
    } else {
      title = _titleFromFilename(filename);
      bodyStartIndex = 0;
    }

    // Look for a "Reminder: <ISO8601>" line right after the heading (or at
    // the very start, if there was none) - tolerating a blank line before
    // it, though toMarkdown never actually puts one there. A line that
    // doesn't match, or a date that fails to parse, is left alone to
    // become part of the body instead of being silently dropped.
    var reminderLineIndex = bodyStartIndex;
    while (reminderLineIndex < lines.length &&
        lines[reminderLineIndex].trim().isEmpty) {
      reminderLineIndex++;
    }
    DateTime? reminderAt;
    if (reminderLineIndex < lines.length) {
      final match = _reminderLinePattern.firstMatch(lines[reminderLineIndex]);
      if (match != null) {
        final parsed = DateTime.tryParse(match.group(1)!.trim());
        if (parsed != null) {
          reminderAt = parsed.toLocal();
          bodyStartIndex = reminderLineIndex + 1;
        }
      }
    }

    final body = lines.skip(bodyStartIndex).join('\n').trim();

    return Note(
      id: _uuid.v4(),
      title: title,
      body: body,
      colorIndex: 0,
      reminderAt: reminderAt,
      created: now,
      updated: now,
    );
  }

  String _titleFromFilename(String filename) {
    final base = filename.split('/').last;
    return base.toLowerCase().endsWith('.md')
        ? base.substring(0, base.length - 3)
        : base;
  }
}
