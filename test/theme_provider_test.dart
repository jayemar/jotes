import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to system theme when nothing is persisted', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('setThemeMode updates state immediately', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.dark);

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('setThemeMode persists the choice for a freshly-built notifier',
      () async {
    final container1 = ProviderContainer();
    await container1
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.light);
    container1.dispose();

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    // NotifierProviders build lazily on first read - read once to trigger
    // build() (which kicks off an unawaited async load from
    // SharedPreferences), then give that load a turn to complete.
    container2.read(themeModeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container2.read(themeModeProvider), ThemeMode.light);
  });
}
