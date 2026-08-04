import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.jayemar.jotes/share');

/// What another app (e.g. a mobile browser's "Share" action) sent to jotes
/// via Android's ACTION_SEND - [text] is always present, [subject] (e.g. a
/// shared page's title) is not always provided by the sending app.
class SharedContent {
  final String text;
  final String? subject;

  const SharedContent({required this.text, this.subject});
}

/// Turns the raw platform-channel payload (a Map with "text"/"subject"
/// keys - see MainActivity.kt's extractShare) into a [SharedContent], or
/// null if it doesn't look like a real share. Pulled out as a pure
/// function so this parsing is independently testable, same reasoning as
/// main.dart's noteIdFromWidgetUri.
@visibleForTesting
SharedContent? parseSharedContent(Object? raw) {
  if (raw is! Map) return null;
  final text = raw['text'];
  if (text is! String || text.isEmpty) return null;
  final subject = raw['subject'];
  return SharedContent(text: text, subject: subject is String ? subject : null);
}

/// Lets another app share plain text into jotes (registered as a share
/// target via the ACTION_SEND intent-filter on MainActivity in
/// AndroidManifest.xml) - e.g. sharing a page/selection from a mobile
/// browser opens a new, not-yet-saved note pre-filled with it (see
/// main.dart's _openNoteFromShare).
class ShareIntentService {
  static final ShareIntentService instance = ShareIntentService._();
  ShareIntentService._();

  final _sharedController = StreamController<SharedContent>.broadcast();

  /// Fires for a share arriving while jotes is already running (a "warm"
  /// share - MainActivity's launchMode="singleTop" routes it through
  /// onNewIntent instead of a fresh cold start). Call [initialize] once at
  /// app startup before relying on this.
  Stream<SharedContent> get onSharedText => _sharedController.stream;

  /// Must be called once at app startup (see main.dart), before
  /// [getInitialSharedText] or [onSharedText] can see anything - wires up
  /// the platform channel's incoming-call handler, same shape as
  /// NotificationService.initialize's onDidReceiveNotificationResponse.
  void initialize() {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final shared = parseSharedContent(call.arguments);
        if (shared != null) _sharedController.add(shared);
      }
    });
  }

  /// If the app process was cold-started by a share (jotes wasn't already
  /// running), returns that share. Call once, after the navigator is ready
  /// to push a route - mirrors NotificationService.getLaunchNoteId/
  /// HomeWidget.initiallyLaunchedFromHomeWidget for the same reason (no
  /// running app instance yet to deliver a live event to).
  Future<SharedContent?> getInitialSharedText() async {
    if (kIsWeb) return null;
    try {
      final raw = await _channel.invokeMethod('getInitialSharedText');
      return parseSharedContent(raw);
    } catch (_) {
      // Called from an unawaited post-frame callback at startup; a plugin
      // failure here must not surface as an unhandled app-launch exception -
      // same reasoning as NotificationService.getLaunchNoteId.
      return null;
    }
  }
}
