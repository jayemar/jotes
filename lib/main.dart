import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/theme_provider.dart';
import 'screens/note_editor_screen.dart';
import 'screens/notes_screen.dart';
import 'services/db_service.dart';
import 'services/notification_service.dart';
import 'services/pb_service.dart';
import 'services/unifiedpush_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// UnifiedPush can start the app headlessly (no UI) purely to hand a
/// background push to [UnifiedPushService], passing `--unifiedpush-bg` in
/// [args] - the same entrypoint runs either way, and this flag is what
/// decides whether to actually build a widget tree. See
/// UnifiedPushService.initialize for why onMessage needs to be registered
/// in both cases.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await UnifiedPushService.instance.initialize();

  if (args.contains('--unifiedpush-bg')) {
    await NotificationService.instance.initialize();
    await PbService.instance.restore();
    return;
  }

  await NotificationService.instance.initialize();
  runApp(const ProviderScope(child: JotesApp()));
}

class JotesApp extends ConsumerStatefulWidget {
  const JotesApp({super.key});

  @override
  ConsumerState<JotesApp> createState() => _JotesAppState();
}

class _JotesAppState extends ConsumerState<JotesApp> {
  StreamSubscription<String>? _tapSubscription;

  @override
  void initState() {
    super.initState();
    _tapSubscription =
        NotificationService.instance.onNoteTapped.listen(_openNoteById);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final launchNoteId = await NotificationService.instance.getLaunchNoteId();
      if (launchNoteId != null) _openNoteById(launchNoteId);
    });
  }

  @override
  void dispose() {
    _tapSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openNoteById(String id) async {
    final note = await DbService.instance.getById(id);
    if (note == null) return; // note may have since been deleted
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(existing: note)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'jotes',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const NotesScreen(),
    );
  }
}
