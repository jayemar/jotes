import 'dart:convert';

/// The recurrence unit a [RepeatRule] is built on - the same four units
/// Google Calendar's own quick-repeat presets and Custom recurrence dialog
/// both build on.
enum RepeatFrequency {
  daily('Day'),
  weekly('Week'),
  monthly('Month'),
  yearly('Year');

  const RepeatFrequency(this.unitLabel);

  /// Singular unit name for the Custom recurrence screen's "Every 1 ___"
  /// row - callers pluralize themselves when interval != 1 (see
  /// RepeatRule.summary).
  final String unitLabel;
}

/// When a repeating reminder stops recurring - mirrors Calendar's own
/// Custom recurrence "Ends" section exactly: never, on a specific date, or
/// after a fixed number of occurrences (counting the very first one).
sealed class RepeatEnd {
  const RepeatEnd();

  Map<String, dynamic> toJson();

  static RepeatEnd fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'onDate' => RepeatEndOnDate(DateTime.parse(json['date'] as String)),
      'afterCount' => RepeatEndAfterCount(json['count'] as int),
      _ => const RepeatEndNever(),
    };
  }
}

class RepeatEndNever extends RepeatEnd {
  const RepeatEndNever();

  @override
  Map<String, dynamic> toJson() => {'type': 'never'};

  @override
  bool operator ==(Object other) => other is RepeatEndNever;

  @override
  int get hashCode => (RepeatEndNever).hashCode;
}

class RepeatEndOnDate extends RepeatEnd {
  final DateTime date;

  const RepeatEndOnDate(this.date);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'onDate',
    'date': date.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is RepeatEndOnDate && other.date == date;

  @override
  int get hashCode => Object.hash(RepeatEndOnDate, date);
}

class RepeatEndAfterCount extends RepeatEnd {
  /// Total number of occurrences the rule ever produces, counting the
  /// very first (original) one - matches how Calendar's own "After N
  /// occurrences" counts.
  final int count;

  const RepeatEndAfterCount(this.count);

  @override
  Map<String, dynamic> toJson() => {'type': 'afterCount', 'count': count};

  @override
  bool operator ==(Object other) =>
      other is RepeatEndAfterCount && other.count == count;

  @override
  int get hashCode => Object.hash(RepeatEndAfterCount, count);
}

/// DateTime.monday..sunday, in week order - shared by the weekday chips on
/// the Custom recurrence screen and by [RepeatRule]'s own short weekday
/// labels.
const weekdayShortLabels = {
  DateTime.monday: 'Mon',
  DateTime.tuesday: 'Tue',
  DateTime.wednesday: 'Wed',
  DateTime.thursday: 'Thu',
  DateTime.friday: 'Fri',
  DateTime.saturday: 'Sat',
  DateTime.sunday: 'Sun',
};

const _weekdaysMonToFri = {1, 2, 3, 4, 5};

/// A note's full recurrence rule - [Note.repeatRule] being null means "does
/// not repeat" at all; this class only ever describes a reminder that
/// does. Deliberately modeled on Google Calendar's own Custom recurrence
/// dialog: an interval count on top of the frequency ("every 2 weeks", not
/// just "weekly"), specific weekdays for a weekly rule, and an end
/// condition - not just a fixed daily/weekly/monthly/yearly preset.
class RepeatRule {
  /// The recurrence unit - see [RepeatFrequency].
  final RepeatFrequency frequency;

  /// "Every [interval] [frequency]" - e.g. interval: 2, frequency: weekly
  /// is "every 2 weeks". Always >= 1.
  final int interval;

  /// Which weekdays a *weekly* rule fires on (DateTime.monday..sunday) -
  /// meaningless for any other frequency. Empty means "whatever weekday
  /// the reminder itself already falls on", matching the quick presets
  /// (see [RepeatRule.preset]) - only a Custom weekly rule with specific
  /// days checked ever populates this.
  final Set<int> weekdays;

  /// When this rule stops recurring - see [RepeatEnd].
  final RepeatEnd end;

  const RepeatRule({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const {},
    this.end = const RepeatEndNever(),
  }) : assert(interval >= 1, 'interval must be at least 1');

  /// One of the original 5 quick presets (daily/weekly/monthly/yearly,
  /// each with interval 1, no specific weekday, never-ending) - what this
  /// app offered before Custom recurrence existed, and still the default
  /// the picker sheet's simple options produce.
  factory RepeatRule.preset(RepeatFrequency frequency) =>
      RepeatRule(frequency: frequency);

  /// "Every weekday" - Calendar's own 6th quick preset, on top of the
  /// original 5 above.
  factory RepeatRule.everyWeekday() => const RepeatRule(
    frequency: RepeatFrequency.weekly,
    weekdays: _weekdaysMonToFri,
  );

  bool get isEveryWeekday =>
      frequency == RepeatFrequency.weekly &&
      weekdays.length == _weekdaysMonToFri.length &&
      weekdays.containsAll(_weekdaysMonToFri);

  /// Whether this is exactly one of the 5 original fixed presets - lets
  /// the picker sheet show it pre-checked there instead of always falling
  /// through to "Custom...".
  bool get isSimplePreset =>
      interval == 1 && weekdays.isEmpty && end is RepeatEndNever;

  RepeatRule copyWith({
    RepeatFrequency? frequency,
    int? interval,
    Set<int>? weekdays,
    RepeatEnd? end,
  }) {
    return RepeatRule(
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      weekdays: weekdays ?? this.weekdays,
      end: end ?? this.end,
    );
  }

  /// Short, human-readable description shown as the Repeat row's subtitle
  /// once a rule is anything beyond a bare preset - e.g. "Every 2 weeks on
  /// Mon, Wed" or "Every year, 5 times" or "Every weekday". A plain
  /// preset's own [RepeatFrequency] label (see reminder_edit_screen.dart)
  /// is used instead when [isSimplePreset] is true, so this only needs to
  /// handle the genuinely custom cases.
  String get summary {
    final parts = <String>[];
    if (isEveryWeekday) {
      parts.add('Every weekday (Mon–Fri)');
    } else {
      final unit = interval == 1
          ? frequency.unitLabel.toLowerCase()
          : '${frequency.unitLabel.toLowerCase()}s';
      parts.add('Every $interval $unit');
      if (frequency == RepeatFrequency.weekly && weekdays.isNotEmpty) {
        final sorted = weekdays.toList()..sort();
        parts.add(
          'on ${sorted.map((d) => weekdayShortLabels[d]).join(', ')}',
        );
      }
    }
    switch (end) {
      case RepeatEndNever():
        break;
      case RepeatEndOnDate(date: final date):
        parts.add(
          'until ${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
        );
      case RepeatEndAfterCount(count: final count):
        parts.add('($count time${count == 1 ? '' : 's'})');
    }
    return parts.join(' ');
  }

  Map<String, dynamic> toJson() => {
    'frequency': frequency.name,
    'interval': interval,
    'weekdays': weekdays.toList()..sort(),
    'end': end.toJson(),
  };

  /// Falls back to null (meaning "does not repeat") for anything
  /// unparseable - a corrupt/unrecognized value should never crash note
  /// loading, same reasoning as _repeatIntervalFromName's old fallback
  /// (see note.dart) did for the fixed-preset enum this replaces.
  static RepeatRule? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final frequency = RepeatFrequency.values.firstWhere(
        (f) => f.name == json['frequency'],
      );
      return RepeatRule(
        frequency: frequency,
        interval: (json['interval'] as num?)?.toInt() ?? 1,
        weekdays: {
          for (final d in (json['weekdays'] as List? ?? const []))
            (d as num).toInt(),
        },
        end: json['end'] is Map<String, dynamic>
            ? RepeatEnd.fromJson(json['end'] as Map<String, dynamic>)
            : const RepeatEndNever(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is RepeatRule &&
        other.frequency == frequency &&
        other.interval == interval &&
        other.weekdays.length == weekdays.length &&
        other.weekdays.containsAll(weekdays) &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(
    frequency,
    interval,
    Object.hashAllUnordered(weekdays),
    end,
  );

  @override
  String toString() => 'RepeatRule(${jsonEncode(toJson())})';
}

/// Advances one single step under [rule] - the core "what's the next
/// occurrence" logic, deliberately separate from end-condition/catch-up
/// handling (see [nextRuleOccurrence]) so each stays independently
/// testable. [RepeatFrequency.monthly]/[yearly] use DateTime's own
/// month/year arithmetic, which normalizes an out-of-range day (e.g. Jan
/// 31 + 1 month) into the following month instead of clamping to that
/// month's last day - a deliberately simple "add N and go" recurrence, not
/// full calendar-aware scheduling.
DateTime _advanceOnce(DateTime from, RepeatRule rule) {
  return switch (rule.frequency) {
    RepeatFrequency.daily => from.add(Duration(days: rule.interval)),
    RepeatFrequency.weekly => _advanceWeekly(from, rule),
    RepeatFrequency.monthly => DateTime(
      from.year,
      from.month + rule.interval,
      from.day,
      from.hour,
      from.minute,
    ),
    RepeatFrequency.yearly => DateTime(
      from.year + rule.interval,
      from.month,
      from.day,
      from.hour,
      from.minute,
    ),
  };
}

/// [RepeatRule.weekdays] empty means "same weekday every [interval]
/// weeks", the simple case. A non-empty set (only reachable via Custom
/// recurrence) instead walks forward to the next selected weekday within
/// the current week; once the week runs out of selected days left, it
/// wraps to the first selected weekday of the week [interval] cycles
/// later - e.g. "every 2 weeks on Mon/Wed" from a Wednesday jumps to the
/// Monday two full weeks after this week's Monday, not next week's.
DateTime _advanceWeekly(DateTime from, RepeatRule rule) {
  if (rule.weekdays.isEmpty) {
    return from.add(Duration(days: 7 * rule.interval));
  }
  final sortedDays = rule.weekdays.toList()..sort();
  final currentWeekday = from.weekday;
  for (final day in sortedDays) {
    if (day > currentWeekday) {
      return from.add(Duration(days: day - currentWeekday));
    }
  }
  final daysToWeekEnd = 7 - currentWeekday;
  final extraWeeks = 7 * (rule.interval - 1);
  return from.add(Duration(days: daysToWeekEnd + sortedDays.first + extraWeeks));
}

/// Whether the occurrence at [date], numbered [occurrenceNumber] (1 =
/// first ever), is past [rule]'s own [RepeatEnd] - see
/// [RepeatEndAfterCount]'s own doc comment for why occurrence numbering
/// starts at 1 and counts the original occurrence too.
bool _isPastEnd(RepeatRule rule, DateTime date, int occurrenceNumber) {
  return switch (rule.end) {
    RepeatEndNever() => false,
    RepeatEndOnDate(date: final endDate) => date.isAfter(endDate),
    RepeatEndAfterCount(count: final count) => occurrenceNumber > count,
  };
}

/// Advances [from] (the [occurrenceNumber]th occurrence so far) to the
/// next occurrence under [rule] that's still ahead of [now] (defaults to
/// the real current time) - skipping past however many cycles have
/// already been missed, the same "don't get stuck re-landing on an
/// already-past time" reasoning the old nextFutureOccurrence had for the
/// original fixed presets (see NotificationService.
/// advanceOverdueRepeatingReminders). Always advances by at least one step
/// even if [from] itself is already after [now].
///
/// Returns null once [rule]'s own [RepeatEnd] is reached partway through
/// that walk - not "this occurrence is done" but "this reminder has
/// genuinely finished repeating for good," which callers should treat the
/// same as a note with no repeat rule at all from that point on.
({DateTime reminderAt, int occurrenceNumber})? nextRuleOccurrence(
  DateTime from,
  int occurrenceNumber,
  RepeatRule rule, {
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  var next = from;
  var occurrence = occurrenceNumber;
  while (true) {
    next = _advanceOnce(next, rule);
    occurrence += 1;
    if (_isPastEnd(rule, next, occurrence)) return null;
    if (next.isAfter(effectiveNow)) {
      return (reminderAt: next, occurrenceNumber: occurrence);
    }
  }
}
