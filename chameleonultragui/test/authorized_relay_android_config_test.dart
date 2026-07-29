import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'authorized relay payment service remains discoverable while disarmed',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final serviceMetadata = File(
        'android/app/src/main/res/xml/authorized_relay_apdu_service.xml',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/io/chameleon/ultra/MainActivity.kt',
      ).readAsStringSync();
      final service = File(
        'android/app/src/main/kotlin/io/chameleon/ultra/'
        'AuthorizedRelayHostApduService.kt',
      ).readAsStringSync();
      final relayPage = File(
        'lib/gui/menu/hacking/authorized_relay_lab.dart',
      ).readAsStringSync();
      final hackingMenu = File(
        'lib/gui/page/ethical_hacking.dart',
      ).readAsStringSync();

      expect(
        manifest,
        contains(
          'android:name=".AuthorizedRelayHostApduService"\n'
          '            android:enabled="true"',
        ),
      );
      expect(serviceMetadata, contains('android:category="payment"'));
      expect(serviceMetadata, contains('325041592E5359532E4444463031'));
      expect(activity, contains('CardEmulation.ACTION_CHANGE_DEFAULT'));
      expect(activity, contains('RoleManager.ROLE_WALLET'));
      expect(
        activity,
        isNot(contains('intent.resolveActivity(packageManager)')),
      );
      expect(
        activity,
        contains('PackageManager.COMPONENT_ENABLED_STATE_DEFAULT'),
      );
      expect(
        manifest,
        contains('android:name=".AuthorizedRelayUpgradeReceiver"'),
      );

      final lifecycleReset = RegExp(
        r'private fun resetAuthorizedRelayRouting\(\) \{([\s\S]*?)\n    \}',
      ).firstMatch(activity)!.group(1)!;
      expect(lifecycleReset, isNot(contains('removeAidsForService')));
      expect(
        lifecycleReset,
        isNot(contains('COMPONENT_ENABLED_STATE_DISABLED')),
      );
      expect(service, isNot(contains('setComponentEnabledSetting')));
      expect(service, isNot(contains('removeAidsForService')));
      expect(activity, isNot(contains('removeAidsForService')));
      expect(activity, contains('RoleManager.ROLE_WALLET'));
      expect(activity, contains('authorizeAndEnableAuthorizedRelay'));
      expect(activity, isNot(contains('"authorizeOnce"')));
      expect(relayPage, isNot(contains('_confirmPreparedSession')));
      expect(relayPage, isNot(contains('Review this live backend session')));
      expect(relayPage, isNot(contains('_platform.clearAids()')));
      expect(relayPage, contains('if (!_prepared) {'));
      expect(relayPage, contains('await _prepare();'));
      expect(relayPage, contains('_platform.authorizeAndEnable('));
      expect(relayPage, contains('onPressed: _openPaymentSettings'));
      expect(
        hackingMenu,
        isNot(
          contains(
            '(c) => _push(c, const AuthorizedRelayLabPage()),\n'
            '          deviceRequired: true',
          ),
        ),
      );
    },
  );
}
