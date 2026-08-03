import 'dart:convert';

import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesProvider preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = SharedPreferencesProvider();
    preferences.debugDataSyncWriteInterceptor = null;
    await preferences.load();
  });

  test(
    'plaintext settings export contains only safe scalar GUI settings',
    () async {
      final raw = await SharedPreferences.getInstance();
      await raw.setStringList('cards', ['plaintext-card-secret']);
      await raw.setStringList('dictionaries', ['plaintext-dictionary-secret']);
      await raw.setStringList('keyboard_scripts', ['plaintext-script-secret']);
      await raw.setStringList('emulation_change_history', [
        'plaintext-history-secret',
      ]);
      await raw.setStringList('debug_logging_value', ['plaintext-log-secret']);
      await raw.setString('access_token', 'plaintext-token-secret');
      await preferences.setTheme(ThemeMode.dark);
      await preferences.setThemeColor(7);
      await preferences.setLocale(const Locale('de', 'AT'));
      await preferences.setHfCaptureRetentionDays(90);
      await preferences.setMifareClassicNonceHistoryEnabled(true);
      await preferences.setDeviceLedAnimationMode(AnimationSetting.symmetric);

      final encoded = preferences.dumpSettingsToJson();
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final settings = decoded['settings'] as Map<String, dynamic>;

      expect(decoded.keys.toSet(), {'version', 'settings'});
      expect(decoded['version'], 3);
      expect(settings.keys.toSet(), {
        'app_theme',
        'app_theme_color',
        'locale',
        'confirm_delete',
        'auto_scan_enabled',
        'auto_connect_first_found',
        'device_found_banner',
        'sidebar_auto_expanded',
        'sidebar_expanded_index',
        'emulation_change_monitoring',
        'hf_capture_retention_days',
        'mifare_classic_nonce_history_enabled_v1',
        'device_led_animation_mode',
      });
      expect(settings['app_theme'], ThemeMode.dark.index);
      expect(settings['app_theme_color'], 7);
      expect(settings['locale'], 'de-AT');
      expect(settings['hf_capture_retention_days'], 90);
      expect(settings['mifare_classic_nonce_history_enabled_v1'], isTrue);
      expect(
        settings['device_led_animation_mode'],
        AnimationSetting.symmetric.value,
      );
      expect(encoded, isNot(contains('plaintext-')));

      await preferences.setHfCaptureRetentionDays(7);
      await preferences.setMifareClassicNonceHistoryEnabled(false);
      await preferences.setDeviceLedAnimationMode(AnimationSetting.full);
      await preferences.restoreSettingsFromJson(encoded);
      expect(preferences.getHfCaptureRetentionDays(), 90);
      expect(preferences.getMifareClassicNonceHistoryEnabled(), isTrue);
      expect(
        preferences.getDeviceLedAnimationMode(),
        AnimationSetting.symmetric,
      );
    },
  );

  test('invalid restore is rejected before any setting is mutated', () async {
    await preferences.setTheme(ThemeMode.light);
    await preferences.setThemeColor(2);
    await preferences.setConfirmDelete(true);

    final invalid = jsonEncode({
      'version': 1,
      'settings': {
        'app_theme': ThemeMode.dark.index,
        'confirm_delete': false,
        'app_theme_color': 8,
      },
    });

    await expectLater(
      preferences.restoreSettingsFromJson(invalid),
      throwsA(isA<FormatException>()),
    );
    expect(preferences.getTheme(), ThemeMode.light);
    expect(preferences.getThemeColorIndex(), 2);
    expect(preferences.getConfirmDelete(), isTrue);
  });

  test('version 1 settings backup migrates capture retention safely', () async {
    await preferences.setHfCaptureRetentionDays(90);
    await preferences.setDeviceLedAnimationMode(AnimationSetting.symmetric);

    await preferences.restoreSettingsFromJson(
      jsonEncode({
        'version': 1,
        'settings': {'confirm_delete': false},
      }),
    );

    expect(preferences.getConfirmDelete(), isFalse);
    expect(preferences.getHfCaptureRetentionDays(), 30);
    expect(preferences.getDeviceLedAnimationMode(), AnimationSetting.full);
  });

  test('version 2 settings backup migrates the LED restore mode', () async {
    await preferences.setDeviceLedAnimationMode(AnimationSetting.symmetric);

    await preferences.restoreSettingsFromJson(
      jsonEncode({
        'version': 2,
        'settings': {'confirm_delete': false},
      }),
    );

    expect(preferences.getConfirmDelete(), isFalse);
    expect(preferences.getDeviceLedAnimationMode(), AnimationSetting.full);
  });

  test(
    'restore rejects unknown keys, types, versions, and oversized input',
    () async {
      final invalidBackups = <Object>[
        {'version': 4, 'settings': <String, Object>{}},
        {
          'version': 1,
          'settings': {'cards': <Object>[]},
        },
        {
          'version': 1,
          'settings': {'confirm_delete': 1},
        },
        {
          'version': 1,
          'settings': {'locale': 'not-supported'},
        },
        {
          'version': 3,
          'settings': {
            'device_led_animation_mode': AnimationSetting.none.value,
          },
        },
        {'version': 1, 'settings': <String, Object>{}, 'extra': true},
      ];

      for (final backup in invalidBackups) {
        await expectLater(
          preferences.restoreSettingsFromJson(jsonEncode(backup)),
          throwsA(isA<FormatException>()),
        );
      }
      await expectLater(
        preferences.restoreSettingsFromJson(' ' * (16 * 1024 + 1)),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('corrupt scalar preferences fall back to safe UI defaults', () async {
    final raw = await SharedPreferences.getInstance();
    await raw.setInt('app_theme', 99);
    await raw.setInt('app_theme_color', 99);
    await raw.setInt('hf_capture_retention_days', 0);
    await raw.setInt('device_led_animation_mode', AnimationSetting.none.value);

    expect(preferences.getTheme(), ThemeMode.system);
    expect(preferences.getThemeColorIndex(), 0);
    expect(preferences.getHfCaptureRetentionDays(), 30);
    expect(preferences.getDeviceLedAnimationMode(), AnimationSetting.full);
  });

  test(
    'recovery history is opt-in, hashes failed keys, and is removable per card',
    () async {
      const uid = '04 11 22 33';
      const sample = 'weak|capture-one';

      expect(preferences.getMifareClassicNonceHistoryEnabled(), isFalse);
      await preferences.recordMifareClassicFailedKey(uid, 'FF FF FF FF FF FF');
      await preferences.setMifareClassicNonceHistoryEnabled(true);
      expect(
        preferences.hasMifareClassicFailedKey(uid, 'ffffffffffff'),
        isFalse,
      );
      await preferences.recordMifareClassicNonceSample(uid, sample);
      await preferences.recordMifareClassicNonceSample(uid, sample);
      await preferences.recordMifareClassicNonceSample(uid, 'weak|capture-two');
      await preferences.recordMifareClassicFailedKey(uid, 'FF FF FF FF FF FF');

      expect(preferences.hasMifareClassicNonceSample(uid, sample), isTrue);
      expect(
        preferences.hasMifareClassicFailedKey(uid, 'ffffffffffff'),
        isTrue,
      );
      expect(
        preferences.hasMifareClassicFailedKey('04 11 22 34', 'ffffffffffff'),
        isFalse,
      );
      final summaries = preferences.getMifareClassicNonceHistorySummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.cardUid, '04112233');
      expect(summaries.single.nonceSampleCount, 2);
      expect(summaries.single.failedKeyCount, 1);
      expect(summaries.single.byteSize, greaterThan(0));
      expect(preferences.dumpSettingsToJson(), isNot(contains('04112233')));
      expect(preferences.dumpSettingsToJson(), isNot(contains('FFFFFFFFFFFF')));

      await preferences.clearMifareClassicNonceHistoryForCard(uid);
      expect(preferences.getMifareClassicNonceHistorySummaries(), isEmpty);
    },
  );

  test('legacy nonce history migrates when failed keys are recorded', () async {
    const uid = '04 11 22 33';
    const sample = 'weak|legacy-capture';
    final raw = await SharedPreferences.getInstance();
    final digest = sha256.convert(utf8.encode(sample)).toString();
    await raw.setString(
      'mifare_classic_nonce_history_v1',
      jsonEncode({
        'version': 1,
        'cards': {
          uid: [digest],
        },
      }),
    );

    await preferences.setMifareClassicNonceHistoryEnabled(true);
    expect(preferences.hasMifareClassicNonceSample(uid, sample), isTrue);
    await preferences.recordMifareClassicFailedKey(uid, 'ffffffffffff');

    final stored =
        jsonDecode(raw.getString('mifare_classic_nonce_history_v1')!)
            as Map<String, dynamic>;
    expect(stored['version'], 2);
    final card =
        (stored['cards'] as Map<String, dynamic>)['04112233']
            as Map<String, dynamic>;
    expect(card['nonceSamples'], [digest]);
    expect(card['failedKeys'], hasLength(1));
  });

  test(
    'legacy flat backup migrates only allowlisted scalar settings',
    () async {
      await preferences.restoreSettingsFromJson(
        jsonEncode({
          'app_theme': ThemeMode.dark.index,
          'app_theme_color': 3,
          'confirm_delete': false,
          'cards': ['secret'],
          'debug_logging_value': ['secret'],
        }),
      );

      expect(preferences.getTheme(), ThemeMode.dark);
      expect(preferences.getThemeColorIndex(), 3);
      expect(preferences.getConfirmDelete(), isFalse);
      expect(preferences.getCards(), isEmpty);
      expect(preferences.getLogLines(), isEmpty);
    },
  );

  test(
    'sync metadata migration does not rewrite shipped payload keys',
    () async {
      const legacyCards = ['legacy-card-record'];
      const legacyDictionaries = ['legacy-dictionary-record'];
      const legacyScripts = ['legacy-script-record'];
      SharedPreferences.setMockInitialValues({
        'cards': legacyCards,
        'dictionaries': legacyDictionaries,
        'keyboard_scripts': legacyScripts,
        'app_theme': 1,
        'confirm_delete': false,
      });

      await preferences.load();
      final raw = await SharedPreferences.getInstance();

      expect(raw.getStringList('cards'), legacyCards);
      expect(raw.getStringList('dictionaries'), legacyDictionaries);
      expect(raw.getStringList('keyboard_scripts'), legacyScripts);
      expect(raw.getInt('app_theme'), 1);
      expect(raw.getBool('confirm_delete'), isFalse);
      final checkpoint = SyncCheckpoint.fromJson(
        jsonDecode(raw.getString(dataSyncMetaPreferenceKey)!),
      );
      expect(checkpoint.revision, 0);
    },
  );
}
