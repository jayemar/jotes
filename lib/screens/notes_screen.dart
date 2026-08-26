import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../providers/app_info_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/notes_view_provider.dart';
import '../providers/sync_provider.dart';
import '../services/autostart_service.dart';
import '../services/keep_import_service.dart';
import '../services/markdown_export_service.dart';
import '../services/markdown_import_service.dart';
import '../services/notification_service.dart';
import '../theme/app_text_styles.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/note_card.dart';
import '../widgets/settings_labels.dart';
import 'note_editor_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';
import 'sync_settings_screen.dart';

/// Icon for the search field's reminder-visibility button, reflecting the
/// current NoteReminderFilter - "visibility" for [NoteReminderFilter.all]
/// (everything's visible), an eye-off for [withoutReminders] (reminder
/// notes specifically hidden from view), and an alarm for [withReminders]
/// (only reminder notes shown).
IconData _reminderVisibilityIcon(NoteReminderFilter filter) => switch (filter) {
  NoteReminderFilter.all => Icons.visibility_outlined,
  NoteReminderFilter.withoutReminders => Icons.visibility_off_outlined,
  NoteReminderFilter.withReminders => Icons.alarm,
};

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

  /// Notes currently playing their fade/shrink-out exit animation (see
  /// _RemovableNoteCard) - still present in notesProvider's own list (the
  /// real delete is deferred to _finishDelete, once each card's own
  /// animation completes), just visually on their way out. A confirmation
  /// that the deletion actually took place, not just a instantaneous
  /// disappearance - see _deleteSelected's own doc comment.
  final Set<String> _pendingDeleteIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Existing notes may already have reminders that can never fire if
    // notifications are disabled - surface that here, not only reactively
    // when the user next tries to set one (note_editor_screen.dart).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkNotificationsEnabled(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkAutostartSettings(),
    );

    // NoteCard's reminder chip switches from green (upcoming) to red (past)
    // by comparing reminderAt to DateTime.now() on every build - correct,
    // but nothing otherwise triggers a rebuild as time passes with no data
    // change, so a fired reminder's chip visibly stays green until some
    // unrelated event (editing a note, a sync update) happens to rebuild
    // the grid. This timer's only job is to periodically force that
    // rebuild so the chip's own already-correct logic gets re-evaluated.
    _reminderChipRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) {
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

  static const _autostartBannerDismissedPrefsKey = 'autostart_banner_dismissed';

  /// Unlike _checkNotificationsEnabled, there's no API to detect whether
  /// autostart is actually blocking this app - only whether this device's
  /// manufacturer has that concept at all (see AutostartService) - so
  /// re-showing this on every launch regardless of what the user already
  /// did about it would just be nagging. Shown once per install unless
  /// dismissed.
  Future<void> _checkAutostartSettings() async {
    final isRestrictive = await AutostartService.instance
        .isKnownRestrictiveManufacturer();
    if (!isRestrictive) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_autostartBannerDismissedPrefsKey) ?? false) return;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text(
          'Your device may block reminders from firing in the background '
          'unless jotes is allowed to auto-start.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await AutostartService.instance.openAutostartSettings();
              await prefs.setBool(_autostartBannerDismissedPrefsKey, true);
              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              }
            },
            child: const Text('Open settings'),
          ),
          TextButton(
            onPressed: () async {
              await prefs.setBool(_autostartBannerDismissedPrefsKey, true);
              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              }
            },
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
        .where(
          (n) =>
              n.title.toLowerCase().contains(q) ||
              n.body.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Popup anchored right next to whichever widget triggered it - shared
  /// by the Filter/Layout/Sort pickers below, all reached from a small
  /// icon (the search field's reminder-visibility button, or an item in
  /// the overflow menu), where a bottom sheet rising from the bottom of
  /// the screen felt disproportionate to a handful of options.
  /// [anchorContext] should be the BuildContext of the specific tapped
  /// widget, so the popup lands beside it rather than at some fixed
  /// screen position.
  Future<T?> _selectOptionAt<T>({
    required BuildContext anchorContext,
    required List<T> options,
    required T current,
    required String Function(T) label,
    required String Function(T) keySuffix,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = anchorContext.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    return showMenu<T>(
      context: context,
      position: position,
      items: [
        for (final option in options)
          PopupMenuItem<T>(
            key: Key('notes_view_option_${keySuffix(option)}'),
            value: option,
            child: Row(
              children: [
                Expanded(child: Text(label(option))),
                if (option == current) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _pickReminderFilter(BuildContext anchorContext) async {
    final current = ref.read(notesViewProvider).filter;
    final selected = await _selectOptionAt<NoteReminderFilter>(
      anchorContext: anchorContext,
      options: NoteReminderFilter.values,
      current: current,
      label: (f) => f.label,
      keySuffix: (f) => f.name,
    );
    if (selected == null) return;
    await ref.read(notesViewProvider.notifier).setFilter(selected);
  }

  Future<void> _pickLayout(BuildContext anchorContext) async {
    final current = ref.read(notesViewProvider).layout;
    final selected = await _selectOptionAt<NoteLayout>(
      anchorContext: anchorContext,
      options: NoteLayout.values,
      current: current,
      label: (l) => l.label,
      keySuffix: (l) => l.name,
    );
    if (selected == null) return;
    await ref.read(notesViewProvider.notifier).setLayout(selected);
  }

  Future<void> _pickSortOrder(BuildContext anchorContext) async {
    final current = ref.read(notesViewProvider).sortOrder;
    final selected = await _selectOptionAt<NoteSortOrder>(
      anchorContext: anchorContext,
      options: NoteSortOrder.values,
      current: current,
      label: (s) => s.label,
      keySuffix: (s) => s.name,
    );
    if (selected == null) return;
    await ref.read(notesViewProvider.notifier).setSortOrder(selected);
  }

  /// Marks the selected notes for removal rather than deleting them
  /// immediately - each one's own _RemovableNoteCard plays a fade/shrink-out
  /// animation first (with the rest of the grid/list reflowing around it as
  /// it shrinks away), and only calls back to actually delete it (see
  /// _finishDelete) once that animation finishes. A visual confirmation
  /// that the deletion took place, rather than notes just instantaneously
  /// vanishing with the remaining ones silently snapping into new
  /// positions.
  void _deleteSelected(List<Note> notes) {
    final selectedIds = notes
        .where((n) => _selectedIds.contains(n.id))
        .map((n) => n.id)
        .toSet();
    _clearSelection();
    setState(() => _pendingDeleteIds.addAll(selectedIds));
  }

  /// Called once [note]'s own exit animation completes - see
  /// _deleteSelected's own doc comment for why the real delete waits until
  /// here instead of happening up front.
  Future<void> _finishDelete(Note note) async {
    await ref.read(notesProvider.notifier).delete(note);
    if (mounted) setState(() => _pendingDeleteIds.remove(note.id));
  }

  Future<void> _recolorSelected(
    BuildContext anchorContext,
    List<Note> notes,
  ) async {
    final index = await showColorPickerSheet(anchorContext);
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
    final syncState = ref.watch(syncProvider);

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _clearSelection();
      },
      child: _buildScaffold(context, notesAsync, notes, syncState),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AsyncValue<List<Note>> notesAsync,
    List<Note> notes,
    SyncState syncState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.onSurfaceVariant;
    final viewState = ref.watch(notesViewProvider);
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
      body: RefreshIndicator(
        key: const Key('notes_refresh_indicator'),
        // Same reconciliation as the "Sync now" button in Sync settings -
        // a pull-down gesture is the more discoverable, mobile-browser-
        // style way to ask for the same thing, without leaving this
        // screen. A no-op (but still a valid, harmless refresh gesture)
        // while not connected - see SyncNotifier.resync.
        onRefresh: () => ref.read(syncProvider.notifier).resync(),
        child: CustomScrollView(
          // Without this, a note list short enough to not fill the
          // viewport has nothing to overscroll, and the pull gesture
          // never registers at all - RefreshIndicator needs the
          // scrollable to always be scrollable, not just when its content
          // happens to overflow.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: colorScheme.surfaceContainerHigh,
              surfaceTintColor: Colors.transparent,
              elevation: 1,
              shadowColor: colorScheme.shadow,
              // AppBar's own defaults (56 leadingWidth, 16 titleSpacing on
              // both sides of the title) leave a lot of dead space around
              // the hamburger icon and the search field's rounded
              // container - tightening both hands that width back to the
              // search field itself, which is what actually benefits from
              // it (see the Expanded TextField inside the title container
              // below).
              leadingWidth: 48,
              titleSpacing: 4,
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
                      alignment: Alignment.center,
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      decoration: BoxDecoration(
                        color: searchFieldColor,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('search_field'),
                              controller: _searchCtrl,
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                hintText: 'Search notes',
                                hintStyle: TextStyle(
                                  color: searchFieldTextColor.withAlpha(140),
                                ),
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                              style: TextStyle(
                                color: searchFieldTextColor,
                                fontSize: 16,
                              ),
                              onChanged: (v) =>
                                  setState(() => _searchQuery = v),
                            ),
                          ),
                          // Quick access to the same reminder filter as the
                          // overflow menu's own "Filter" option - right in
                          // the search field, since "which notes am I even
                          // looking at" is a more immediate question than
                          // the overflow menu's other two options (layout,
                          // sort), which don't change *which* notes show.
                          Tooltip(
                            message: viewState.filter.label,
                            child: Builder(
                              builder: (iconContext) => InkWell(
                                key: const Key('reminder_visibility_button'),
                                customBorder: const CircleBorder(),
                                onTap: () => _pickReminderFilter(iconContext),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    _reminderVisibilityIcon(viewState.filter),
                                    color: searchFieldTextColor,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              actions: _selectionMode
                  ? [
                      Builder(
                        builder: (paletteContext) => IconButton(
                          icon: Icon(Icons.palette_outlined, color: iconColor),
                          tooltip: 'Change color',
                          onPressed: () =>
                              _recolorSelected(paletteContext, notes),
                        ),
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
                      Tooltip(
                        message: syncState.status == SyncStatus.connected
                            ? 'Sync connected'
                            : 'Sync not connected',
                        child: InkWell(
                          key: const Key('sync_indicator_button'),
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SyncSettingsScreen(),
                            ),
                          ),
                          child: Padding(
                            // Was all(12) plus an extra 6px wrapper beyond
                            // that - more dead space around a 10px dot than
                            // this touch target needs, at the search
                            // field's expense.
                            padding: const EdgeInsets.all(8),
                            child: Container(
                              key: const Key('sync_indicator'),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: syncState.status == SyncStatus.connected
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Builder(
                        builder: (menuButtonContext) => PopupMenuButton<String>(
                          key: const Key('notes_view_menu'),
                          // Was the default EdgeInsets.all(8) - tightened
                          // to match the sync indicator's own padding just
                          // to its left (see sync_indicator_button above).
                          padding: const EdgeInsets.all(6),
                          icon: Icon(Icons.more_vert, color: iconColor),
                          tooltip: 'View options',
                          onSelected: (value) {
                            switch (value) {
                              case 'layout':
                                _pickLayout(menuButtonContext);
                              case 'sort':
                                _pickSortOrder(menuButtonContext);
                            }
                          },
                          // Filter isn't offered here - it's already one
                          // tap away via the reminder-visibility icon right
                          // in the search field (see
                          // reminder_visibility_button above), so a second
                          // entry point for the same choice would just be
                          // redundant.
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'layout',
                              child: ListTile(
                                leading: const Icon(Icons.view_agenda_outlined),
                                title: const Text('Layout'),
                                subtitle: Text(viewState.layout.label),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'sort',
                              child: ListTile(
                                leading: const Icon(Icons.sort),
                                title: const Text('Sort by'),
                                subtitle: Text(viewState.sortOrder.label),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
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
                notes: applyNotesView(_filterNotes(notes), viewState),
                layout: viewState.layout,
                selectedIds: _selectedIds,
                selectionMode: _selectionMode,
                searching: _searchQuery.isNotEmpty,
                filtered: viewState.filter != NoteReminderFilter.all,
                pendingDeleteIds: _pendingDeleteIds,
                onToggleSelection: _toggleSelection,
                onOpen: (note) => _openNote(context, ref, note),
                onRemoved: _finishDelete,
              ),
            ),
          ],
        ),
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
    final itemStyle = AppTextStyles.of(context).item;
    final syncState = ref.watch(syncProvider);
    final packageInfoAsync = ref.watch(packageInfoProvider);
    // Semantic version only - no build number/timestamp, which were only
    // ever useful for confirming which build is installed, not something
    // an end user needs to see on every drawer open.
    final versionText = packageInfoAsync.when(
      data: (info) => 'v${info.version}',
      loading: () => '',
      error: (_, _) => '',
    );

    return Drawer(
      child: SafeArea(
        // `minimum` guarantees breathing room below the pinned Sync row
        // even on devices where the system nav bar's reported inset
        // doesn't fully cover its own visual footprint (seen on a tablet
        // with an on-screen nav bar overlapping the drawer's last row).
        minimum: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'J',
                          style: TextStyle(
                            fontFamily: 'Pacifico',
                            fontSize: 32,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'jotes',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          versionText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('settings_drawer_item'),
                    leading: const Icon(Icons.settings_outlined),
                    title: Text('Settings', style: itemStyle),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    key: const Key('reminders_drawer_item'),
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text('Reminders', style: itemStyle),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RemindersScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  const SectionLabel('Data'),
                  ListTile(
                    leading: const Icon(Icons.upload_file),
                    title: Text('Import from Google Keep', style: itemStyle),
                    onTap: () {
                      Navigator.pop(context);
                      _importFromKeep(context, ref);
                    },
                  ),
                  ListTile(
                    key: const Key('import_markdown_item'),
                    leading: const Icon(Icons.description_outlined),
                    title: Text('Import from Markdown', style: itemStyle),
                    onTap: () {
                      Navigator.pop(context);
                      _importFromMarkdown(context, ref);
                    },
                  ),
                  ListTile(
                    key: const Key('export_markdown_item'),
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text('Export to Markdown', style: itemStyle),
                    subtitle: const Text('All notes, as a .zip'),
                    onTap: () {
                      Navigator.pop(context);
                      _exportNotesToMarkdown(context, notes);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('sync_drawer_item'),
              leading: Icon(
                syncState.status == SyncStatus.connected
                    ? Icons.cloud_done
                    : Icons.cloud_outlined,
              ),
              title: Text('Sync', style: itemStyle),
              subtitle: Text(
                syncState.status == SyncStatus.connected
                    ? 'Connected as ${syncState.userEmail}'
                    : 'Not connected',
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openNote(BuildContext context, WidgetRef ref, Note? note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(existing: note)),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No notes to export.')));
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
  final NoteLayout layout;
  final Set<String> selectedIds;
  final bool selectionMode;
  final bool searching;
  // Whether NotesViewState.filter is narrowing the list (independent of
  // [searching]) - lets the empty state say "no notes match this filter"
  // instead of the misleading "No notes yet" when e.g. "With reminders" is
  // selected and none happen to have one, or vice versa.
  final bool filtered;
  final Set<String> pendingDeleteIds;
  final void Function(String id) onToggleSelection;
  final void Function(Note note) onOpen;
  final void Function(Note note) onRemoved;

  const _NoteGrid({
    required this.notes,
    required this.layout,
    required this.selectedIds,
    required this.selectionMode,
    required this.searching,
    required this.filtered,
    required this.pendingDeleteIds,
    required this.onToggleSelection,
    required this.onOpen,
    required this.onRemoved,
  });

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      final message = searching
          ? 'No notes match your search.'
          : filtered
          ? 'No notes match this filter.'
          : 'No notes yet.\nTap + to create one.';
      return SliverFillRemaining(
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      );
    }

    // Keyed by note id (not the default positional identity) so each
    // card's own _RemovableNoteCard state - specifically, whether it's
    // mid-animation - stays correctly attached to that note as the
    // underlying list changes around it, rather than getting shuffled onto
    // a different note when one ahead of it is removed.
    Widget cardFor(Note note) => _RemovableNoteCard(
      key: ValueKey(note.id),
      removing: pendingDeleteIds.contains(note.id),
      onRemoved: () => onRemoved(note),
      child: NoteCard(
        note: note,
        selected: selectedIds.contains(note.id),
        selectionMode: selectionMode,
        onTap: () => selectionMode ? onToggleSelection(note.id) : onOpen(note),
        onLongPress: () => onToggleSelection(note.id),
      ),
    );

    // The Scaffold's body (this grid's own CustomScrollView, in
    // notes_screen.dart's _buildScaffold) is never wrapped in a SafeArea -
    // unlike the fixed toolbars/drawer elsewhere in this app, which already
    // reserve room for an on-screen gesture/nav bar via their own SafeArea
    // (see e.g. note_editor_screen.dart's bottom toolbar) - so without this,
    // scrolling to the end of the list leaves its last row sitting flush
    // against a flat 8px padding, unreachable behind the system nav bar on
    // an edge-to-edge display.
    final bottomInset = 8.0 + MediaQuery.paddingOf(context).bottom;

    return switch (layout) {
      NoteLayout.card => SliverPadding(
        padding: EdgeInsets.fromLTRB(8, 8, 8, bottomInset),
        sliver: SliverMasonryGrid(
          // Keyed on the ordered note ids: RenderSliverMasonryGrid caches
          // each child's column assignment (crossAxisIndex) on its own
          // parent data, and when a child survives a rebuild via its own
          // key (see cardFor's ValueKey(note.id) below), it reuses that
          // *old* cached column instead of recomputing it - fine as long
          // as the list only ever grows/shrinks in place, but this app's
          // default sort is "last edited, newest first", so editing any
          // note (even just checking off a checklist item) reorders the
          // whole list. A note that jumps to a new position while keeping
          // its stale column desyncs that column's height bookkeeping for
          // everything laid out after it, producing a column-sized blank
          // gap (reproduced directly against the package's own source -
          // see computeFirstChildParentData in RenderSliverMasonryGrid.
          // performLayout). Changing this key whenever the id order
          // changes forces a brand-new RenderSliverMasonryGrid with no
          // retained children/cached columns, sidestepping the bug
          // entirely rather than patching around its internals.
          key: ValueKey(notes.map((n) => n.id).join(',')),
          gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
          ),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          delegate: SliverChildBuilderDelegate(
            (context, i) => cardFor(notes[i]),
            childCount: notes.length,
          ),
        ),
      ),
      // A single full-width column, one note after another - the same
      // NoteCard as the card layout, just not packed side by side into
      // columns.
      NoteLayout.list => SliverPadding(
        padding: EdgeInsets.fromLTRB(8, 8, 8, bottomInset),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: cardFor(notes[i]),
            ),
            childCount: notes.length,
          ),
        ),
      ),
    };
  }
}

/// Shrinks and fades [child] out in place, then calls [onRemoved] - the
/// visual "confirmation a deletion took place" _deleteSelected's own doc
/// comment describes, shared by both the card and list layouts. Deliberately
/// just a fade/shrink rather than an animated slide-to-fill-the-gap: the
/// card layout's staggered masonry packing (SliverMasonryGrid, variable
/// card heights) has no built-in animated-reflow widget the way a plain
/// fixed-height grid or list would (see AnimatedList/SliverAnimatedGrid),
/// and building custom reflow-animation logic just for that one layout
/// would leave the two layouts behaving inconsistently - so both simply
/// shrink/fade the removed card out, then let the grid/list snap to its new
/// layout on the very next frame, once [onRemoved] actually removes the
/// note from the underlying data.
class _RemovableNoteCard extends StatelessWidget {
  final Widget child;
  final bool removing;
  final VoidCallback onRemoved;

  const _RemovableNoteCard({
    super.key,
    required this.child,
    required this.removing,
    required this.onRemoved,
  });

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: removing ? 0.7 : 1,
      duration: _duration,
      curve: Curves.easeIn,
      child: AnimatedOpacity(
        opacity: removing ? 0 : 1,
        duration: _duration,
        curve: Curves.easeIn,
        // Only wired up while actually removing - AnimatedOpacity's onEnd
        // also fires after any other opacity transition (there are none
        // here, but future-proofing this against a stray unrelated
        // rebuild-triggered no-op transition calling onRemoved is why this
        // isn't unconditional).
        onEnd: removing ? onRemoved : null,
        child: child,
      ),
    );
  }
}
