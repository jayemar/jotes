import 'dart:async';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';
import 'providers/appearance_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/note_editor_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/widget_note_picker_screen.dart';
import 'services/background_sync_service.dart';
import 'services/db_service.dart';
import 'services/notification_service.dart';
import 'services/pb_service.dart';
import 'services/periodic_refresh_settings.dart';
import 'services/share_intent_service.dart';
import 'services/sync_engine.dart';
import 'services/unifiedpush_service.dart';
import 'services/widget_service.dart';
import 'theme/app_text_styles.dart';
import 'widgets/reminder_popup.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Extracts the note id from a `jotes://note/{id}` widget-tap URI (see
/// SingleNoteWidget.kt/ReminderListWidget.kt), or null if [uri] doesn't
/// match that shape. Pulled out of _openNoteFromWidget as a pure function
/// so this parsing is independently testable - for this URI shape, "note"
/// is the *host* (authority), not a path segment; pathSegments is just
/// `["{id}"]`. Get this wrong (as an earlier version did, checking
/// pathSegments[0]/[1]) and every widget tap silently no-ops.
@visibleForTesting
String? noteIdFromWidgetUri(Uri? uri) {
  if (uri == null || uri.host != 'note' || uri.pathSegments.isEmpty) {
    return null;
  }
  return uri.pathSegments[0];
}

/// UnifiedPush can start the app headlessly (no UI) purely to hand a
/// background push to [UnifiedPushService], passing `--unifiedpush-bg` in
/// [args] - the same entrypoint runs either way, and this flag is what
/// decides whether to actually build a widget tree. See
/// UnifiedPushService.initialize for why onMessage needs to be registered
/// in both cases.
///
/// BootRestoreReceiver/BootRestoreService (Kotlin) start the app headlessly
/// the same way on BOOT_COMPLETED, passing `--boot-restore` instead, so an
/// unresolved overdue reminder reappears without the user opening the app
/// first - see NotificationService.restoreUnresolvedReminders.
///
/// PeriodicRefreshWorker (Kotlin) does the same on a recurring WorkManager
/// schedule (roughly every 15 minutes, the shortest interval Android's
/// WorkManager allows for periodic work), passing `--periodic-refresh` -
/// covers two gaps a sync/push/boot-triggered refresh alone leaves: the
/// widget's upcoming/overdue split is only ever recomputed when something
/// pushes fresh data to it, so a reminder can sit displayed as "upcoming"
/// well past its own fire time until the next unrelated sync happens to
/// touch it; and restoreUnresolvedReminders() only ever runs once at
/// startup, so a reminder that fires normally but then gets cleared from
/// the notification shade some other way than tapping its own
/// Dismiss/Snooze action (a swipe, "Clear all", the shade being wiped by a
/// reboot) stays silently gone until the next app open. Deliberately
/// local-only (no PbService/mergeSync call) - both gaps are about
/// re-deriving state from what's already on this device against the
/// current time, not about fetching anything new from the server; actual
/// cross-device changes already have their own push path (see
/// UnifiedPushService).
///
/// [backgroundSyncCallbackDispatcher] is a separate, WorkManager-driven
/// headless trigger (not gated on an `args` flag, since Workmanager's own
/// plugin - not Android's Intent system - decides when to invoke it): see
/// BackgroundSyncService's own doc comment for what enqueues it and why.
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

  // requestPermissions: false in both headless branches below - same
  // reasoning as handleBackgroundReminderAction in notification_service.dart:
  // BootRestoreService/UnifiedPushService run this in a bare FlutterEngine
  // with no Activity attached (see BootRestoreService.kt), and
  // requestNotificationsPermission crashes native-side with no Activity to
  // show a dialog on - not by throwing something Dart could catch, but by
  // never sending a platform-channel result back, which hangs the awaiting
  // call forever and silently prevents everything after it (including
  // restoreUnresolvedReminders itself) from ever running.
  if (args.contains('--boot-restore')) {
    await NotificationService.instance.initialize(requestPermissions: false);
    await NotificationService.instance.restoreUnresolvedReminders();
    return;
  }

  if (args.contains('--periodic-refresh')) {
    await NotificationService.instance.initialize(requestPermissions: false);
    await NotificationService.instance.restoreUnresolvedReminders();
    await WidgetService.instance.syncAll(await DbService.instance.getAll());
    return;
  }

  await UnifiedPushService.instance.initialize();

  if (args.contains('--unifiedpush-bg')) {
    await NotificationService.instance.initialize(requestPermissions: false);
    await PbService.instance.restore();
    return;
  }

  await NotificationService.instance.initialize();
  ShareIntentService.instance.initialize();
  // Registers backgroundSyncCallbackDispatcher's callback handle with the
  // native side (persisted, so this only strictly needs to happen once
  // ever, but it's cheap and every other one-time native registration here
  // is likewise redone on every launch rather than tracked separately) -
  // see BackgroundSyncService's own doc comment for what this unlocks:
  // NotificationService.handleBackgroundReminderAction enqueuing a
  // WorkManager-backed sync instead of pushing inline from its own
  // unreliable background isolate.
  await Workmanager().initialize(backgroundSyncCallbackDispatcher);
  // Syncs native's WorkManager schedule to whatever the user last chose in
  // Settings (see PeriodicRefreshSettings) - a fresh install has never told
  // native anything, and an app update's native side starts with no memory
  // of a schedule from before either, so this has to run on every genuine
  // launch rather than only when the setting actually changes.
  unawaited(PeriodicRefreshSettings.instance.applyToNative());
  // Once per genuine app launch, not from the headless push path above (no
  // reason to re-alert the user from a background pocket-buzz wake) and not
  // from sync's own reconnect/push-driven mergeSync (which would otherwise
  // re-alert on every one of those for a reminder the user simply hasn't
  // gotten to yet) - see restoreUnresolvedReminders' own doc comment.
  unawaited(NotificationService.instance.restoreUnresolvedReminders());
  runApp(const ProviderScope(child: JotesApp()));
}

/// Invoked by WorkManager in a fresh headless engine whenever a task
/// enqueued via [BackgroundSyncService.enqueue] actually runs - registered
/// once via Workmanager().initialize() above in [main]. Runs the same full
/// reconciliation a normal app launch/reconnect already does (not a
/// narrower single-note push): by the time this runs, whatever local write
/// enqueued it has already landed (see BackgroundSyncService's own doc
/// comment), and mergeSync picks up anything else locally newer than the
/// server for the same underlying reason, not just the one change that
/// happened to trigger this particular task.
@pragma('vm:entry-point')
void backgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != backgroundSyncTaskName) return true;
    try {
      await PbService.instance.restore();
      await mergeSync();
      return true;
    } catch (_) {
      return false; // lets WorkManager retry per its backoff policy
    }
  });
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
  StreamSubscription<SharedContent>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    _tapSubscription = NotificationService.instance.onNoteTapped.listen(
      _openNoteById,
    );
    _widgetClickSubscription = HomeWidget.widgetClicked.listen(
      _openNoteFromWidget,
    );
    _shareSubscription = ShareIntentService.instance.onSharedText.listen(
      _openNoteFromShare,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final launchNoteId = await NotificationService.instance.getLaunchNoteId();
      if (launchNoteId != null) _openNoteById(launchNoteId);
      final widgetUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (widgetUri != null) _openNoteFromWidget(widgetUri);
      final sharedContent = await ShareIntentService.instance
          .getInitialSharedText();
      if (sharedContent != null) _openNoteFromShare(sharedContent);
    });
  }

  @override
  void dispose() {
    _tapSubscription?.cancel();
    _widgetClickSubscription?.cancel();
    _shareSubscription?.cancel();
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
  /// straight to the editor instead. Deliberately does not touch the tray
  /// notification or mark the reminder resolved - same reasoning as "Open
  /// note" in showReminderPopup.
  Future<void> _openNoteFromWidget(Uri? uri) async {
    final noteId = noteIdFromWidgetUri(uri);
    if (noteId == null) return;
    final note = await DbService.instance.getById(noteId);
    if (note == null) return; // note may have since been deleted
    final navState = navigatorKey.currentState;
    if (navState == null) return;
    navState.push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(existing: note)),
    );
  }

  /// Another app shared text into jotes (e.g. a mobile browser's "Share"
  /// action - see the ACTION_SEND intent-filter in AndroidManifest.xml and
  /// ShareIntentService). Opens a brand-new, not-yet-saved note pre-filled
  /// with it - lands in the editor so the user can review/edit before it's
  /// actually kept, rather than silently creating a note behind their
  /// back, matching how most other share targets (e.g. Google Keep)
  /// behave.
  void _openNoteFromShare(SharedContent shared) {
    final navState = navigatorKey.currentState;
    if (navState == null) return;
    navState.push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          initialTitle: shared.subject,
          initialBody: shared.text,
        ),
      ),
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
