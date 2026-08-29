import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.jayemar.jotes/periodic_refresh');
const _enabledPrefsKey = 'periodic_refresh_enabled';

/// Whether the periodic (~15 minute) background refresh is enabled - see
/// PeriodicRefreshWorker.kt and main.dart's --periodic-refresh branch for
/// what it actually does: a best-effort mergeSync with the server (so a
/// change made on another device, e.g. a Dismiss, is picked up even if
/// push delivery isn't working), then re-deriving the widget's
/// upcoming/overdue state against the current time and re-posting an
/// overdue reminder that's no longer showing in the notification shade,
/// both of which happen regardless of whether the sync above succeeded.
/// Defaults to on, matching the behavior before this became configurable.
///
/// The actual WorkManager schedule lives entirely on the native side (see
/// MainActivity.kt) - this class only owns the persisted on/off choice and
/// tells native what to do with it, since reading this app's
/// SharedPreferences file directly from Kotlin isn't a stable enough format
/// to depend on.
class PeriodicRefreshSettings {
  static final PeriodicRefreshSettings instance = PeriodicRefreshSettings._();
  PeriodicRefreshSettings._();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledPrefsKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefsKey, enabled);
    await _applyToNative(enabled);
  }

  /// Syncs native's WorkManager schedule to the persisted setting - called
  /// once at every normal app startup (see main.dart) so a fresh install's
  /// default-on state actually gets scheduled the first time the app ever
  /// runs, and so an app update doesn't need its own separate migration
  /// step to (re)apply whatever was last chosen.
  Future<void> applyToNative() async {
    await _applyToNative(await isEnabled());
  }

  Future<void> _applyToNative(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setPeriodicRefreshEnabled', enabled);
    } catch (_) {
      // Best-effort - same reasoning as AutostartService; the setting is
      // already persisted above and will still be applied next launch.
    }
  }
}
