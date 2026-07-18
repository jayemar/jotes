import 'dart:async';

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/appearance_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/notes_screen.dart';
import 'services/db_service.dart';
import 'services/notification_service.dart';
import 'services/pb_service.dart';
import 'services/unifiedpush_service.dart';
import 'widgets/reminder_popup.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// UnifiedPush can start the app headlessly (no UI) purely to hand a
/// background push to [UnifiedPushService], passing `--unifiedpush-bg` in
/// [args] - the same entrypoint runs either way, and this flag is what
/// decides whether to actually build a widget tree. See
/// UnifiedPushService.initialize for why onMessage needs to be registered
/// in both cases.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // The 4 curated fonts (see assets/google_fonts/) are bundled as local
  // assets specifically so font choice works fully offline - this makes
  // that a hard guarantee rather than a hope: if a lookup ever misses the
  // bundled asset (e.g. a typo'd family name), fail loudly instead of
  // silently reaching out to Google's servers.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final family in ['Inter', 'Lora', 'RobotoMono', 'Quicksand']) {
      final license = await rootBundle
          .loadString('assets/google_fonts/licenses/$family-OFL.txt');
      yield LicenseEntryWithLineBreaks([family], license);
    }
  });

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
    final context = navigatorKey.currentContext;
    if (context == null) return;
    // navigatorKey.currentContext is re-fetched fresh above, not a stale
    // State's own context captured before the await - safe despite the
    // lint, same reasoning as the ignores elsewhere in this codebase.
    // ignore: use_build_context_synchronously
    await showReminderPopup(context, note);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final appearance = ref.watch(appearanceProvider);
    final fontFamily = appearance.font.fontFamily;

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
        fontFamily: fontFamily,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: fontFamily,
      ),
      // The text-size setting is a deliberate app-level override, not a
      // multiplier on top of the system's own accessibility text scale -
      // simpler to reason about ("Large" always renders the same), and
      // consistent with how the font choice above is also an override
      // rather than a system-setting-aware adjustment.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(appearance.textSize.scale),
        ),
        child: child!,
      ),
      home: const NotesScreen(),
    );
  }
}
