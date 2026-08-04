import 'package:shared_preferences/shared_preferences.dart';

const _snoozeModePrefsKey = 'snooze_mode';
const _snoozeCustomDelayMinutesPrefsKey = 'snooze_custom_delay_minutes';
const _snoozeTimeOfDayMinutesPrefsKey = 'snooze_time_of_day_minutes';

/// How far the notification's single "Snooze" action (see
/// notification_service.dart) pushes a reminder out - configured once here,
/// not chosen fresh each time a reminder fires, since Android has no way to
/// show a picker of any kind directly inside a notification action without
/// opening the app. A few fixed presets cover the common case with zero
/// setup; [custom] and [timeOfDay] exist for everything else - an arbitrary
/// delay, or "always push it to a specific time of day" (e.g. after work),
/// respectively.
enum SnoozeMode {
  fifteenMinutes('15 minutes'),
  thirtyMinutes('30 minutes'),
  oneHour('1 hour'),
  threeHours('3 hours'),
  custom('Custom delay'),
  timeOfDay('Time of day');

  const SnoozeMode(this.label);

  /// Shown in the Settings picker.
  final String label;
}

class SnoozeSettings {
  static final SnoozeSettings instance = SnoozeSettings._();
  SnoozeSettings._();

  static const defaultMode = SnoozeMode.oneHour;
  static const defaultCustomDelayMinutes = 60;
  static const defaultTimeOfDayMinutes = 9 * 60; // 9:00 AM
  static const _maxCustomDelayMinutes = 7 * 24 * 60; // 1 week

  /// Deliberately plain SharedPreferences, not a Riverpod provider like
  /// AppearanceNotifier - this also needs to be read from
  /// handleBackgroundReminderAction's background isolate, which has no
  /// ProviderScope to read from.
  Future<SnoozeMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_snoozeModePrefsKey);
    return SnoozeMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => defaultMode,
    );
  }

  Future<void> setMode(SnoozeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snoozeModePrefsKey, mode.name);
  }

  /// Only meaningful when [getMode] returns [SnoozeMode.custom].
  Future<int> getCustomDelayMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_snoozeCustomDelayMinutesPrefsKey) ??
        defaultCustomDelayMinutes;
  }

  /// Clamped to at least 1 minute (a 0 or negative delay would fire
  /// immediately, defeating the point of snoozing) and at most a week
  /// (well past anything a "snooze" is meant for, and large enough to
  /// catch a stray typo like an extra digit).
  Future<void> setCustomDelayMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _snoozeCustomDelayMinutesPrefsKey,
      minutes.clamp(1, _maxCustomDelayMinutes),
    );
  }

  /// Minutes since midnight. Only meaningful when [getMode] returns
  /// [SnoozeMode.timeOfDay].
  Future<int> getTimeOfDayMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_snoozeTimeOfDayMinutesPrefsKey) ??
        defaultTimeOfDayMinutes;
  }

  Future<void> setTimeOfDayMinutes(int minutesSinceMidnight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _snoozeTimeOfDayMinutesPrefsKey,
      minutesSinceMidnight.clamp(0, 24 * 60 - 1),
    );
  }

  /// Resolves the currently configured snooze setting to an actual point
  /// in time, relative to [now] (defaults to the real current time -
  /// overridable for tests).
  Future<DateTime> resolveNext({DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();
    switch (await getMode()) {
      case SnoozeMode.fifteenMinutes:
        return effectiveNow.add(const Duration(minutes: 15));
      case SnoozeMode.thirtyMinutes:
        return effectiveNow.add(const Duration(minutes: 30));
      case SnoozeMode.oneHour:
        return effectiveNow.add(const Duration(hours: 1));
      case SnoozeMode.threeHours:
        return effectiveNow.add(const Duration(hours: 3));
      case SnoozeMode.custom:
        final minutes = await getCustomDelayMinutes();
        return effectiveNow.add(Duration(minutes: minutes));
      case SnoozeMode.timeOfDay:
        final todMinutes = await getTimeOfDayMinutes();
        final candidate = DateTime(
          effectiveNow.year,
          effectiveNow.month,
          effectiveNow.day,
          todMinutes ~/ 60,
          todMinutes % 60,
        );
        // Already passed for today (or is right now) - push to the same
        // time tomorrow instead, so this always resolves to a future time.
        return candidate.isAfter(effectiveNow)
            ? candidate
            : candidate.add(const Duration(days: 1));
    }
  }
}
