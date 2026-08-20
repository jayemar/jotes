import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/providers/theme_provider.dart';
import 'package:jotes/screens/settings_screen.dart';
import 'package:jotes/services/periodic_refresh_settings.dart';
import 'package:jotes/services/snooze_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpSettingsScreen(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Opens a DropdownMenu and taps the entry matching [label]. Unlike the old
/// DropdownButton, DropdownMenu's closed field also displays the current
/// selection as literal text, so there can be two matches once the menu is
/// open - `.last` reliably targets the freshly-opened menu entry, added
/// later in the tree.
Future<void> _choose(WidgetTester tester, Key dropdownKey, String label) async {
  await tester.tap(find.byKey(dropdownKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'shows a theme dropdown defaulting to System, with Light and Dark '
    'selectable when opened',
    (tester) async {
      final container = await _pumpSettingsScreen(tester);

      expect(find.byKey(const Key('theme_dropdown')), findsOneWidget);
      // DropdownMenu pre-builds its entries (for width measurement) even
      // while closed, so the initially-selected entry's text can match both
      // that hidden entry and the closed field's own displayed text -
      // findsWidgets (at least one) is what matters, not an exact count of
      // Flutter's internal representation.
      expect(find.text('System'), findsWidgets);
      expect(container.read(themeModeProvider), ThemeMode.system);

      await tester.tap(find.byKey(const Key('theme_dropdown')));
      await tester.pumpAndSettle();

      expect(find.text('Light'), findsWidgets);
      expect(find.text('Dark'), findsWidgets);
    },
  );

  testWidgets('selecting Dark updates the theme provider', (tester) async {
    final container = await _pumpSettingsScreen(tester);
    await _choose(tester, const Key('theme_dropdown'), 'Dark');
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets(
    'selecting Light then System updates the theme provider each time',
    (tester) async {
      final container = await _pumpSettingsScreen(tester);
      await _choose(tester, const Key('theme_dropdown'), 'Light');
      expect(container.read(themeModeProvider), ThemeMode.light);
      await _choose(tester, const Key('theme_dropdown'), 'System');
      expect(container.read(themeModeProvider), ThemeMode.system);
    },
  );

  testWidgets('shows Font and Text size dropdowns', (tester) async {
    await _pumpSettingsScreen(tester);

    expect(find.byKey(const Key('font_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('text_size_dropdown')), findsOneWidget);
    // DropdownMenu pre-builds its entries (for width measurement) even
    // while closed, so a font entry with a custom labelWidget can match
    // both that hidden entry and the closed field's own displayed text -
    // findsWidgets (at least one) is what actually matters here, not an
    // exact count of Flutter's internal representation.
    expect(find.text('Default'), findsWidgets);
    expect(find.text('Medium'), findsWidgets);
  });

  group('snooze setting', () {
    testWidgets('shows a snooze mode dropdown defaulting to 1 hour', (
      tester,
    ) async {
      await _pumpSettingsScreen(tester);

      expect(find.byKey(const Key('snooze_mode_dropdown')), findsOneWidget);
      expect(find.text('1 hour'), findsWidgets);
      expect(find.byKey(const Key('snooze_custom_hours_field')), findsNothing);
      expect(find.byKey(const Key('snooze_time_of_day_tile')), findsNothing);
    });

    testWidgets('reflects a previously-saved mode on load', (tester) async {
      SharedPreferences.setMockInitialValues({
        'snooze_mode': SnoozeMode.threeHours.name,
      });

      await _pumpSettingsScreen(tester);

      expect(find.text('3 hours'), findsWidgets);
    });

    testWidgets('selecting a fixed preset persists it to SnoozeSettings', (
      tester,
    ) async {
      await _pumpSettingsScreen(tester);

      await _choose(tester, const Key('snooze_mode_dropdown'), '30 minutes');

      expect(await SnoozeSettings.instance.getMode(), SnoozeMode.thirtyMinutes);
    });

    testWidgets(
      'selecting Custom delay reveals hours/minutes fields, and typing in '
      'them persists the delay',
      (tester) async {
        await _pumpSettingsScreen(tester);

        await _choose(
          tester,
          const Key('snooze_mode_dropdown'),
          'Custom delay',
        );

        final hoursField = find.byKey(const Key('snooze_custom_hours_field'));
        final minutesField = find.byKey(
          const Key('snooze_custom_minutes_field'),
        );
        expect(hoursField, findsOneWidget);
        expect(minutesField, findsOneWidget);

        await tester.enterText(hoursField, '2');
        await tester.enterText(minutesField, '15');
        await tester.pumpAndSettle();

        expect(
          await SnoozeSettings.instance.getCustomDelayMinutes(),
          2 * 60 + 15,
        );
      },
    );

    testWidgets(
      'reflects a previously-saved custom delay in the hours/minutes fields',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'snooze_mode': SnoozeMode.custom.name,
          'snooze_custom_delay_minutes': 90,
        });

        await _pumpSettingsScreen(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('snooze_custom_hours_field')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('snooze_custom_minutes_field')),
            matching: find.text('30'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('selecting Time of day reveals a time picker tile showing the '
        'configured time', (tester) async {
      SharedPreferences.setMockInitialValues({
        'snooze_time_of_day_minutes': 18 * 60,
      });
      await _pumpSettingsScreen(tester);

      await _choose(tester, const Key('snooze_mode_dropdown'), 'Time of day');

      final tile = find.byKey(const Key('snooze_time_of_day_tile'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.textContaining('6:00')),
        findsOneWidget,
      );
    });

    testWidgets('tapping the Time of day tile opens a time picker', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'snooze_mode': SnoozeMode.timeOfDay.name,
      });
      await _pumpSettingsScreen(tester);

      await tester.tap(find.byKey(const Key('snooze_time_of_day_tile')));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsOneWidget);
    });
  });

  group('reminder auto-start setting', () {
    const autostartChannel = MethodChannel('com.jayemar.jotes/autostart');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(autostartChannel, null);
    });

    testWidgets(
      'is hidden on a non-restrictive manufacturer (or when the check is '
      'unavailable, as in a plain test run)',
      (tester) async {
        messenger.setMockMethodCallHandler(autostartChannel, (call) async {
          if (call.method == 'isKnownRestrictiveManufacturer') return false;
          return null;
        });
        await _pumpSettingsScreen(tester);

        expect(find.byKey(const Key('autostart_setting')), findsNothing);
      },
    );

    testWidgets(
      'is shown on a restrictive manufacturer and its tap opens the native '
      'autostart settings',
      (tester) async {
        var opened = false;
        messenger.setMockMethodCallHandler(autostartChannel, (call) async {
          if (call.method == 'isKnownRestrictiveManufacturer') return true;
          if (call.method == 'openAutostartSettings') opened = true;
          return null;
        });
        await _pumpSettingsScreen(tester);

        // The tile can start out below the ListView's build/cache extent
        // now that there's more content above it (see
        // _PeriodicRefreshSetting) - drag the list directly by its own key
        // rather than find.byType(Scrollable), which also matches
        // DropdownMenu's own hidden pre-built entries elsewhere on this
        // screen and so can't identify the settings list unambiguously.
        await tester.drag(
          find.byKey(const Key('settings_list')),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();

        final tile = find.byKey(const Key('autostart_setting'));
        expect(tile, findsOneWidget);

        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(opened, isTrue);
      },
    );
  });

  group('background refresh setting', () {
    const periodicRefreshChannel = MethodChannel(
      'com.jayemar.jotes/periodic_refresh',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(periodicRefreshChannel, null);
    });

    testWidgets('defaults to on', (tester) async {
      messenger.setMockMethodCallHandler(
        periodicRefreshChannel,
        (call) async => null,
      );
      await _pumpSettingsScreen(tester);

      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('periodic_refresh_setting')),
      );
      expect(tile.value, isTrue);
    });

    testWidgets(
      'turning it off persists the choice and tells native to cancel the '
      'schedule immediately, not just on next launch',
      (tester) async {
        String? lastMethod;
        Object? lastArgs;
        messenger.setMockMethodCallHandler(periodicRefreshChannel, (
          call,
        ) async {
          lastMethod = call.method;
          lastArgs = call.arguments;
          return null;
        });
        await _pumpSettingsScreen(tester);

        await tester.tap(find.byKey(const Key('periodic_refresh_setting')));
        await tester.pumpAndSettle();

        final tile = tester.widget<SwitchListTile>(
          find.byKey(const Key('periodic_refresh_setting')),
        );
        expect(tile.value, isFalse);
        expect(lastMethod, 'setPeriodicRefreshEnabled');
        expect(lastArgs, false);
        expect(
          await PeriodicRefreshSettings.instance.isEnabled(),
          isFalse,
        );
      },
    );
  });
}
