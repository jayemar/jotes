import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/screens/sync_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: SyncSettingsScreen())),
  );
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
}
