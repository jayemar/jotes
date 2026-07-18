import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';
import 'package:jotes/services/markdown_export_service.dart';
import 'package:jotes/services/markdown_import_service.dart';

Note _note({
  String? id,
  String title = 'Title',
  String body = 'Body',
}) {
  final now = DateTime.now();
  return Note(
    id: id ?? 'note-id-12345678',
    title: title,
    body: body,
    created: now,
    updated: now,
  );
}

void main() {
  group('MarkdownExportService.toMarkdown', () {
    test('a note with both title and body becomes a heading plus body', () {
      final md = MarkdownExportService.instance
          .toMarkdown(_note(title: 'Groceries', body: 'Milk\nEggs'));
      expect(md, '# Groceries\n\nMilk\nEggs');
    });

    test('a title-only note has no trailing blank body section', () {
      final md =
          MarkdownExportService.instance.toMarkdown(_note(title: 'Just a title', body: ''));
      expect(md, '# Just a title');
    });

    test('a body-only note (no title) has no heading', () {
      final md =
          MarkdownExportService.instance.toMarkdown(_note(title: '', body: 'Just body text'));
      expect(md, 'Just body text');
    });

    test('checklist syntax in the body passes through unchanged', () {
      final md = MarkdownExportService.instance.toMarkdown(
        _note(title: 'Todo', body: '- [x] Done\n- [ ] Not done'),
      );
      expect(md, '# Todo\n\n- [x] Done\n- [ ] Not done');
    });
  });

  group('MarkdownExportService.suggestedFilename', () {
    test('sanitizes filesystem-forbidden characters out of the title', () {
      final name = MarkdownExportService.instance
          .suggestedFilename(_note(title: 'a/b:c*d?e"f<g>h|i'));
      expect(name, 'abcdefghi');
    });

    test('collapses internal whitespace but keeps single spaces', () {
      final name = MarkdownExportService.instance
          .suggestedFilename(_note(title: 'a   b\tc'));
      expect(name, 'a b c');
    });

    test('falls back to an id-derived name when the title sanitizes to '
        'nothing', () {
      final name = MarkdownExportService.instance
          .suggestedFilename(_note(id: 'abcdefgh-1234', title: '///???'));
      expect(name, 'note-abcdefgh');
    });
  });

  group('MarkdownExportService.toZip', () {
    test('bundles one .md file per note with the expected content', () {
      final zipBytes = MarkdownExportService.instance.toZip([
        _note(id: '1', title: 'First', body: 'One'),
        _note(id: '2', title: 'Second', body: 'Two'),
      ]);

      final archive = ZipDecoder().decodeBytes(zipBytes);
      expect(archive.files, hasLength(2));

      final contents = {
        for (final f in archive.files) f.name: utf8.decode(f.content as List<int>),
      };
      expect(contents['First.md'], '# First\n\nOne');
      expect(contents['Second.md'], '# Second\n\nTwo');
    });

    test('disambiguates two notes that sanitize to the same filename', () {
      final zipBytes = MarkdownExportService.instance.toZip([
        _note(id: '1', title: 'Same', body: 'One'),
        _note(id: '2', title: 'Same', body: 'Two'),
      ]);

      final archive = ZipDecoder().decodeBytes(zipBytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, {'Same.md', 'Same (1).md'});
    });
  });

  test('a note exported to Markdown and re-imported round-trips its title '
      'and body unchanged', () {
    final original = _note(
      title: 'Round trip',
      body: 'Some text\n- [x] and a checklist item',
    );

    final md = MarkdownExportService.instance.toMarkdown(original);
    final result = MarkdownImportService.instance.parseFiles({
      'export.md': Uint8List.fromList(utf8.encode(md)),
    });

    expect(result.notes.single.title, original.title);
    expect(result.notes.single.body, original.body);
  });
}
