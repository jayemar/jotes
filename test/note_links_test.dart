import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/widgets/note_links.dart';

void main() {
  group('parseLinks', () {
    test('plain text with no links returns a single plain segment', () {
      final segments = parseLinks('Just some text.');
      expect(segments, hasLength(1));
      expect(segments.single.text, 'Just some text.');
      expect(segments.single.isLink, isFalse);
    });

    test('a markdown link becomes a single link segment using its label', () {
      final segments = parseLinks('See [the docs](https://example.com/docs).');
      expect(segments.map((s) => s.text), [
        'See ',
        'the docs',
        '.',
      ]);
      expect(segments[1].isLink, isTrue);
      expect(segments[1].url, 'https://example.com/docs');
    });

    test('a markdown link with an empty label falls back to showing the '
        'url itself', () {
      final segments = parseLinks('[](https://example.com)');
      expect(segments.single.text, 'https://example.com');
      expect(segments.single.url, 'https://example.com');
    });

    test('a bare http(s) URL is detected as a link using itself as the '
        'display text', () {
      final segments = parseLinks('Visit https://example.com for more.');
      expect(segments.map((s) => s.text), [
        'Visit ',
        'https://example.com',
        ' for more.',
      ]);
      expect(segments[1].isLink, isTrue);
      expect(segments[1].url, 'https://example.com');
    });

    test('trailing sentence punctuation after a bare URL is not swallowed '
        'into the link', () {
      final segments = parseLinks('See https://example.com.');
      expect(segments.map((s) => s.text), [
        'See ',
        'https://example.com',
        '.',
      ]);
      expect(segments[1].url, 'https://example.com');
    });

    test('a URL already inside a markdown link is not also matched as a '
        'second, bare link', () {
      final segments = parseLinks('[here](https://example.com)');
      expect(segments, hasLength(1));
      expect(segments.single.url, 'https://example.com');
    });

    test('multiple bare URLs in the same text are each detected', () {
      final segments = parseLinks('https://a.example and https://b.example');
      final links = segments.where((s) => s.isLink).toList();
      expect(links.map((s) => s.url), ['https://a.example', 'https://b.example']);
    });

    test('a mix of a markdown link and a bare URL in the same text are '
        'both detected', () {
      final segments = parseLinks(
        '[Site](https://a.example) and also https://b.example',
      );
      final links = segments.where((s) => s.isLink).toList();
      expect(links, hasLength(2));
      expect(links[0].url, 'https://a.example');
      expect(links[0].text, 'Site');
      expect(links[1].url, 'https://b.example');
    });

    test('empty text returns no segments', () {
      expect(parseLinks(''), isEmpty);
    });
  });
}
