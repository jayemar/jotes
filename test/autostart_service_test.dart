import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/services/autostart_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jayemar.jotes/autostart');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('isKnownRestrictiveManufacturer returns the native result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isKnownRestrictiveManufacturer');
      return true;
    });

    expect(
      await AutostartService.instance.isKnownRestrictiveManufacturer(),
      isTrue,
    );
  });

  test('isKnownRestrictiveManufacturer returns false when the platform call '
      'throws, rather than propagating the error', () async {
    messenger.setMockMethodCallHandler(channel, (call) {
      throw PlatformException(code: 'error');
    });

    expect(
      await AutostartService.instance.isKnownRestrictiveManufacturer(),
      isFalse,
    );
  });

  test('openAutostartSettings invokes the native method', () async {
    var invoked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openAutostartSettings') invoked = true;
      return null;
    });

    await AutostartService.instance.openAutostartSettings();

    expect(invoked, isTrue);
  });

  test(
    'openAutostartSettings does not throw when the platform call fails',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) {
        throw PlatformException(code: 'error');
      });

      await expectLater(
        AutostartService.instance.openAutostartSettings(),
        completes,
      );
    },
  );
}
