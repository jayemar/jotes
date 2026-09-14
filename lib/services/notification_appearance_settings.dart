import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _soundsChannel = MethodChannel('com.jayemar.jotes/notification_sounds');
const _appearanceByNotePrefsKey = 'notification_appearance_by_note';

/// The channel id used when no custom sound has been chosen for a given
/// reminder - unchanged from before this setting existed, so a note that's
/// never had a custom sound picked for it keeps using exactly the channel
/// it already has. See [NotificationAppearanceSettings.channelIdFor] for
/// why a chosen sound needs a different channel entirely.
const jotesReminderBaseChannelId = 'jotes_reminders';

/// Android's own well-known URI for "whatever the user has set as their
/// device-wide default notification sound" - also what
/// [NotificationAppearanceSettings.systemSoundOptions]'s own "Default"
/// entry resolves to (see MainActivity.kt's listNotificationSounds).
/// Selecting it is treated identically to never having chosen a sound at
/// all (see [NotificationAppearanceSettings.effectiveSoundUri]) - both mean
/// "just use the channel's own default", so explicitly picking "Default"
/// doesn't cost a second, functionally-identical channel next to
/// [jotesReminderBaseChannelId].
const _systemDefaultSoundUri = 'content://settings/system/notification_sound';

class NotificationSoundOption {
  const NotificationSoundOption({required this.uri, required this.title});
  final String uri;
  final String title;
}

enum NotificationIconOption {
  defaultIcon('ic_stat_default', 'Default'),
  shamrock('ic_stat_shamrock', 'Shamrock'),
  biohazard('ic_stat_biohazard', 'Biohazard'),
  dharma('ic_stat_dharma', 'Wheel of Dharma'),
  atom('ic_stat_atom', 'Atom'),
  pentagram('ic_stat_pentagram', 'Pentagram');

  const NotificationIconOption(this.drawable, this.label);

  /// The Android drawable resource name to pass as
  /// AndroidNotificationDetails.icon. [shamrock]/[biohazard]/[dharma]/
  /// [atom]/[pentagram] are vector drawables under
  /// android/app/src/main/res/drawable/; [defaultIcon] is instead a set of
  /// density-specific PNGs
  /// (drawable-{m,h,xh,xxh,xxxh}dpi/ic_stat_default.png), a proper
  /// alpha-silhouette crop of jotes' own "J" mark (see
  /// assets/icon/icon_foreground.png, the adaptive launcher icon's
  /// foreground layer) rather than a raster export of some other, unrelated
  /// glyph. Deliberately has its own dedicated drawable at all rather than
  /// falling back to null (which resolves to
  /// AndroidInitializationSettings.defaultIcon, i.e. the *full-color*
  /// launcher icon, blue background included) - a status-bar icon is
  /// supposed to be a plain white/alpha silhouette, and the launcher png
  /// rendered that way looks like an odd solid blob rather than a
  /// recognizable mark.
  ///
  /// Every value here is only ever referenced by this string at runtime
  /// (via AndroidNotificationDetails.icon), never anywhere R8's resource
  /// shrinker can trace statically - see
  /// android/app/src/main/res/raw/keep.xml, without which a release build
  /// silently strips all of these and scheduling then throws
  /// PlatformException(invalid_icon, ...).
  final String drawable;
  final String label;
}

/// One note's reminder sound/icon choice - see
/// [NotificationAppearanceSettings.getForNote].
class NoteNotificationAppearance {
  const NoteNotificationAppearance({
    this.soundUri,
    this.soundTitle,
    this.icon = NotificationIconOption.defaultIcon,
  });

  final String? soundUri;
  final String? soundTitle;
  final NotificationIconOption icon;
}

/// Where a reminder notification's sound and small status-bar icon are
/// configured - deliberately per-*note* (set in reminder_edit_screen.dart
/// at the same time as the reminder's date/time/repeat, not as a single
/// standing default in the Settings screen), since a fresh choice is
/// naturally part of creating/editing each reminder rather than something
/// worth a single app-wide default.
///
/// Deliberately its own local store, keyed by [Note.id], rather than
/// fields on [Note] itself: a sound's content:// uri is specific to the
/// device that offered it and generally won't resolve to anything on a
/// different device, so round-tripping it through Note's PocketBase
/// serialization would mean a value picked on one device either goes
/// nowhere useful on another or (worse) gets silently reset to null the
/// next time a remote update is merged in, since Note is rebuilt wholesale
/// from Note.fromPocketBase's fields on every such merge - see
/// SyncNotifier/PbService. Kept as plain SharedPreferences, not Riverpod -
/// same reasoning as SnoozeSettings: notification_service.dart's
/// _reminderNotificationDetails reads this from
/// handleBackgroundReminderAction's background isolate too, which has no
/// ProviderScope.
class NotificationAppearanceSettings {
  static final NotificationAppearanceSettings instance =
      NotificationAppearanceSettings._();
  NotificationAppearanceSettings._();

  /// A curated handful of this device's own notification sounds -
  /// "Default" first, then whatever MainActivity.kt's listNotificationSounds
  /// found via RingtoneManager (already capped there - see its own doc
  /// comment for why). Returns an empty list on any failure, including web
  /// (where the whole notifications feature doesn't exist) - the sound
  /// picker treats that as "nothing to offer", not an error.
  Future<List<NotificationSoundOption>> systemSoundOptions() async {
    if (kIsWeb) return const [];
    try {
      final raw = await _soundsChannel.invokeMethod<List<Object?>>(
        'listNotificationSounds',
      );
      if (raw == null) return const [];
      return [
        for (final entry in raw)
          if (entry is Map)
            NotificationSoundOption(
              uri: entry['uri'] as String,
              title: entry['title'] as String,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Plays [uri] once as a preview - best-effort and fire-and-forget, same
  /// reasoning as [systemSoundOptions] itself: a preview failing to play
  /// (including on web, where this whole feature doesn't exist) isn't worth
  /// surfacing as an error, just a picker tap that happens to be silent.
  Future<void> playSound(String uri) async {
    if (kIsWeb) return;
    try {
      await _soundsChannel.invokeMethod('playNotificationSound', uri);
    } catch (_) {
      // Best-effort, see doc comment above.
    }
  }

  Future<Map<String, dynamic>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_appearanceByNotePrefsKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Corrupt/unexpected stored value - treat as if nothing were ever
      // saved rather than throwing, same reasoning as RepeatRule.fromJson.
      return {};
    }
  }

  Future<void> _saveAll(Map<String, dynamic> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appearanceByNotePrefsKey, jsonEncode(all));
  }

  /// This note's currently configured sound/icon - the defaults (system
  /// sound, [NotificationIconOption.defaultIcon]) if never explicitly set.
  Future<NoteNotificationAppearance> getForNote(String noteId) async {
    final all = await _loadAll();
    final entry = all[noteId];
    if (entry is! Map) return const NoteNotificationAppearance();
    return NoteNotificationAppearance(
      soundUri: entry['soundUri'] as String?,
      soundTitle: entry['soundTitle'] as String?,
      icon: NotificationIconOption.values.firstWhere(
        (i) => i.name == entry['icon'],
        orElse: () => NotificationIconOption.defaultIcon,
      ),
    );
  }

  Future<void> setForNote(
    String noteId,
    NoteNotificationAppearance appearance,
  ) async {
    final all = await _loadAll();
    all[noteId] = {
      'soundUri': appearance.soundUri,
      'soundTitle': appearance.soundTitle,
      'icon': appearance.icon.name,
    };
    await _saveAll(all);
  }

  /// Called when a note's reminder is removed entirely, or the note itself
  /// is deleted - without this the per-note map would otherwise grow
  /// forever, one entry per note that ever had a custom sound/icon picked.
  Future<void> clearForNote(String noteId) async {
    final all = await _loadAll();
    if (all.remove(noteId) != null) await _saveAll(all);
  }

  /// The uri actually worth passing to AndroidNotificationDetails.sound -
  /// null both when [rawSoundUri] is null and when it's the explicit
  /// "Default" choice (see [_systemDefaultSoundUri]'s own doc comment), so
  /// either case leaves a reminder on the original, already-existing
  /// [jotesReminderBaseChannelId] channel rather than minting a redundant
  /// one.
  String? effectiveSoundUri(String? rawSoundUri) {
    if (rawSoundUri == null || rawSoundUri == _systemDefaultSoundUri) {
      return null;
    }
    return rawSoundUri;
  }

  /// Whether [optionUri] (one of [systemSoundOptions]'s own entries) is the
  /// one currently selected via [rawSoundUri] - true not just for a literal
  /// match, but also when nothing has been explicitly chosen yet
  /// ([rawSoundUri] is null) and [optionUri] is the "Default" entry itself,
  /// so a picker showing the current choice checks "Default" up front
  /// rather than showing nothing checked at all.
  bool isSelectedSound(String? rawSoundUri, String optionUri) {
    if (rawSoundUri == null) return optionUri == _systemDefaultSoundUri;
    return rawSoundUri == optionUri;
  }

  /// The channel a reminder notification should be scheduled/shown on for
  /// a given [rawSoundUri] (a note's own [NoteNotificationAppearance.soundUri]).
  /// Android channels are immutable once created, so changing the existing
  /// [jotesReminderBaseChannelId] channel's sound in code wouldn't affect
  /// anyone who already has it - a distinct sound needs a distinct channel
  /// instead. Deterministic per distinct sound uri, so two different notes
  /// (or the same note, re-picking a sound it used before) sharing a sound
  /// choice share the one channel rather than each minting their own;
  /// bounded in practice by [systemSoundOptions]'s own small cap on how
  /// many sounds there are to choose from in the first place.
  String channelIdFor(String? rawSoundUri) {
    final uri = effectiveSoundUri(rawSoundUri);
    if (uri == null) return jotesReminderBaseChannelId;
    return '${jotesReminderBaseChannelId}_'
        '${uri.hashCode.toUnsigned(32).toRadixString(16)}';
  }
}
