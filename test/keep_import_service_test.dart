import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/services/keep_import_service.dart';

Uint8List _buildFixtureZip() {
  final archive = Archive();

  void addJson(String name, Map<String, dynamic> json) {
    final bytes = utf8.encode(jsonEncode(json));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addJson('Takeout/Keep/plain_note.json', {
    'title': 'Groceries',
    'textContent': 'Milk\nEggs',
    'color': 'BLUE',
    'isTrashed': false,
    'isArchived': false,
    'createdTimestampUsec': 1700000000000000,
    'userEditedTimestampUsec': 1700000100000000,
  });

  addJson('Takeout/Keep/checklist_note.json', {
    'title': '',
    'listContent': [
      {'text': 'Buy milk', 'isChecked': true},
      {'text': 'Buy eggs', 'isChecked': false},
    ],
    'color': 'GREEN',
    'createdTimestampUsec': 1700000000000000,
    'userEditedTimestampUsec': 1700000000000000,
  });

  addJson('Takeout/Keep/trashed_note.json', {
    'title': 'Old note',
    'textContent': 'should be skipped',
    'isTrashed': true,
  });

  addJson('Takeout/Keep/archived_note.json', {
    'title': 'Archived',
    'textContent': 'still imported',
    'color': 'DEFAULT',
    'isArchived': true,
  });

  addJson('Takeout/Keep/cerulean_note.json', {
    'title': 'Cerulean',
    'textContent': 'maps to blue',
    'color': 'CERULEAN',
  });

  addJson('Takeout/Keep/with_attachment.json', {
    'title': 'Has attachment',
    'textContent': 'body text',
    'attachments': [
      {'filePath': 'foo.jpg', 'mimetype': 'image/jpeg'},
    ],
  });
  archive.addFile(ArchiveFile('Takeout/Keep/foo.jpg', 3, [1, 2, 3]));
  archive.addFile(
    ArchiveFile(
      'Takeout/Keep/with_attachment.html',
      11,
      utf8.encode('<html></html>'),
    ),
  );

  // Deliberately malformed JSON.
  final malformed = utf8.encode('{not valid json');
  archive.addFile(
    ArchiveFile('Takeout/Keep/malformed.json', malformed.length, malformed),
  );

  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

void main() {
  test('parseZip imports, skips, and fails the expected notes', () {
    final result = KeepImportService.instance.parseZip(_buildFixtureZip());

    expect(result.imported, 5);
    expect(result.skipped, 1);
    expect(result.failed, 1);
  });

  test('plain note maps title, body, color, and timestamps', () {
    final result = KeepImportService.instance.parseZip(_buildFixtureZip());
    final note = result.notes.firstWhere((n) => n.title == 'Groceries');

    expect(note.body, 'Milk\nEggs');
    expect(note.colorIndex, 6); // BLUE
    expect(note.reminderAt, isNull);
    expect(
      note.created,
      DateTime.fromMicrosecondsSinceEpoch(1700000000000000),
    );
  });

  test('checklist note is rendered as [x]/[ ] text lines', () {
    final result = KeepImportService.instance.parseZip(_buildFixtureZip());
    final note = result.notes.firstWhere(
      (n) => n.body.contains('Buy milk'),
    );

    expect(note.body, '- [x] Buy milk\n- [ ] Buy eggs');
    expect(note.colorIndex, 4); // GREEN
  });

  test('archived notes import normally', () {
    final result = KeepImportService.instance.parseZip(_buildFixtureZip());
    expect(result.notes.any((n) => n.title == 'Archived'), isTrue);
  });

  test('CERULEAN falls back to the blue color slot', () {
    final result = KeepImportService.instance.parseZip(_buildFixtureZip());
    final note = result.notes.firstWhere((n) => n.title == 'Cerulean');
    expect(note.colorIndex, 6);
  });

  test('attachments are dropped without error, non-json files ignored', () {
    final result = KeepImportService.instance.parseZip(_buildFixtureZip());
    final note = result.notes.firstWhere((n) => n.title == 'Has attachment');
    expect(note.body, 'body text');
    // Only the 6 *.json fixtures should ever be considered; the .jpg/.html
    // siblings must not produce extra notes or parse failures.
    expect(result.imported + result.skipped + result.failed, 7);
  });
}
