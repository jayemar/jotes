import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/repeat_rule.dart';
// Both aliased to `tz` together, same as notification_service.dart's own
// import - data/latest.dart supplies initializeTimeZones(), timezone.dart
// supplies TZDateTime/getLocation/Location.
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);

  group('RepeatRule.preset/everyWeekday', () {
    test('preset is a simple interval-1, no-weekday, never-ending rule', () {
      final rule = RepeatRule.preset(RepeatFrequency.daily);
      expect(rule.interval, 1);
      expect(rule.weekdays, isEmpty);
      expect(rule.end, const RepeatEndNever());
      expect(rule.isSimplePreset, isTrue);
    });

    test('everyWeekday is a weekly rule on Mon-Fri', () {
      final rule = RepeatRule.everyWeekday();
      expect(rule.frequency, RepeatFrequency.weekly);
      expect(rule.weekdays, {1, 2, 3, 4, 5});
      expect(rule.isEveryWeekday, isTrue);
      // Not a "simple preset" - it has non-empty weekdays, distinguishing
      // it from the plain "Weekly" preset in the picker sheet.
      expect(rule.isSimplePreset, isFalse);
    });

    test('a custom interval is not a simple preset', () {
      final rule = RepeatRule(frequency: RepeatFrequency.weekly, interval: 2);
      expect(rule.isSimplePreset, isFalse);
    });

    test('a rule with an end condition is not a simple preset', () {
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: const RepeatEndAfterCount(5),
      );
      expect(rule.isSimplePreset, isFalse);
    });
  });

  group('RepeatRule equality', () {
    test('two rules with the same fields are equal', () {
      final a = RepeatRule(
        frequency: RepeatFrequency.weekly,
        interval: 2,
        weekdays: const {1, 3},
        end: RepeatEndOnDate(DateTime(2027, 1, 1)),
      );
      final b = RepeatRule(
        frequency: RepeatFrequency.weekly,
        interval: 2,
        weekdays: const {3, 1}, // different construction order
        end: RepeatEndOnDate(DateTime(2027, 1, 1)),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing weekdays are not equal', () {
      final a = RepeatRule(
        frequency: RepeatFrequency.weekly,
        weekdays: const {1},
      );
      final b = RepeatRule(
        frequency: RepeatFrequency.weekly,
        weekdays: const {2},
      );
      expect(a, isNot(b));
    });

    test('RepeatEndAfterCount compares by count', () {
      expect(const RepeatEndAfterCount(3), const RepeatEndAfterCount(3));
      expect(const RepeatEndAfterCount(3), isNot(const RepeatEndAfterCount(4)));
    });
  });

  group('RepeatRule JSON round-trip', () {
    test('a simple preset round-trips', () {
      final rule = RepeatRule.preset(RepeatFrequency.monthly);
      final restored = RepeatRule.fromJson(_encode(rule));
      expect(restored, rule);
    });

    test('a fully custom rule round-trips exactly', () {
      final rule = RepeatRule(
        frequency: RepeatFrequency.weekly,
        interval: 3,
        weekdays: const {1, 3, 5},
        end: const RepeatEndAfterCount(10),
      );
      final encoded = _encode(rule);
      final restored = RepeatRule.fromJson(encoded);
      expect(restored, rule);
    });

    test('a rule ending on a date round-trips the date', () {
      final rule = RepeatRule(
        frequency: RepeatFrequency.yearly,
        end: RepeatEndOnDate(DateTime.utc(2030, 6, 15)),
      );
      final encoded = _encode(rule);
      final restored = RepeatRule.fromJson(encoded);
      expect(restored, rule);
    });

    test('null/empty input decodes to null (does not repeat)', () {
      expect(RepeatRule.fromJson(null), isNull);
      expect(RepeatRule.fromJson(''), isNull);
    });

    test('unparseable/corrupt JSON falls back to null rather than '
        'throwing', () {
      expect(RepeatRule.fromJson('not json'), isNull);
      expect(RepeatRule.fromJson('{"frequency":"not_a_real_one"}'), isNull);
    });
  });

  group('RepeatRule.summary', () {
    test('every weekday', () {
      expect(RepeatRule.everyWeekday().summary, 'Every weekday (Mon–Fri)');
    });

    test('every N units, pluralized', () {
      final rule = RepeatRule(frequency: RepeatFrequency.weekly, interval: 2);
      expect(rule.summary, 'Every 2 weeks');
    });

    test('interval of 1 is not pluralized', () {
      final rule = RepeatRule(frequency: RepeatFrequency.monthly, interval: 1);
      expect(rule.summary, 'Every 1 month');
    });

    test('specific weekdays are listed in week order regardless of '
        'construction order', () {
      final rule = RepeatRule(
        frequency: RepeatFrequency.weekly,
        weekdays: const {5, 1, 3},
      );
      expect(rule.summary, 'Every 1 week on Mon, Wed, Fri');
    });

    test('an end-on-date condition is appended', () {
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: RepeatEndOnDate(DateTime(2027, 3, 5)),
      );
      expect(rule.summary, 'Every 1 day until 2027-03-05');
    });

    test('an end-after-count condition is appended, pluralized', () {
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: const RepeatEndAfterCount(1),
      );
      expect(rule.summary, 'Every 1 day (1 time)');

      final rule5 = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: const RepeatEndAfterCount(5),
      );
      expect(rule5.summary, 'Every 1 day (5 times)');
    });
  });

  group('nextRuleOccurrence - daily', () {
    test('advances by interval days', () {
      final from = DateTime(2026, 1, 1, 9);
      final rule = RepeatRule(frequency: RepeatFrequency.daily, interval: 3);
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: DateTime(2026, 1, 1, 10),
      );

      expect(result, isNotNull);
      expect(result!.reminderAt, DateTime(2026, 1, 4, 9));
      expect(result.occurrenceNumber, 2);
    });

    test('catches up multiple missed cycles', () {
      final from = DateTime(2026, 1, 1, 9);
      final rule = RepeatRule(frequency: RepeatFrequency.daily);
      final now = DateTime(2026, 1, 4, 15); // 3+ days later

      final result = nextRuleOccurrence(from, 1, rule, now: now);

      expect(result!.reminderAt, DateTime(2026, 1, 5, 9));
      expect(result.reminderAt.isAfter(now), isTrue);
      expect(result.occurrenceNumber, 5);
    });
  });

  group('nextRuleOccurrence - weekly with no specific weekday', () {
    test('advances by interval weeks, same weekday', () {
      final from = DateTime(2026, 1, 1, 9); // a Thursday
      final rule = RepeatRule(frequency: RepeatFrequency.weekly, interval: 2);
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      expect(result!.reminderAt, DateTime(2026, 1, 15, 9));
    });
  });

  group('nextRuleOccurrence - weekly with specific weekdays', () {
    test('advances to the next selected weekday within the same week', () {
      // Monday, weekdays Mon/Wed/Fri - from Monday should land on Wednesday.
      final from = DateTime(2026, 1, 5, 9); // Monday
      final rule = RepeatRule(
        frequency: RepeatFrequency.weekly,
        weekdays: const {1, 3, 5},
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      expect(result!.reminderAt, DateTime(2026, 1, 7, 9)); // Wednesday
    });

    test('wraps to the first selected weekday of the next cycle once the '
        'week runs out', () {
      // Friday, weekdays Mon/Wed/Fri - next should be Monday the
      // following week (interval 1).
      final from = DateTime(2026, 1, 9, 9); // Friday
      final rule = RepeatRule(
        frequency: RepeatFrequency.weekly,
        weekdays: const {1, 3, 5},
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      expect(result!.reminderAt, DateTime(2026, 1, 12, 9)); // Monday
    });

    test('an interval > 1 skips whole extra weeks when wrapping', () {
      // Friday, weekdays Mon/Wed/Fri, every 2 weeks - wrapping past Friday
      // should skip an entire extra week before landing on Monday.
      final from = DateTime(2026, 1, 9, 9); // Friday
      final rule = RepeatRule(
        frequency: RepeatFrequency.weekly,
        interval: 2,
        weekdays: const {1, 3, 5},
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      // Without the extra week this would be Jan 12; with it, Jan 19.
      expect(result!.reminderAt, DateTime(2026, 1, 19, 9));
    });
  });

  group('nextRuleOccurrence - monthly/yearly', () {
    test('monthly rolls an out-of-range day into the following month, '
        'same as the old nextOccurrence', () {
      final from = DateTime(2026, 1, 31, 9);
      final rule = RepeatRule(frequency: RepeatFrequency.monthly);
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      expect(result!.reminderAt, DateTime(2026, 3, 3, 9));
    });

    test('yearly advances by interval years', () {
      final from = DateTime(2026, 6, 15, 9);
      final rule = RepeatRule(frequency: RepeatFrequency.yearly, interval: 2);
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      expect(result!.reminderAt, DateTime(2028, 6, 15, 9));
    });
  });

  group('nextRuleOccurrence - RepeatEndOnDate', () {
    test(
      'continues while the next occurrence is on or before the end date',
      () {
        final from = DateTime(2026, 1, 1, 9);
        final rule = RepeatRule(
          frequency: RepeatFrequency.daily,
          end: RepeatEndOnDate(DateTime(2026, 1, 10)),
        );
        final result = nextRuleOccurrence(
          from,
          1,
          rule,
          now: from.add(const Duration(hours: 1)),
        );

        expect(result, isNotNull);
        expect(result!.reminderAt, DateTime(2026, 1, 2, 9));
      },
    );

    test('returns null once the next occurrence would fall after the end '
        'date - the rule has genuinely finished', () {
      final from = DateTime(2026, 1, 9, 9);
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: RepeatEndOnDate(DateTime(2026, 1, 9, 23, 59)),
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      expect(result, isNull);
    });

    test('returns null when catching up past several missed cycles runs '
        'straight through the end date', () {
      final from = DateTime(2026, 1, 1, 9);
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: RepeatEndOnDate(DateTime(2026, 1, 3)),
      );
      // "Now" is well past the end date - every subsequent occurrence is
      // both stale AND past the end, so this should end, not loop forever.
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: DateTime(2026, 2, 1),
      );

      expect(result, isNull);
    });
  });

  group('nextRuleOccurrence - RepeatEndAfterCount', () {
    test('continues while under the occurrence count', () {
      final from = DateTime(2026, 1, 1, 9);
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: const RepeatEndAfterCount(3),
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      expect(result, isNotNull);
      expect(result!.occurrenceNumber, 2);
    });

    test('returns null once the occurrence count is exhausted', () {
      final from = DateTime(2026, 1, 3, 9); // occurrence 3 of 3
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: const RepeatEndAfterCount(3),
      );
      final result = nextRuleOccurrence(
        from,
        3,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      expect(result, isNull);
    });

    test('catching up past several missed cycles that exhaust the count '
        'returns null, not a stale occurrence number', () {
      final from = DateTime(2026, 1, 1, 9);
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        end: const RepeatEndAfterCount(2),
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: DateTime(2026, 2, 1),
      );

      expect(result, isNull);
    });
  });

  test('nextRuleOccurrence always advances at least once, even if from is '
      'already after now', () {
    final from = DateTime(2026, 1, 5, 9);
    final rule = RepeatRule(frequency: RepeatFrequency.daily);
    final result = nextRuleOccurrence(from, 1, rule, now: DateTime(2026, 1, 1));

    expect(result!.reminderAt, DateTime(2026, 1, 6, 9));
    expect(result.occurrenceNumber, 2);
  });

  group('RepeatRule.followsLocalTime/timezone', () {
    test('defaults to following local time, with no timezone', () {
      final rule = RepeatRule.preset(RepeatFrequency.daily);
      expect(rule.followsLocalTime, isTrue);
      expect(rule.timezone, isNull);
    });

    test('round-trips through JSON', () {
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        followsLocalTime: false,
        timezone: 'America/Los_Angeles',
      );
      final restored = RepeatRule.fromJson(_encode(rule));
      expect(restored, rule);
      expect(restored?.followsLocalTime, isFalse);
      expect(restored?.timezone, 'America/Los_Angeles');
    });

    test('absent from JSON (a rule encoded before this field existed) '
        'defaults to following local time', () {
      final legacyJson = jsonEncode({
        'frequency': 'daily',
        'interval': 1,
        'weekdays': <int>[],
        'end': {'type': 'never'},
      });
      final restored = RepeatRule.fromJson(legacyJson);
      expect(restored?.followsLocalTime, isTrue);
      expect(restored?.timezone, isNull);
    });

    test('copyWith(timezone: null) explicitly clears an existing zone, '
        'distinct from not passing timezone at all', () {
      final fixed = RepeatRule(
        frequency: RepeatFrequency.daily,
        followsLocalTime: false,
        timezone: 'America/Los_Angeles',
      );

      final untouched = fixed.copyWith(interval: 2);
      expect(untouched.timezone, 'America/Los_Angeles');

      final cleared = fixed.copyWith(followsLocalTime: true, timezone: null);
      expect(cleared.followsLocalTime, isTrue);
      expect(cleared.timezone, isNull);
    });
  });

  group('nextRuleOccurrence - fixed timezone', () {
    test('a fixed daily rule advances the wall-clock time in its own '
        'anchor zone, returned as a TZDateTime in that zone', () {
      final from = DateTime(2026, 1, 1, 9); // some wall-clock 9am
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        followsLocalTime: false,
        timezone: 'America/Los_Angeles',
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: DateTime(2026, 1, 1, 10),
      );

      expect(result, isNotNull);
      final reminderAt = result!.reminderAt;
      expect(reminderAt, isA<tz.TZDateTime>());
      final tzResult = reminderAt as tz.TZDateTime;
      expect(tzResult.location.name, 'America/Los_Angeles');
      expect(tzResult.year, 2026);
      expect(tzResult.month, 1);
      expect(tzResult.day, 2);
      expect(tzResult.hour, 9);
      expect(tzResult.minute, 0);
    });

    test('stays anchored to the same zone across multiple catch-up '
        'cycles', () {
      final from = DateTime(2026, 1, 1, 9);
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        followsLocalTime: false,
        timezone: 'America/Los_Angeles',
      );
      // 3+ days later, forcing nextRuleOccurrence to loop several times.
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: DateTime(2026, 1, 4, 15),
      );

      final tzResult = result!.reminderAt as tz.TZDateTime;
      expect(tzResult.location.name, 'America/Los_Angeles');
      expect(tzResult.hour, 9);
      expect(tzResult.minute, 0);
    });

    test('a fixed monthly rule stays anchored to its zone too - the '
        'literal DateTime(...) construction monthly/yearly use would '
        'otherwise silently drop the anchor', () {
      final from = DateTime(2026, 1, 31, 9);
      final rule = RepeatRule(
        frequency: RepeatFrequency.monthly,
        followsLocalTime: false,
        timezone: 'America/Los_Angeles',
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: from.add(const Duration(hours: 1)),
      );

      final tzResult = result!.reminderAt as tz.TZDateTime;
      expect(tzResult.location.name, 'America/Los_Angeles');
      // Same out-of-range-day normalization as the unanchored test above.
      expect(
        tzResult,
        tz.TZDateTime(tz.getLocation('America/Los_Angeles'), 2026, 3, 3, 9),
      );
    });

    test('a rule that follows local time never becomes a TZDateTime', () {
      final from = DateTime(2026, 1, 1, 9);
      final rule = RepeatRule(frequency: RepeatFrequency.daily);
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: DateTime(2026, 1, 1, 10),
      );

      expect(result!.reminderAt, isNot(isA<tz.TZDateTime>()));
    });

    test('an unrecognized zone id degrades to local-time-for-this-advance '
        'rather than throwing', () {
      final from = DateTime(2026, 1, 1, 9);
      final rule = RepeatRule(
        frequency: RepeatFrequency.daily,
        followsLocalTime: false,
        timezone: 'Not/A_Real_Zone',
      );

      expect(
        () => nextRuleOccurrence(from, 1, rule, now: DateTime(2026, 1, 1, 10)),
        returnsNormally,
      );
      final result = nextRuleOccurrence(
        from,
        1,
        rule,
        now: DateTime(2026, 1, 1, 10),
      );
      expect(result!.reminderAt, DateTime(2026, 1, 2, 9));
    });

    // America/Los_Angeles springs forward on 2026-03-08 (2am -> 3am, so
    // 2:00-2:59am that day doesn't exist) and falls back on 2026-11-01
    // (2am -> 1am, so 1:00-1:59am that day happens twice). Confirmed via a
    // standalone probe of tz.TZDateTime's own constructor (not something
    // this app's code controls): a nonexistent wall-clock time is shifted
    // forward by the gap rather than rejected, and an ambiguous one
    // resolves to its *earlier* occurrence (the pre-transition UTC
    // offset) - deterministic either way, never a throw. These tests lock
    // in that a fixed-zone reminder landing on exactly one of those two
    // days rides along with whatever tz.TZDateTime itself decides, rather
    // than crashing Dismiss or silently losing the reminder.
    group('DST transitions (fixed zone)', () {
      test('a fixed daily reminder whose time falls in the spring-forward '
          'gap does not throw - it normalizes forward by the gap, same as '
          'a bare tz.TZDateTime construction would', () {
        // The day before the transition, at a time that lands inside
        // the following day's nonexistent 2:00-2:59am gap.
        final from = DateTime(2026, 3, 7, 2, 30);
        final rule = RepeatRule(
          frequency: RepeatFrequency.daily,
          followsLocalTime: false,
          timezone: 'America/Los_Angeles',
        );

        expect(
          () => nextRuleOccurrence(from, 1, rule, now: DateTime(2026, 3, 7, 3)),
          returnsNormally,
        );
        final result = nextRuleOccurrence(
          from,
          1,
          rule,
          now: DateTime(2026, 3, 7, 3),
        );

        final tzResult = result!.reminderAt as tz.TZDateTime;
        expect(tzResult.year, 2026);
        expect(tzResult.month, 3);
        expect(tzResult.day, 8);
        // 2:30am doesn't exist that day - shifted forward by the gap.
        expect(tzResult.hour, 3);
        expect(tzResult.minute, 30);
      });

      test('a fixed daily reminder whose time falls in the fall-back '
          'overlap does not throw - it resolves to that time\'s earlier '
          '(pre-transition) occurrence', () {
        final from = DateTime(2026, 10, 31, 1, 30);
        final rule = RepeatRule(
          frequency: RepeatFrequency.daily,
          followsLocalTime: false,
          timezone: 'America/Los_Angeles',
        );

        expect(
          () =>
              nextRuleOccurrence(from, 1, rule, now: DateTime(2026, 10, 31, 2)),
          returnsNormally,
        );
        final result = nextRuleOccurrence(
          from,
          1,
          rule,
          now: DateTime(2026, 10, 31, 2),
        );

        final tzResult = result!.reminderAt as tz.TZDateTime;
        expect(tzResult.year, 2026);
        expect(tzResult.month, 11);
        expect(tzResult.day, 1);
        expect(tzResult.hour, 1);
        expect(tzResult.minute, 30);
        // The earlier of the two 1:30am instants that day - matches
        // the offset still in effect just before the transition, not
        // the one that takes over after it.
        expect(tzResult.timeZoneOffset, const Duration(hours: -7));
      });
    });
  });
}

/// Mirrors what Note.toMap/toPocketBase actually do to persist a
/// RepeatRule - jsonEncode of the rule's own toJson().
String _encode(RepeatRule rule) => jsonEncode(rule.toJson());
