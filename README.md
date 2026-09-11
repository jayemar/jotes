# jotes

A self-hosted, Keep-style notes app with cross-device sync.

## Architecture

- **Flutter/Dart app**, Android-first - reminders, home-screen widgets, and
  local notifications are Android-only (guarded by `kIsWeb` checks
  throughout `lib/services/`). A web build also exists (see `web/`) for
  viewing/editing notes without those Android-only features, published as
  a static site via `.github/workflows/publish-web-image.yml`.
- **State management**: Riverpod (`lib/providers/`) - `notes_provider.dart`
  owns the note list and drives local save + reminder scheduling + server
  push on every edit; `sync_provider.dart` drives the realtime sync
  subscription.
- **Local storage**: sembast (an embedded NoSQL store) via
  `lib/services/db_service.dart` - the on-device source of truth; every
  note read/write goes through this independently of sync.
- **Sync**: PocketBase, via `lib/services/pb_service.dart` (REST/realtime
  client) and `lib/services/sync_engine.dart` (`mergeSync()`, the merge/
  reconciliation logic run on app open, pull-to-refresh, and every
  incoming push). The server itself lives outside this repo - see "Sync
  backend" below.
- **Push wake-up**: UnifiedPush (`lib/services/unifiedpush_service.dart`),
  not Firebase - a self-hosted-friendly mechanism that just wakes the app
  to run `mergeSync()`, rather than carrying a payload itself.
- **Reminders/notifications**: `lib/services/notification_service.dart`
  schedules local notifications via `flutter_local_notifications`;
  per-reminder sound/icon choice lives in
  `lib/services/notification_appearance_settings.dart`. Native Android
  code (`android/app/src/main/kotlin/com/jayemar/jotes/MainActivity.kt`)
  backs several platform channels - autostart-settings detection,
  periodic background refresh via WorkManager, share-intent handling, and
  listing the device's own system notification sounds.
- **Home-screen widgets**: Jetpack Glance-based (`SingleNoteWidget`,
  `ReminderListWidget`), built in Kotlin, fed by
  `lib/services/widget_service.dart`.
- **Headless entry points**: `lib/main.dart` also runs as a bare
  `FlutterEngine` with no UI for `--boot-restore` (re-post reminders after
  a reboot), `--periodic-refresh` (WorkManager-triggered background
  sync), and `--unifiedpush-bg` (push-triggered sync).

## Getting it running

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(Dart SDK `^3.12.2`, per `pubspec.yaml`).

```sh
flutter pub get
flutter run      # debug build on a connected device/emulator
```

The app has no build-time knowledge of the sync backend - once it's
running, enter a PocketBase server URL in the app's Settings -> Sync
screen (see `lib/services/pb_service.dart`). Reminders, notifications, and
home-screen widgets only work on Android; other platforms just skip that
functionality.

To build and install a release APK:

```sh
./build-apk.sh       # bumps the build number, builds build/app/outputs/flutter-apk/app-release.apk
./copy-to-sync.sh     # copies the built APK to a synced directory for install on a device
```

A release build needs `android/key.properties` (gitignored, not in this
repo) with a signing key - see the `signingConfigs` block in
`android/app/build.gradle.kts` for the expected fields (`keyAlias`,
`keyPassword`, `storeFile`, `storePassword`). A debug build (`flutter
run`) doesn't need this.

Tests:

```sh
flutter test --exclude-tags=integration
```

Two tests (`test/pb_service_integration_test.dart`,
`test/sync_provider_test.dart`) are tagged `integration` and exercise a
real, running PocketBase instance rather than mocks - they skip
automatically if no server is reachable, so they're excluded above for a
routine run.

## Sync backend

The sync backend is PocketBase, but it no longer lives in this repo (the
old `backend/` directory is gone). It's now part of
`~/projects/homelab/pocketbase/` - a server shared with other apps
(currently also meditation-timer), each with its own collections/hooks
package under `pocketbase/apps/<app>/`. This repo's collections
(`notes`, `push_subscriptions`, the snooze-settings fields on `users`)
and the notes-push Web Push hooks live in `apps/jotes/` there - see that
repo's README for deployment details.

The app itself has no build-time knowledge of the backend's location -
enter the server URL in the app's Settings -> Sync screen (see
`lib/services/pb_service.dart`), same as on any other device.
