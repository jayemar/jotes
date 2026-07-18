import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/providers/appearance_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to the default font and medium text size when nothing is '
      'persisted', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(appearanceProvider);
    expect(state.font, AppFont.defaultFont);
    expect(state.textSize, TextSizeOption.medium);
  });

  test('setFont updates state immediately', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(appearanceProvider.notifier).setFont(AppFont.serif);

    expect(container.read(appearanceProvider).font, AppFont.serif);
  });

  test('setTextSize updates state immediately without disturbing the '
      'font choice', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(appearanceProvider.notifier).setFont(AppFont.rounded);
    await container
        .read(appearanceProvider.notifier)
        .setTextSize(TextSizeOption.large);

    final state = container.read(appearanceProvider);
    expect(state.font, AppFont.rounded);
    expect(state.textSize, TextSizeOption.large);
  });

  test('setFont and setTextSize persist for a freshly-built notifier',
      () async {
    final container1 = ProviderContainer();
    await container1
        .read(appearanceProvider.notifier)
        .setFont(AppFont.monospace);
    await container1
        .read(appearanceProvider.notifier)
        .setTextSize(TextSizeOption.extraLarge);
    container1.dispose();

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    // NotifierProviders build lazily on first read - read once to trigger
    // build() (which kicks off an unawaited async load from
    // SharedPreferences), then give that load a turn to complete.
    container2.read(appearanceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container2.read(appearanceProvider);
    expect(state.font, AppFont.monospace);
    expect(state.textSize, TextSizeOption.extraLarge);
  });
}
