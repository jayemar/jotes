import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/providers/sync_provider.dart';
import 'package:jotes/screens/sync_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: SyncSettingsScreen())),
  );
  await tester.pumpAndSettle();
}

/// Records resync() calls instead of hitting a real server - build() jumps
/// straight to a "connected" state so _buildConnected (and its "Sync now"
/// button) renders without going through the real _restore()/PbService
/// flow.
class _RecordingSyncNotifier extends SyncNotifier {
  int resyncCalls = 0;
  Completer<void>? resyncGate;

  @override
  SyncState build() => const SyncState(
    status: SyncStatus.connected,
    serverUrl: 'http://example.com',
    userEmail: 'me@example.com',
  );

  @override
  Future<void> resync() async {
    resyncCalls++;
    final gate = resyncGate;
    if (gate != null) await gate.future;
  }
}

/// Goes straight from disconnected to whatever [connect] is told to
/// resolve to, instead of hitting a real PbService - lets tests drive the
/// form submission flow without a real server.
class _ConnectingSyncNotifier extends SyncNotifier {
  _ConnectingSyncNotifier({required this.succeeds});
  final bool succeeds;

  @override
  SyncState build() => SyncState.initial;

  @override
  Future<void> connect({
    required String url,
    required String email,
    required String password,
    required bool register,
  }) async {
    state = succeeds
        ? const SyncState(
            status: SyncStatus.connected,
            serverUrl: 'http://example.com',
            userEmail: 'me@example.com',
          )
        : const SyncState(status: SyncStatus.error, errorMessage: 'nope');
  }
}

/// Pushes SyncSettingsScreen on top of a distinguishable placeholder route
/// (rather than as the app's only route), so a successful submit's
/// Navigator.pop has somewhere observable to land back on - mirrors how
/// notes_screen.dart actually reaches this screen, always via a push.
Future<void> _pumpPushedOntoPlaceholder(
  WidgetTester tester,
  SyncNotifier notifier,
) async {
  final container = ProviderContainer(
    overrides: [syncProvider.overrideWith(() => notifier)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open_sync_settings'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
                ),
                child: const Text('Main notes screen'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open_sync_settings')));
  await tester.pumpAndSettle();
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('sync_url_field')),
    'http://example.com',
  );
  await tester.enterText(
    find.byKey(const Key('sync_email_field')),
    'me@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('sync_password_field')),
    'hunter2',
  );
  await tester.tap(find.byKey(const Key('sync_submit_button')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // SyncNotifier.build() fires off PbService.instance.restore(), which
    // reads SharedPreferences - unmocked, that throws under flutter_test.
    // No stored server URL means it returns early and the screen renders
    // its normal disconnected/form state, which is all these tests need.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the password field starts obscured', (tester) async {
    await _pumpScreen(tester);

    final field = tester.widget<TextField>(
      find.byKey(const Key('sync_password_field')),
    );
    expect(field.obscureText, isTrue);
  });

  testWidgets(
    'tapping the visibility toggle reveals the password, tapping it again '
    'hides it',
    (tester) async {
      await _pumpScreen(tester);

      final toggle = find.byKey(const Key('sync_password_visibility_toggle'));

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('sync_password_field')))
            .obscureText,
        isFalse,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('sync_password_field')))
            .obscureText,
        isTrue,
      );
    },
  );

  testWidgets(
    'the email and password fields carry autofill hints, so a password '
    'manager can recognize and offer to fill/save them',
    (tester) async {
      await _pumpScreen(tester);

      final email = tester.widget<TextField>(
        find.byKey(const Key('sync_email_field')),
      );
      final password = tester.widget<TextField>(
        find.byKey(const Key('sync_password_field')),
      );

      expect(email.autofillHints, contains(AutofillHints.email));
      expect(password.autofillHints, contains(AutofillHints.password));
    },
  );

  testWidgets(
    'the email and password fields sit inside a shared AutofillGroup, so '
    'the platform treats them as one form rather than two unrelated '
    'fields',
    (tester) async {
      await _pumpScreen(tester);

      final group = find.byType(AutofillGroup);
      expect(group, findsOneWidget);
      expect(
        find.descendant(
          of: group,
          matching: find.byKey(const Key('sync_email_field')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: group,
          matching: find.byKey(const Key('sync_password_field')),
        ),
        findsOneWidget,
      );
    },
  );

  group('Sync now (see SyncNotifier.resync)', () {
    Future<void> pumpConnected(
      WidgetTester tester,
      _RecordingSyncNotifier notifier,
    ) async {
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SyncSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'tapping "Sync now" triggers a resync and confirms with a snackbar',
      (tester) async {
        final notifier = _RecordingSyncNotifier();
        await pumpConnected(tester, notifier);

        await tester.tap(find.byKey(const Key('sync_now_button')));
        await tester.pumpAndSettle();

        expect(notifier.resyncCalls, 1);
        expect(find.text('Synced'), findsOneWidget);
      },
    );

    testWidgets(
      'shows a progress indicator and disables the button while a resync '
      'is in flight',
      (tester) async {
        final notifier = _RecordingSyncNotifier()
          ..resyncGate = Completer<void>();
        await pumpConnected(tester, notifier);

        await tester.tap(find.byKey(const Key('sync_now_button')));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('sync_now_button')))
              .onPressed,
          isNull,
        );

        notifier.resyncGate!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });

  group('connected state layout', () {
    Future<void> pumpConnected(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => _RecordingSyncNotifier())],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SyncSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      '"Connected to:" and the server URL are on their own separate lines',
      (tester) async {
        await pumpConnected(tester);

        expect(find.text('Connected to:'), findsOneWidget);
        expect(find.text('http://example.com'), findsOneWidget);
      },
    );

    testWidgets(
      'the Sync now and Disconnect buttons sit side by side at the same '
      'width',
      (tester) async {
        await pumpConnected(tester);

        final syncNowBox = tester.getSize(
          find.byKey(const Key('sync_now_button')),
        );
        final disconnectBox = tester.getSize(
          find.byKey(const Key('sync_disconnect_button')),
        );

        expect(syncNowBox.width, disconnectBox.width);
        // Side by side, not stacked - same vertical position.
        expect(
          tester.getTopLeft(find.byKey(const Key('sync_now_button'))).dy,
          tester.getTopLeft(find.byKey(const Key('sync_disconnect_button'))).dy,
        );
      },
    );
  });

  group('submitting the connect form', () {
    testWidgets(
      'a successful connect pops back to whatever screen pushed this one, '
      'rather than staying on the "Connected to:" summary',
      (tester) async {
        await _pumpPushedOntoPlaceholder(
          tester,
          _ConnectingSyncNotifier(succeeds: true),
        );

        await _fillAndSubmit(tester);

        expect(find.byType(SyncSettingsScreen), findsNothing);
        expect(find.text('Main notes screen'), findsOneWidget);
      },
    );

    testWidgets(
      'a failed connect stays on this screen, showing the error rather '
      'than popping',
      (tester) async {
        await _pumpPushedOntoPlaceholder(
          tester,
          _ConnectingSyncNotifier(succeeds: false),
        );

        await _fillAndSubmit(tester);

        expect(find.byType(SyncSettingsScreen), findsOneWidget);
        expect(find.textContaining('Could not connect'), findsOneWidget);
      },
    );
  });
}
