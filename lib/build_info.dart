/// Wall-clock time this build was compiled, injected via
/// `--dart-define=BUILD_TIMESTAMP=...` in build-apk.sh - not available to
/// ad-hoc `flutter build`/`flutter run` invocations that skip that flag.
const buildTimestamp = String.fromEnvironment(
  'BUILD_TIMESTAMP',
  defaultValue: 'dev build',
);
