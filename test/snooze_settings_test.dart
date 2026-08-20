import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/services/pb_service.dart';
import 'package:jotes/services/snooze_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('getMode', () {
    test('defaults to 1 hour when nothing has been saved', () async {
      expect(await SnoozeSettings.instance.getMode(), SnoozeMode.oneHour);
    });

    test('returns whatever was last saved via setMode', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.thirtyMinutes);

      expect(await SnoozeSettings.instance.getMode(), SnoozeMode.thirtyMinutes);
    });

    test('falls back to the default if the stored value is unrecognized '
        '(e.g. a removed enum value from an older install)', () async {
      SharedPreferences.setMockInitialValues({
        'snooze_mode': 'no_longer_a_real_option',
      });

      expect(await SnoozeSettings.instance.getMode(), SnoozeMode.oneHour);
    });
  });

  group('custom delay minutes', () {
    test('defaults to 60 minutes when nothing has been saved', () async {
      expect(await SnoozeSettings.instance.getCustomDelayMinutes(), 60);
    });

    test('returns whatever was last saved via setCustomDelayMinutes', () async {
      await SnoozeSettings.instance.setCustomDelayMinutes(90);

      expect(await SnoozeSettings.instance.getCustomDelayMinutes(), 90);
    });

    test('clamps a zero or negative value up to 1 minute', () async {
      await SnoozeSettings.instance.setCustomDelayMinutes(0);
      expect(await SnoozeSettings.instance.getCustomDelayMinutes(), 1);

      await SnoozeSettings.instance.setCustomDelayMinutes(-30);
      expect(await SnoozeSettings.instance.getCustomDelayMinutes(), 1);
    });

    test('clamps an excessively large value down to a week', () async {
      await SnoozeSettings.instance.setCustomDelayMinutes(999999);

      expect(
        await SnoozeSettings.instance.getCustomDelayMinutes(),
        7 * 24 * 60,
      );
    });
  });

  group('time of day minutes', () {
    test(
      'defaults to 9:00am (540 minutes) when nothing has been saved',
      () async {
        expect(await SnoozeSettings.instance.getTimeOfDayMinutes(), 9 * 60);
      },
    );

    test('returns whatever was last saved via setTimeOfDayMinutes', () async {
      await SnoozeSettings.instance.setTimeOfDayMinutes(18 * 60 + 30);

      expect(await SnoozeSettings.instance.getTimeOfDayMinutes(), 18 * 60 + 30);
    });

    test('clamps to a valid time-of-day range', () async {
      await SnoozeSettings.instance.setTimeOfDayMinutes(-5);
      expect(await SnoozeSettings.instance.getTimeOfDayMinutes(), 0);

      await SnoozeSettings.instance.setTimeOfDayMinutes(24 * 60 + 5);
      expect(await SnoozeSettings.instance.getTimeOfDayMinutes(), 24 * 60 - 1);
    });
  });

  group('resolveNext', () {
    final now = DateTime(2026, 7, 30, 10);

    test('fifteenMinutes adds 15 minutes to now', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.fifteenMinutes);

      expect(
        await SnoozeSettings.instance.resolveNext(now: now),
        DateTime(2026, 7, 30, 10, 15),
      );
    });

    test('thirtyMinutes adds 30 minutes to now', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.thirtyMinutes);

      expect(
        await SnoozeSettings.instance.resolveNext(now: now),
        DateTime(2026, 7, 30, 10, 30),
      );
    });

    test('oneHour adds 1 hour to now', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.oneHour);

      expect(
        await SnoozeSettings.instance.resolveNext(now: now),
        DateTime(2026, 7, 30, 11),
      );
    });

    test('threeHours adds 3 hours to now', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.threeHours);

      expect(
        await SnoozeSettings.instance.resolveNext(now: now),
        DateTime(2026, 7, 30, 13),
      );
    });

    test('custom adds the configured custom delay to now', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.custom);
      await SnoozeSettings.instance.setCustomDelayMinutes(135);

      expect(
        await SnoozeSettings.instance.resolveNext(now: now),
        DateTime(2026, 7, 30, 12, 15),
      );
    });

    test('timeOfDay resolves to later today when the configured time has not '
        'happened yet', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.timeOfDay);
      await SnoozeSettings.instance.setTimeOfDayMinutes(18 * 60); // 6pm

      expect(
        await SnoozeSettings.instance.resolveNext(now: now),
        DateTime(2026, 7, 30, 18),
      );
    });

    test('timeOfDay resolves to tomorrow when the configured time has already '
        'passed today', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.timeOfDay);
      await SnoozeSettings.instance.setTimeOfDayMinutes(8 * 60); // 8am

      expect(
        await SnoozeSettings.instance.resolveNext(now: now),
        DateTime(2026, 7, 31, 8),
      );
    });

    test('timeOfDay resolves to tomorrow when the configured time is exactly '
        'now', () async {
      await SnoozeSettings.instance.setMode(SnoozeMode.timeOfDay);
      await SnoozeSettings.instance.setTimeOfDayMinutes(10 * 60); // 10am

      expect(
        await SnoozeSettings.instance.resolveNext(now: now),
        DateTime(2026, 7, 31, 10),
      );
    });
  });

  group('pullFromServer', () {
    test('is a harmless no-op when not logged into a sync server - the '
        'local value (default or previously saved) is left untouched',
        () async {
      // PbService.instance.userData is null whenever no PocketBase client
      // has ever been configured (see PbService.connect/restore) - true by
      // default in a plain test run with no server connection made.
      expect(PbService.instance.userData, isNull);

      await SnoozeSettings.instance.pullFromServer();

      expect(await SnoozeSettings.instance.getMode(), SnoozeMode.oneHour);
    });
  });
}
