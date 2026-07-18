import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/note.dart';

/// Formats notes as standalone Markdown files. Since note bodies already
/// use GitHub-Flavored-Markdown checklist syntax (see
/// note_body_editor.dart), this is just a title heading followed by the
/// body as-is - the inverse of MarkdownImportService, no conversion
/// needed either direction.
class MarkdownExportService {
  static final MarkdownExportService instance = MarkdownExportService._();

  MarkdownExportService._();

  String toMarkdown(Note note) {
    final title = note.title.trim();
    final body = note.body.trim();
    if (title.isEmpty) return body;
    if (body.isEmpty) return '# $title';
    return '# $title\n\n$body';
  }

  /// A filesystem-safe filename (no extension) derived from the note's
  /// title, falling back to a short id fragment if the title is empty or
  /// sanitizes down to nothing (e.g. a title that's only punctuation).
  String suggestedFilename(Note note) {
    final sanitized = note.title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isNotEmpty) return sanitized;
    return 'note-${note.id.substring(0, 8)}';
  }

  /// Bundles multiple notes into one zip of individual .md files, for
  /// exporting more than one at once (multi-select, or all notes) without
  /// needing per-platform directory-picking support, which isn't reliably
  /// available on web - the same reasoning as KeepImportService's
  /// zip-only import, just in reverse.
  Uint8List toZip(List<Note> notes) {
    final archive = Archive();
    final usedNames = <String, int>{};

    for (final note in notes) {
      var name = suggestedFilename(note);
      final count = usedNames[name] ?? 0;
      usedNames[name] = count + 1;
      if (count > 0) name = '$name ($count)';

      final content = utf8.encode(toMarkdown(note));
      archive.addFile(ArchiveFile('$name.md', content.length, content));
    }

    return ZipEncoder().encodeBytes(archive);
  }
}
