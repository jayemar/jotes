import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';

class KeepImportResult {
  final List<Note> notes;
  final int skipped;
  final int failed;

  const KeepImportResult({
    required this.notes,
    required this.skipped,
    required this.failed,
  });

  int get imported => notes.length;
}

const Map<String, int> _keepColorMap = {
  'DEFAULT': 0,
  'RED': 1,
  'ORANGE': 2,
  'YELLOW': 3,
  'GREEN': 4,
  'TEAL': 5,
  'BLUE': 6,
  'CERULEAN': 6, // no matching slot in kNoteColors, closest hue
  'PURPLE': 7,
  'PINK': 8,
  'BROWN': 9,
  'GRAY': 0, // no matching slot in kNoteColors, falls back to default
};

/// Parses a Google Takeout export zip into jotes [Note]s. Pure parsing only
/// — no DB/notification/sync side effects, so callers control batching.
class KeepImportService {
  static final KeepImportService instance = KeepImportService._();

  KeepImportService._();

  final Uuid _uuid = const Uuid();

  KeepImportResult parseZip(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final notes = <Note>[];
    var skipped = 0;
    var failed = 0;

    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (!file.name.toLowerCase().endsWith('.json')) continue;

      try {
        final json =
            jsonDecode(utf8.decode(file.content)) as Map<String, dynamic>;

        if (json['isTrashed'] == true) {
          skipped++;
          continue;
        }

        notes.add(_noteFromKeepJson(json));
      } catch (_) {
        failed++;
      }
    }

    return KeepImportResult(notes: notes, skipped: skipped, failed: failed);
  }

  Note _noteFromKeepJson(Map<String, dynamic> json) {
    final created = _parseUsec(json['createdTimestampUsec']) ?? DateTime.now();
    final updated = _parseUsec(json['userEditedTimestampUsec']) ?? created;

    return Note(
      id: _uuid.v4(),
      title: (json['title'] as String?) ?? '',
      body: _bodyFromKeepJson(json),
      colorIndex: _colorIndexFromKeep(json['color'] as String?),
      created: created,
      updated: updated,
    );
  }

  String _bodyFromKeepJson(Map<String, dynamic> json) {
    final listContent = json['listContent'] as List<dynamic>?;
    if (listContent != null && listContent.isNotEmpty) {
      return listContent.map((item) {
        final entry = item as Map<String, dynamic>;
        final text = (entry['text'] as String?) ?? '';
        final checked = entry['isChecked'] == true;
        return checked ? '- [x] $text' : '- [ ] $text';
      }).join('\n');
    }
    return (json['textContent'] as String?) ?? '';
  }

  int _colorIndexFromKeep(String? keepColor) {
    if (keepColor == null) return 0;
    return _keepColorMap[keepColor] ?? 0;
  }

  DateTime? _parseUsec(dynamic value) {
    if (value == null) return null;
    final usec = int.tryParse(value.toString());
    if (usec == null) return null;
    return DateTime.fromMicrosecondsSinceEpoch(usec);
  }
}
