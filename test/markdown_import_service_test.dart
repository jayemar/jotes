import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/services/markdown_import_service.dart';

Uint8List _bytes(String content) => Uint8List.fromList(utf8.encode(content));

void main() {
  group('MarkdownImportService', () {
    test('a leading "# Heading" line becomes the title, rest becomes the body',
        () {
      final result = MarkdownImportService.instance.parseFiles({
        'groceries.md': _bytes('# Groceries\n\nMilk\nEggs'),
      });

      expect(result.imported, 1);
      expect(result.failed, 0);
      expect(result.notes.single.title, 'Groceries');
      expect(result.notes.single.body, 'Milk\nEggs');
    });

    test('a file with no heading falls back to a title derived from the '
        'filename, and the whole content becomes the body', () {
      final result = MarkdownImportService.instance.parseFiles({
        'shopping list.md': _bytes('Milk\nEggs'),
      });

      expect(result.notes.single.title, 'shopping list');
      expect(result.notes.single.body, 'Milk\nEggs');
    });

    test('checklist syntax in the body passes through unchanged, since it '
        'already matches jotes\' own note body format', () {
      final result = MarkdownImportService.instance.parseFiles({
        'todo.md': _bytes('# Todo\n\n- [x] Done thing\n- [ ] Not done'),
      });

      expect(result.notes.single.body, '- [x] Done thing\n- [ ] Not done');
    });

    test('blank lines before the heading are skipped, not treated as body',
        () {
      final result = MarkdownImportService.instance.parseFiles({
        'note.md': _bytes('\n\n# Title\n\nBody text'),
      });

      expect(result.notes.single.title, 'Title');
      expect(result.notes.single.body, 'Body text');
    });

    test('multiple files each become their own note', () {
      final result = MarkdownImportService.instance.parseFiles({
        'a.md': _bytes('# A\n\nFirst'),
        'b.md': _bytes('# B\n\nSecond'),
      });

      expect(result.imported, 2);
      expect(result.notes.map((n) => n.title), containsAll(['A', 'B']));
    });

    test('a file that fails to decode is counted as failed without '
        'aborting the rest of the batch', () {
      final result = MarkdownImportService.instance.parseFiles({
        'good.md': _bytes('# Good\n\nFine'),
        'bad.md': Uint8List.fromList([0xFF, 0xFE, 0xFD]),
      });

      expect(result.imported, 1);
      expect(result.failed, 1);
      expect(result.notes.single.title, 'Good');
    });

    test('a heading-only file imports with an empty body', () {
      final result = MarkdownImportService.instance.parseFiles({
        'empty.md': _bytes('# Just a title'),
      });

      expect(result.notes.single.title, 'Just a title');
      expect(result.notes.single.body, isEmpty);
    });
  });
}
