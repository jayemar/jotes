import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/repeat_rule.dart';
import 'package:jotes/screens/custom_recurrence_screen.dart';

Future<RepeatRule?> _pumpAndOpen(
  WidgetTester tester, {
  RepeatRule? initialRule,
  required DateTime startDate,
}) async {
  RepeatRule? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            key: const Key('open'),
            onPressed: () async {
              result = await Navigator.push<RepeatRule>(
                context,
                MaterialPageRoute(
                  builder: (_) => CustomRecurrenceScreen(
                    initialRule: initialRule,
                    startDate: startDate,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _done(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('custom_recurrence_done')));
  await tester.pumpAndSettle();
}

void main() {
  // A Tuesday, so the "defaults to the reminder's own weekday" behavior has
  // a single unambiguous expected weekday across every test below.
  final startDate = DateTime(2026, 8, 25, 9);

  testWidgets('with no initial rule, defaults to weekly, interval 1, on '
      'the reminder\'s own weekday, never-ending', (tester) async {
    RepeatRule? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('open'),
              onPressed: () async {
                result = await Navigator.push<RepeatRule>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CustomRecurrenceScreen(startDate: startDate),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    await _done(tester);

    expect(
      result,
      RepeatRule(
        frequency: RepeatFrequency.weekly,
        weekdays: {DateTime.tuesday},
      ),
    );
  });

  testWidgets('starting from an existing custom rule pre-fills interval, '
      'frequency, weekdays, and end condition', (tester) async {
    final initialRule = RepeatRule(
      frequency: RepeatFrequency.weekly,
      interval: 3,
      weekdays: const {DateTime.monday, DateTime.friday},
      end: const RepeatEndAfterCount(6),
    );

    RepeatRule? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('open'),
              onPressed: () async {
                result = await Navigator.push<RepeatRule>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomRecurrenceScreen(
                      initialRule: initialRule,
                      startDate: startDate,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(Key('custom_recurrence_weekday_${DateTime.monday}')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(Key('custom_recurrence_weekday_${DateTime.friday}')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(Key('custom_recurrence_weekday_${DateTime.tuesday}')),
          )
          .selected,
      isFalse,
    );

    await _done(tester);

    expect(result, initialRule);
  });

  testWidgets('entering an interval and confirming carries it through to '
      'the resulting rule', (tester) async {
    RepeatRule? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('open'),
              onPressed: () async {
                result = await Navigator.push<RepeatRule>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CustomRecurrenceScreen(startDate: startDate),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('custom_recurrence_interval')),
      '2',
    );
    await tester.pumpAndSettle();
    await _done(tester);

    expect(result?.interval, 2);
  });

  testWidgets('the "Repeat on" weekday chips are only shown for a weekly '
      'frequency', (tester) async {
    await _pumpAndOpen(
      tester,
      initialRule: RepeatRule.preset(RepeatFrequency.weekly),
      startDate: startDate,
    );

    expect(
      find.byKey(Key('custom_recurrence_weekday_${DateTime.monday}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('custom_recurrence_frequency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('custom_recurrence_weekday_${DateTime.monday}')),
      findsNothing,
    );
  });

  testWidgets('toggling a weekday chip on adds it, and the last selected '
      'weekday cannot be toggled off (a weekly rule needs at least one)', (
    tester,
  ) async {
    await _pumpAndOpen(
      tester,
      initialRule: RepeatRule.preset(RepeatFrequency.weekly),
      startDate: startDate,
    );

    // Starts with only the reminder's own weekday (Tuesday) selected -
    // RepeatRule.preset has empty weekdays, and CustomRecurrenceScreen
    // falls back to {startDate.weekday} in that case.
    await tester.tap(
      find.byKey(Key('custom_recurrence_weekday_${DateTime.thursday}')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilterChip>(
            find.byKey(Key('custom_recurrence_weekday_${DateTime.thursday}')),
          )
          .selected,
      isTrue,
    );

    // Now two are selected - removing one should succeed.
    await tester.tap(
      find.byKey(Key('custom_recurrence_weekday_${DateTime.tuesday}')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilterChip>(
            find.byKey(Key('custom_recurrence_weekday_${DateTime.tuesday}')),
          )
          .selected,
      isFalse,
    );

    // Only Thursday left - trying to remove it too should be a no-op.
    await tester.tap(
      find.byKey(Key('custom_recurrence_weekday_${DateTime.thursday}')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilterChip>(
            find.byKey(Key('custom_recurrence_weekday_${DateTime.thursday}')),
          )
          .selected,
      isTrue,
    );
  });

  group('the Ends section', () {
    testWidgets('defaults to Never for a fresh rule', (tester) async {
      RepeatRule? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const Key('open'),
                onPressed: () async {
                  result = await Navigator.push<RepeatRule>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CustomRecurrenceScreen(startDate: startDate),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      await _done(tester);

      expect(result?.end, const RepeatEndNever());
    });

    testWidgets('choosing "On" and confirming a date produces a '
        'RepeatEndOnDate', (tester) async {
      RepeatRule? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const Key('open'),
                onPressed: () async {
                  result = await Navigator.push<RepeatRule>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CustomRecurrenceScreen(startDate: startDate),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('custom_recurrence_end_on_date')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('custom_recurrence_end_date_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('custom_recurrence_end_date_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await _done(tester);

      expect(result?.end, isA<RepeatEndOnDate>());
    });

    testWidgets('choosing "After" and entering a count produces a '
        'RepeatEndAfterCount', (tester) async {
      RepeatRule? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const Key('open'),
                onPressed: () async {
                  result = await Navigator.push<RepeatRule>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CustomRecurrenceScreen(startDate: startDate),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('custom_recurrence_end_after_count')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('custom_recurrence_end_count')),
        '5',
      );
      await tester.pumpAndSettle();

      await _done(tester);

      expect(result?.end, const RepeatEndAfterCount(5));
    });
  });

  testWidgets('the close (X) button pops with null, without a rule', (
    tester,
  ) async {
    RepeatRule? result;
    var pushed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('open'),
              onPressed: () async {
                pushed = true;
                result = await Navigator.push<RepeatRule>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CustomRecurrenceScreen(startDate: startDate),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(pushed, isTrue);
    expect(result, isNull);
  });
}
