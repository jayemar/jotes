import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../services/widget_service.dart';

/// Shown only via main.dart's `configureMain()` entrypoint, when the user
/// drags a Single Note widget onto their home screen - Android launches
/// this instead of the normal app so they can pick which note it shows.
/// [widgetId] is null only if something went wrong reaching this screen at
/// all (see main.dart), which the empty-state message below covers.
class WidgetNotePickerScreen extends ConsumerWidget {
  final String? widgetId;

  const WidgetNotePickerScreen({super.key, required this.widgetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgetId = this.widgetId;
    final notesAsync = ref.watch(notesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a note')),
      body: widgetId == null
          ? const Center(child: Text('Could not configure this widget.'))
          : notesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading notes: $e')),
              data: (notes) => notes.isEmpty
                  ? const Center(child: Text('No notes yet.'))
                  : ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return ListTile(
                          title: Text(
                            note.title.isEmpty ? '(untitled)' : note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: note.body.isEmpty
                              ? null
                              : Text(
                                  note.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => _selectNote(widgetId, note),
                        );
                      },
                    ),
            ),
    );
  }

  Future<void> _selectNote(String widgetId, Note note) async {
    await HomeWidget.saveWidgetData<String>('note_id.$widgetId', note.id);
    await HomeWidget.saveWidgetData<String>(
      'note_data.$widgetId',
      jsonEncode(WidgetService.buildSingleNoteJson(note)),
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.jayemar.jotes.SingleNoteWidgetReceiver',
    );
    await HomeWidget.finishHomeWidgetConfigure();
  }
}
