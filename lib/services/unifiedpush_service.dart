import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:unifiedpush/unifiedpush.dart';

import 'pb_service.dart';
import 'sync_engine.dart';

/// Wakes the app (even fully closed) when a note changes on another
/// device, via a self-hosted UnifiedPush distributor (e.g. ntfy) instead of
/// Google's FCM - see backend/push.go for the server side that sends these.
///
/// Android only: UnifiedPush's Flutter connector has no web implementation,
/// and reminders/background sync are already an Android-only feature (see
/// NotificationService), so this mirrors that scope rather than extending
/// it.
class UnifiedPushService {
  static final UnifiedPushService instance = UnifiedPushService._();
  UnifiedPushService._();

  Future<void> initialize() async {
    if (kIsWeb) return;

    await UnifiedPush.initialize(
      onNewEndpoint: _onNewEndpoint,
      onRegistrationFailed: _onRegistrationFailed,
      onUnregistered: _onUnregistered,
      onMessage: _onMessage,
      onTempUnavailable: _onTempUnavailable,
    );
  }

  /// Registers this device with whichever UnifiedPush distributor is
  /// already installed/default on it (e.g. the ntfy app) - call once sync
  /// is connected. There's no distributor picker UI in this first version:
  /// if none is set as default, registration silently no-ops and reminders
  /// simply keep working the way they always have (only while the app is
  /// open), same as before this feature existed.
  Future<void> register() async {
    if (kIsWeb) return;

    final canUse = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
    if (!canUse) {
      developer.log(
        'No UnifiedPush distributor available - skipping push registration',
        name: 'UnifiedPushService',
      );
      return;
    }

    final vapid = await PbService.instance.fetchVapidPublicKey();
    await UnifiedPush.register(vapid: vapid);
  }

  Future<void> unregister() async {
    if (kIsWeb) return;
    await PbService.instance.deletePushSubscription();
    await UnifiedPush.unregister();
  }

  Future<void> _onNewEndpoint(PushEndpoint endpoint, String instance) async {
    final keys = endpoint.pubKeySet;
    if (keys == null) {
      // Our backend can't encrypt a Web Push message without these -
      // shouldn't happen with a standards-compliant distributor, but skip
      // registration rather than send the server keys it can't use.
      developer.log(
        'New push endpoint has no encryption keys - skipping',
        name: 'UnifiedPushService',
      );
      return;
    }

    await PbService.instance.upsertPushSubscription(
      endpoint: endpoint.url,
      p256dh: keys.pubKey,
      auth: keys.auth,
      instance: instance,
    );
  }

  void _onRegistrationFailed(FailedReason reason, String instance) {
    developer.log('Push registration failed: $reason', name: 'UnifiedPushService');
  }

  void _onUnregistered(String instance) {
    developer.log('Push unregistered by distributor', name: 'UnifiedPushService');
  }

  void _onTempUnavailable(String instance) {
    developer.log('Push distributor temporarily unavailable', name: 'UnifiedPushService');
  }

  /// A push carries only a lightweight "something changed" hint (see
  /// backend/push.go), never the note data itself, so responding to one
  /// always means a full reconciliation rather than a targeted update -
  /// identical to what already happens on every normal reconnect.
  Future<void> _onMessage(PushMessage message, String instance) async {
    await mergeSync();
  }
}
