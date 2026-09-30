import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/widgets/note_inline_format.dart';

void main() {
  group('parseInlineFormatting', () {
    test('plain text with no formatting returns a single plain segment', () {
      final segments = parseInlineFormatting('Just some text.');
      expect(segments, hasLength(1));
      expect(segments.single.text, 'Just some text.');
      expect(segments.single.formats, isEmpty);
    });

    test('bold text becomes a single bold segment, markers stripped', () {
      final segments = parseInlineFormatting('This is **bold** text.');
      expect(segments.map((s) => s.text), ['This is ', 'bold', ' text.']);
      expect(segments[1].formats, {InlineFormat.bold});
    });

    test('italic text becomes a single italic segment, markers stripped', () {
      final segments = parseInlineFormatting('This is *italic* text.');
      expect(segments.map((s) => s.text), ['This is ', 'italic', ' text.']);
      expect(segments[1].formats, {InlineFormat.italic});
    });

    test('strikethrough text becomes a single strikethrough segment', () {
      final segments = parseInlineFormatting('This is ~~wrong~~ text.');
      expect(segments.map((s) => s.text), ['This is ', 'wrong', ' text.']);
      expect(segments[1].formats, {InlineFormat.strikethrough});
    });

    test('code text becomes a single code segment', () {
      final segments = parseInlineFormatting('Run `flutter test` now.');
      expect(segments.map((s) => s.text), ['Run ', 'flutter test', ' now.']);
      expect(segments[1].formats, {InlineFormat.code});
    });

    test('a bold run is not instead read as two adjacent italic runs', () {
      final segments = parseInlineFormatting('**bold**');
      expect(segments, hasLength(1));
      expect(segments.single.text, 'bold');
      expect(segments.single.formats, {InlineFormat.bold});
    });

    test('bold and italic can both appear in the same text, separately', () {
      final segments = parseInlineFormatting('**bold** and *italic*');
      expect(segments.map((s) => s.text), ['bold', ' and ', 'italic']);
      expect(segments[0].formats, {InlineFormat.bold});
      expect(segments[2].formats, {InlineFormat.italic});
    });

    test('underscore-based emphasis is left alone (not treated as bold or '
        'italic), so ordinary underscores in text are not misread', () {
      final segments = parseInlineFormatting('a snake_case_name and __not__');
      expect(segments, hasLength(1));
      expect(segments.single.text, 'a snake_case_name and __not__');
      expect(segments.single.formats, isEmpty);
    });

    test('an unterminated marker with no closing pair is left as plain '
        'text, not treated as formatting', () {
      final segments = parseInlineFormatting('This has a stray * character');
      expect(segments, hasLength(1));
      expect(segments.single.formats, isEmpty);
    });
  });
}
