import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/notes_provider.dart';

/// Opens a searchable dialog for picking a note to link to - the only way
/// a user actually creates a note-to-note link (see note_body_editor.dart's
/// insertNoteLink/detectNoteLinkTrigger and note_editor_screen.dart's
/// insertNoteLink toolbar button), since typing another note's raw id by
/// hand isn't reasonable. Returns the picked [Note], or null if the dialog
/// was dismissed without picking one.
Future<Note?> pickNoteToLink(BuildContext context, {String? excludeNoteId}) {
  return showDialog<Note>(
    context: context,
    builder: (_) => NoteLinkPickerDialog(excludeNoteId: excludeNoteId),
  );
}

class NoteLinkPickerDialog extends ConsumerStatefulWidget {
  final String? excludeNoteId;

  const NoteLinkPickerDialog({super.key, this.excludeNoteId});

  @override
  ConsumerState<NoteLinkPickerDialog> createState() =>
      _NoteLinkPickerDialogState();
}

class _NoteLinkPickerDialogState extends ConsumerState<NoteLinkPickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Note> _filtered(List<Note> notes) {
    final query = _query.trim().toLowerCase();
    final candidates = notes.where((n) => n.id != widget.excludeNoteId);
    final matching = query.isEmpty
        ? candidates
        : candidates.where((n) => n.title.toLowerCase().contains(query));
    final result = matching.toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider).value ?? const <Note>[];
    final results = _filtered(notes);

    return Dialog(
      child: SizedBox(
        // Fixed, not just a max - the search field sits right above the
        // results area (see below), so if the dialog were left to shrink
        // to however many results currently match (as a Flexible/
        // shrinkWrap ListView would), it would resize on every keystroke;
        // since Dialog centers itself on screen, that resize visibly
        // shifts the search field's own position rather than leaving it
        // pinned in place while just the results below it change.
        height: 480,
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Link to note',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('note_link_picker_search'),
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          notes.length <= 1
                              ? 'No other notes yet'
                              : 'No matching notes',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final note = results[index];
                          return ListTile(
                            key: Key('note_link_picker_result_${note.id}'),
                            title: Text(
                              note.title.isEmpty ? 'Untitled' : note.title,
                            ),
                            subtitle: note.body.isEmpty
                                ? null
                                : Text(
                                    note.body,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => Navigator.pop(context, note),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
