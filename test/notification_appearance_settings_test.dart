import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/services/notification_appearance_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const soundsChannel = MethodChannel('com.jayemar.jotes/notification_sounds');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(soundsChannel, null);
  });

  group('systemSoundOptions', () {
    test('returns the native side\'s list, mapped to option objects', () async {
      messenger.setMockMethodCallHandler(soundsChannel, (call) async {
        expect(call.method, 'listNotificationSounds');
        return [
          {'uri': 'content://settings/system/notification_sound', 'title': 'Default'},
          {'uri': 'content://media/internal/audio/media/1', 'title': 'Chime'},
        ];
      });

      final options =
          await NotificationAppearanceSettings.instance.systemSoundOptions();

      expect(options, hasLength(2));
      expect(options[0].uri, 'content://settings/system/notification_sound');
      expect(options[0].title, 'Default');
      expect(options[1].uri, 'content://media/internal/audio/media/1');
      expect(options[1].title, 'Chime');
    });

    test('returns an empty list rather than throwing when the platform '
        'call is unavailable', () async {
      expect(
        await NotificationAppearanceSettings.instance.systemSoundOptions(),
        isEmpty,
      );
    });
  });

  group('per-note appearance', () {
    test('getForNote defaults to no sound and the default icon when '
        'nothing has been saved for this note', () async {
      final appearance = await NotificationAppearanceSettings.instance
          .getForNote('note-1');

      expect(appearance.soundUri, isNull);
      expect(appearance.soundTitle, isNull);
      expect(appearance.icon, NotificationIconOption.defaultIcon);
    });

    test('setForNote persists the choice, readable back via getForNote',
        () async {
      await NotificationAppearanceSettings.instance.setForNote(
        'note-1',
        const NoteNotificationAppearance(
          soundUri: 'content://media/internal/audio/media/1',
          soundTitle: 'Chime',
          icon: NotificationIconOption.bell,
        ),
      );

      final appearance = await NotificationAppearanceSettings.instance
          .getForNote('note-1');

      expect(
        appearance.soundUri,
        'content://media/internal/audio/media/1',
      );
      expect(appearance.soundTitle, 'Chime');
      expect(appearance.icon, NotificationIconOption.bell);
    });

    test('choices for different notes do not clobber each other', () async {
      await NotificationAppearanceSettings.instance.setForNote(
        'note-1',
        const NoteNotificationAppearance(icon: NotificationIconOption.bell),
      );
      await NotificationAppearanceSettings.instance.setForNote(
        'note-2',
        const NoteNotificationAppearance(icon: NotificationIconOption.star),
      );

      expect(
        (await NotificationAppearanceSettings.instance.getForNote('note-1'))
            .icon,
        NotificationIconOption.bell,
      );
      expect(
        (await NotificationAppearanceSettings.instance.getForNote('note-2'))
            .icon,
        NotificationIconOption.star,
      );
    });

    test('clearForNote removes a note\'s entry, reverting getForNote to '
        'the defaults', () async {
      await NotificationAppearanceSettings.instance.setForNote(
        'note-1',
        const NoteNotificationAppearance(icon: NotificationIconOption.bell),
      );

      await NotificationAppearanceSettings.instance.clearForNote('note-1');

      final appearance = await NotificationAppearanceSettings.instance
          .getForNote('note-1');
      expect(appearance.soundUri, isNull);
      expect(appearance.icon, NotificationIconOption.defaultIcon);
    });

    test('clearForNote for a note with no saved entry is a harmless no-op',
        () async {
      await expectLater(
        NotificationAppearanceSettings.instance.clearForNote('never-saved'),
        completes,
      );
    });

    test('falls back to the default icon if the stored value is '
        'unrecognized (e.g. a removed enum value from an older install)',
        () async {
      SharedPreferences.setMockInitialValues({
        'notification_appearance_by_note':
            '{"note-1":{"soundUri":null,"soundTitle":null,'
            '"icon":"no_longer_a_real_option"}}',
      });

      expect(
        (await NotificationAppearanceSettings.instance.getForNote('note-1'))
            .icon,
        NotificationIconOption.defaultIcon,
      );
    });
  });

  group('effectiveSoundUri', () {
    test('is null for a null raw uri', () {
      expect(
        NotificationAppearanceSettings.instance.effectiveSoundUri(null),
        isNull,
      );
    });

    test('is null for the explicit system-default uri - it should not '
        'mint a channel identical to the unconfigured one', () {
      expect(
        NotificationAppearanceSettings.instance.effectiveSoundUri(
          'content://settings/system/notification_sound',
        ),
        isNull,
      );
    });

    test('returns a genuinely custom uri as-is', () {
      expect(
        NotificationAppearanceSettings.instance.effectiveSoundUri(
          'content://media/internal/audio/media/1',
        ),
        'content://media/internal/audio/media/1',
      );
    });
  });

  group('isSelectedSound', () {
    test('a literal match is selected', () {
      expect(
        NotificationAppearanceSettings.instance.isSelectedSound(
          'content://media/internal/audio/media/1',
          'content://media/internal/audio/media/1',
        ),
        isTrue,
      );
    });

    test('a non-match is not selected', () {
      expect(
        NotificationAppearanceSettings.instance.isSelectedSound(
          'content://media/internal/audio/media/1',
          'content://media/internal/audio/media/2',
        ),
        isFalse,
      );
    });

    test('when nothing has been chosen (null), the Default option counts '
        'as selected', () {
      expect(
        NotificationAppearanceSettings.instance.isSelectedSound(
          null,
          'content://settings/system/notification_sound',
        ),
        isTrue,
      );
    });

    test('when nothing has been chosen (null), a non-Default option does '
        'not count as selected', () {
      expect(
        NotificationAppearanceSettings.instance.isSelectedSound(
          null,
          'content://media/internal/audio/media/1',
        ),
        isFalse,
      );
    });
  });

  group('channelIdFor', () {
    test('is the base channel id for a null uri', () {
      expect(
        NotificationAppearanceSettings.instance.channelIdFor(null),
        jotesReminderBaseChannelId,
      );
    });

    test('is the base channel id for the explicit system-default uri', () {
      expect(
        NotificationAppearanceSettings.instance.channelIdFor(
          'content://settings/system/notification_sound',
        ),
        jotesReminderBaseChannelId,
      );
    });

    test('is a distinct, uri-derived id for a custom sound', () {
      final id = NotificationAppearanceSettings.instance.channelIdFor(
        'content://media/internal/audio/media/1',
      );

      expect(id, isNot(jotesReminderBaseChannelId));
      expect(id, startsWith('${jotesReminderBaseChannelId}_'));
    });

    test('is stable and deterministic for the same uri', () {
      final first = NotificationAppearanceSettings.instance.channelIdFor(
        'content://media/internal/audio/media/1',
      );
      final second = NotificationAppearanceSettings.instance.channelIdFor(
        'content://media/internal/audio/media/1',
      );

      expect(second, first);
    });

    test('differs between two distinct custom sounds', () {
      final first = NotificationAppearanceSettings.instance.channelIdFor(
        'content://media/internal/audio/media/1',
      );
      final second = NotificationAppearanceSettings.instance.channelIdFor(
        'content://media/internal/audio/media/2',
      );

      expect(second, isNot(first));
    });
  });
}
