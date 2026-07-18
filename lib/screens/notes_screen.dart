import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../providers/appearance_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/theme_provider.dart';
import '../services/keep_import_service.dart';
import '../services/markdown_export_service.dart';
import '../services/markdown_import_service.dart';
import '../services/notification_service.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';
import 'sync_settings_screen.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final Set<String> _selectedIds = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _reminderChipRefreshTimer;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Existing notes may already have reminders that can never fire if
    // notifications are disabled - surface that here, not only reactively
    // when the user next tries to set one (note_editor_screen.dart).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkNotificationsEnabled());

    // NoteCard's reminder chip switches from green (upcoming) to red (past)
    // by comparing reminderAt to DateTime.now() on every build - correct,
    // but nothing otherwise triggers a rebuild as time passes with no data
    // change, so a fired reminder's chip visibly stays green until some
    // unrelated event (editing a note, a sync update) happens to rebuild
    // the grid. This timer's only job is to periodically force that
    // rebuild so the chip's own already-correct logic gets re-evaluated.
    _reminderChipRefreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reminderChipRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNotificationsEnabled() async {
    final enabled = await NotificationService.instance.notificationsEnabled();
    if (!mounted || enabled) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text(
          "Notifications are disabled for jotes, so reminders won't fire.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              NotificationService.instance.requestNotificationsAccess();
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: const Text('Fix'),
          ),
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  List<Note> _filterNotes(List<Note> notes) {
    if (_searchQuery.isEmpty) return notes;
    final q = _searchQuery.toLowerCase();
    return notes
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _deleteSelected(List<Note> notes) async {
    final notifier = ref.read(notesProvider.notifier);
    final selected = notes.where((n) => _selectedIds.contains(n.id)).toList();
    _clearSelection();
    for (final note in selected) {
      await notifier.delete(note);
    }
  }

  Future<void> _recolorSelected(List<Note> notes) async {
    final index = await showColorPickerSheet(context);
    if (index == null || !mounted) return;
    final notifier = ref.read(notesProvider.notifier);
    final selected = notes.where((n) => _selectedIds.contains(n.id)).toList();
    _clearSelection();
    for (final note in selected) {
      await notifier.addOrUpdate(note.copyWith(colorIndex: index));
    }
  }

  /// A single selected note is saved as a plain .md file directly; more
  /// than one is bundled into a zip (see MarkdownExportService.toZip) since
  /// there's no reliably cross-platform way to write multiple files to a
  /// chosen location in one picker interaction.
  Future<void> _exportSelectedToMarkdown(List<Note> notes) async {
    final selected = notes.where((n) => _selectedIds.contains(n.id)).toList();
    _clearSelection();
    if (selected.isEmpty) return;

    if (selected.length == 1) {
      final note = selected.single;
      await FilePicker.platform.saveFile(
        fileName:
            '${MarkdownExportService.instance.suggestedFilename(note)}.md',
        type: FileType.custom,
        allowedExtensions: ['md'],
        bytes: utf8.encode(MarkdownExportService.instance.toMarkdown(note)),
      );
      return;
    }

    final zipBytes = MarkdownExportService.instance.toZip(selected);
    await FilePicker.platform.saveFile(
      fileName: 'jotes-export.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: zipBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider);
    final notes = notesAsync.value ?? const <Note>[];
    // Watched here (not just from the drawer) so restoring a saved sync
    // session and starting the realtime subscription happens as soon as
    // the app launches, not only once the drawer is opened.
    ref.watch(syncProvider);

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _clearSelection();
      },
      child: _buildScaffold(context, notesAsync, notes),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AsyncValue<List<Note>> notesAsync,
    List<Note> notes,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.onSurfaceVariant;
    final searchFieldColor = noteColorFor(context, 0);
    final searchFieldTextColor =
        ThemeData.estimateBrightnessForColor(searchFieldColor) ==
                Brightness.dark
            ? Colors.white
            : Colors.black87;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colorScheme.surfaceContainerLow,
      drawer: _buildDrawer(context, notes),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: colorScheme.surfaceContainerHigh,
            surfaceTintColor: Colors.transparent,
            elevation: 1,
            shadowColor: colorScheme.shadow,
            leading: _selectionMode
                ? IconButton(
                    icon: Icon(Icons.close, color: iconColor),
                    tooltip: 'Cancel selection',
                    onPressed: _clearSelection,
                  )
                : IconButton(
                    icon: Icon(Icons.menu, color: iconColor),
                    tooltip: 'Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
            title: _selectionMode
                ? Text(
                    '${_selectedIds.length} selected',
                    style: TextStyle(
                      color: iconColor,
                      fontWeight: FontWeight.w400,
                      fontSize: 22,
                    ),
                  )
                : Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: searchFieldColor,
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: TextField(
                      key: const Key('search_field'),
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search notes',
                        hintStyle:
                            TextStyle(color: searchFieldTextColor.withAlpha(140)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: TextStyle(
                        color: searchFieldTextColor,
                        fontSize: 16,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
            actions: _selectionMode
                ? [
                    IconButton(
                      icon: Icon(Icons.palette_outlined, color: iconColor),
                      tooltip: 'Change color',
                      onPressed: () => _recolorSelected(notes),
                    ),
                    IconButton(
                      icon: Icon(Icons.folder_zip_outlined, color: iconColor),
                      tooltip: 'Export as Markdown',
                      onPressed: () => _exportSelectedToMarkdown(notes),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: iconColor),
                      tooltip: 'Delete',
                      onPressed: () => _deleteSelected(notes),
                    ),
                  ]
                : [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.clear, color: iconColor),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                  ],
          ),
          notesAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error loading notes: $e')),
            ),
            data: (notes) => _NoteGrid(
              notes: _filterNotes(notes),
              selectedIds: _selectedIds,
              selectionMode: _selectionMode,
              searching: _searchQuery.isNotEmpty,
              onToggleSelection: _toggleSelection,
              onOpen: (note) => _openNote(context, ref, note),
            ),
          ),
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: () => _openNote(context, ref, null),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildDrawer(BuildContext context, List<Note> notes) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final themeMode = ref.watch(themeModeProvider);
    final appearance = ref.watch(appearanceProvider);
    final syncState = ref.watch(syncProvider);

    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'J',
                    style: TextStyle(
                      fontFamily: 'Pacifico',
                      fontSize: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'jotes',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _drawerSectionLabel(context, 'Appearance'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Theme',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: DropdownButton<ThemeMode>(
                key: const Key('theme_dropdown'),
                value: themeMode,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text('Dark'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                ],
                onChanged: _setThemeMode,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Font',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: DropdownButton<AppFont>(
                key: const Key('font_dropdown'),
                value: appearance.font,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final font in AppFont.values)
                    DropdownMenuItem(
                      value: font,
                      child: Text(
                        font.label,
                        style: TextStyle(fontFamily: font.fontFamily),
                      ),
                    ),
                ],
                onChanged: _setFont,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Text size',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: DropdownButton<TextSizeOption>(
                key: const Key('text_size_dropdown'),
                value: appearance.textSize,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final size in TextSizeOption.values)
                    DropdownMenuItem(value: size, child: Text(size.label)),
                ],
                onChanged: _setTextSize,
              ),
            ),
            const Divider(height: 1),
            _drawerSectionLabel(context, 'Data'),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Import from Google Keep'),
              onTap: () {
                Navigator.pop(context);
                _importFromKeep(context, ref);
              },
            ),
            ListTile(
              key: const Key('import_markdown_item'),
              leading: const Icon(Icons.description_outlined),
              title: const Text('Import from Markdown'),
              onTap: () {
                Navigator.pop(context);
                _importFromMarkdown(context, ref);
              },
            ),
            ListTile(
              key: const Key('export_markdown_item'),
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('Export to Markdown'),
              subtitle: const Text('All notes, as a .zip'),
              onTap: () {
                Navigator.pop(context);
                _exportNotesToMarkdown(context, notes);
              },
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('sync_drawer_item'),
              leading: Icon(
                syncState.status == SyncStatus.connected
                    ? Icons.cloud_done
                    : Icons.cloud_outlined,
              ),
              title: const Text('Sync'),
              subtitle: Text(
                syncState.status == SyncStatus.connected
                    ? 'Connected as ${syncState.userEmail}'
                    : 'Not connected',
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SyncSettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _setThemeMode(ThemeMode? mode) {
    if (mode == null) return;
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
  }

  void _setFont(AppFont? font) {
    if (font == null) return;
    ref.read(appearanceProvider.notifier).setFont(font);
  }

  void _setTextSize(TextSizeOption? size) {
    if (size == null) return;
    ref.read(appearanceProvider.notifier).setTextSize(size);
  }

  void _openNote(BuildContext context, WidgetRef ref, Note? note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(existing: note),
      ),
    ).then((_) => ref.invalidate(notesProvider));
  }

  Future<void> _importFromKeep(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;

    final result = KeepImportService.instance.parseZip(bytes);
    await ref.read(notesProvider.notifier).addAllFromImport(result.notes);

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import complete'),
        content: Text(
          'Imported ${result.imported} note(s).\n'
          'Skipped ${result.skipped} trashed note(s).\n'
          'Failed to read ${result.failed} file(s).\n\n'
          'Checklists were converted to editable checkboxes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFromMarkdown(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md'],
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final filesByName = <String, Uint8List>{
      for (final file in picked.files)
        if (file.bytes != null) file.name: file.bytes!,
    };

    final result = MarkdownImportService.instance.parseFiles(filesByName);
    await ref.read(notesProvider.notifier).addAllFromImport(result.notes);

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import complete'),
        content: Text(
          'Imported ${result.imported} note(s).\n'
          'Failed to read ${result.failed} file(s).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportNotesToMarkdown(
    BuildContext context,
    List<Note> notes,
  ) async {
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No notes to export.')),
      );
      return;
    }

    final zipBytes = MarkdownExportService.instance.toZip(notes);
    await FilePicker.platform.saveFile(
      fileName: 'jotes-export.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: zipBytes,
    );
  }
}

class _NoteGrid extends StatelessWidget {
  final List<Note> notes;
  final Set<String> selectedIds;
  final bool selectionMode;
  final bool searching;
  final void Function(String id) onToggleSelection;
  final void Function(Note note) onOpen;

  const _NoteGrid({
    required this.notes,
    required this.selectedIds,
    required this.selectionMode,
    required this.searching,
    required this.onToggleSelection,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Text(
            searching
                ? 'No notes match your search.'
                : 'No notes yet.\nTap + to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final note = notes[i];
            return NoteCard(
              note: note,
              selected: selectedIds.contains(note.id),
              selectionMode: selectionMode,
              onTap: () => selectionMode
                  ? onToggleSelection(note.id)
                  : onOpen(note),
              onLongPress: () => onToggleSelection(note.id),
            );
          },
          childCount: notes.length,
        ),
      ),
    );
  }
}
