import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.jayemar.jotes/autostart');

class AutostartService {
  static final AutostartService instance = AutostartService._();
  AutostartService._();

  /// Whether this device's manufacturer is one of the small set known to
  /// ship a proprietary "autostart"/background-app-management screen that
  /// can silently block BootRestoreReceiver (see its own doc comment) from
  /// running at all. There is no way to detect whether autostart is
  /// actually *disabled* for this app - no such API exists, since it isn't
  /// a real Android concept - so this is only a "might be worth checking"
  /// signal based on manufacturer, not a definitive one.
  Future<bool> isKnownRestrictiveManufacturer() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'isKnownRestrictiveManufacturer',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens this device's manufacturer-specific autostart settings screen
  /// if a known one exists, falling back to this app's own details page
  /// otherwise - see MainActivity.kt for the actual candidate list and
  /// fallback chain, kept natively since it needs manufacturer-specific
  /// ComponentNames Dart has no reason to know about.
  Future<void> openAutostartSettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('openAutostartSettings');
    } catch (_) {
      // Best-effort - see MainActivity.kt's own fallback chain; nothing
      // more useful to do here if even the method channel call fails.
    }
  }
}
