import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/services/share_intent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jayemar.jotes/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('parseSharedContent', () {
    test('parses text and subject from the native payload', () {
      final shared = parseSharedContent({
        'text': 'https://example.com',
        'subject': 'Example page',
      });

      expect(shared!.text, 'https://example.com');
      expect(shared.subject, 'Example page');
    });

    test('subject is optional - a sending app that omits it still parses', () {
      final shared = parseSharedContent({'text': 'just some text'});

      expect(shared!.text, 'just some text');
      expect(shared.subject, isNull);
    });

    test('returns null for anything that is not a Map', () {
      expect(parseSharedContent('just a string'), isNull);
      expect(parseSharedContent(null), isNull);
    });

    test('returns null when text is missing or empty', () {
      expect(parseSharedContent({'subject': 'no text key'}), isNull);
      expect(parseSharedContent({'text': ''}), isNull);
    });
  });

  group('ShareIntentService.getInitialSharedText', () {
    test('returns the parsed share from a cold-start launch intent', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getInitialSharedText');
        return {'text': 'shared body', 'subject': 'shared title'};
      });

      final shared = await ShareIntentService.instance.getInitialSharedText();

      expect(shared!.text, 'shared body');
      expect(shared.subject, 'shared title');
    });

    test('returns null when the app was not launched by a share', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);

      expect(await ShareIntentService.instance.getInitialSharedText(), isNull);
    });

    test('returns null when the platform call throws, rather than '
        'propagating the error', () async {
      messenger.setMockMethodCallHandler(channel, (call) {
        throw PlatformException(code: 'error');
      });

      expect(await ShareIntentService.instance.getInitialSharedText(), isNull);
    });
  });

  group('ShareIntentService.onSharedText', () {
    test('fires when the native side calls onSharedText - a share arriving '
        'while jotes is already running', () async {
      ShareIntentService.instance.initialize();
      final events = <SharedContent>[];
      final subscription = ShareIntentService.instance.onSharedText.listen(
        events.add,
      );
      addTearDown(subscription.cancel);

      final call = const MethodCall('onSharedText', {
        'text': 'a warm share',
        'subject': 'warm subject',
      });
      final envelope = const StandardMethodCodec().encodeMethodCall(call);
      await messenger.handlePlatformMessage(channel.name, envelope, (_) {});

      expect(events, hasLength(1));
      expect(events.single.text, 'a warm share');
      expect(events.single.subject, 'warm subject');
    });
  });
}
