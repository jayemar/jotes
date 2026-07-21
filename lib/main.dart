import 'dart:async';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'providers/appearance_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/note_editor_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/widget_note_picker_screen.dart';
import 'services/db_service.dart';
import 'services/notification_service.dart';
import 'services/pb_service.dart';
import 'services/unifiedpush_service.dart';
import 'theme/app_text_styles.dart';
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
      final license = await rootBundle.loadString(
        'assets/google_fonts/licenses/$family-OFL.txt',
      );
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

/// Separate entrypoint Android launches instead of [main] when the user is
/// placing a Single Note widget on their home screen (see
/// WidgetConfigurationActivity.kt, which points its FlutterActivity at this
/// function by name rather than the default). Skips all the reminder/push
/// setup above since this is just a note picker, not the full app.
@pragma('vm:entry-point')
Future<void> configureMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final widgetId = await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure();
  runApp(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: WidgetNotePickerScreen(widgetId: widgetId),
      ),
    ),
  );
}

class JotesApp extends ConsumerStatefulWidget {
  const JotesApp({super.key});

  @override
  ConsumerState<JotesApp> createState() => _JotesAppState();
}

class _JotesAppState extends ConsumerState<JotesApp> {
  StreamSubscription<String>? _tapSubscription;
  StreamSubscription<Uri?>? _widgetClickSubscription;

  @override
  void initState() {
    super.initState();
    _tapSubscription = NotificationService.instance.onNoteTapped.listen(
      _openNoteById,
    );
    _widgetClickSubscription = HomeWidget.widgetClicked.listen(
      _openNoteFromWidget,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final launchNoteId = await NotificationService.instance.getLaunchNoteId();
      if (launchNoteId != null) _openNoteById(launchNoteId);
      final widgetUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (widgetUri != null) _openNoteFromWidget(widgetUri);
    });
  }

  @override
  void dispose() {
    _tapSubscription?.cancel();
    _widgetClickSubscription?.cancel();
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
    await showReminderPopup(context, ref, note);
  }

  /// A tap on either home-screen widget carries a `jotes://note/{id}` URI
  /// (see HomeWidgetIntent.kt on the Kotlin side). Unlike a fired reminder
  /// notification (_openNoteById, which shows the snooze/dismiss popup), a
  /// widget tap just means "I want to look at this note" - so this goes
  /// straight to the editor instead.
  Future<void> _openNoteFromWidget(Uri? uri) async {
    if (uri == null || uri.pathSegments.length < 2) return;
    if (uri.pathSegments[0] != 'note') return;
    final note = await DbService.instance.getById(uri.pathSegments[1]);
    if (note == null) return; // note may have since been deleted
    final navState = navigatorKey.currentState;
    if (navState == null) return;
    navState.push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(existing: note)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final appearance = ref.watch(appearanceProvider);

    final lightBase = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
      useMaterial3: true,
    );
    final darkBase = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A73E8),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'jotes',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: lightBase.copyWith(
        textTheme: appearance.font.textTheme(lightBase.textTheme),
        extensions: [AppTextStyles.fromColorScheme(lightBase.colorScheme)],
      ),
      darkTheme: darkBase.copyWith(
        textTheme: appearance.font.textTheme(darkBase.textTheme),
        extensions: [AppTextStyles.fromColorScheme(darkBase.colorScheme)],
      ),
      // The text-size setting is a deliberate app-level override, not a
      // multiplier on top of the system's own accessibility text scale -
      // simpler to reason about ("Large" always renders the same), and
      // consistent with how the font choice above is also an override
      // rather than a system-setting-aware adjustment.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(appearance.textSize.scale)),
        child: child!,
      ),
      home: const NotesScreen(),
    );
  }
}
