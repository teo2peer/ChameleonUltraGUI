import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device LED switch disables and restores the previous mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _DeviceLedCommunicator(AnimationSetting.symmetric);
    final appState = ChameleonGUIState(preferences)
      ..communicator = communicator;
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsMainPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('device-led-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Status animations are enabled.'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(communicator.mode, AnimationSetting.none);
    expect(communicator.savedSettingsCount, 1);
    expect(preferences.getDeviceLedAnimationMode(), AnimationSetting.symmetric);
    expect(find.text('All device LEDs are disabled.'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(communicator.mode, AnimationSetting.symmetric);
    expect(communicator.savedSettingsCount, 2);
    expect(find.text('Status animations are enabled.'), findsOneWidget);
  });

  testWidgets('device LED switch is disabled without a connection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final appState = ChameleonGUIState(preferences);
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsMainPage(),
        ),
      ),
    );

    final toggle = find.byKey(const Key('device-led-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    final tile = tester.widget<SwitchListTile>(toggle);
    expect(tile.onChanged, isNull);
    expect(find.text('Connect a device to manage its LEDs.'), findsOneWidget);
  });

  testWidgets('failed persistence reflects runtime state and can be retried', (
    tester,
  ) async {
    final fixture = await _pumpSettings(
      tester,
      _DeviceLedCommunicator(AnimationSetting.symmetric)..saveFailures = 1,
    );
    final toggle = find.byKey(const Key('device-led-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(fixture.communicator.mode, AnimationSetting.none);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(
      find.textContaining('Unable to update device LEDs:'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('device-led-retry')));
    await tester.pumpAndSettle();

    expect(fixture.communicator.saveAttempts, 2);
    expect(find.textContaining('Unable to update device LEDs:'), findsNothing);
    expect(find.text('All device LEDs are disabled.'), findsOneWidget);
  });

  testWidgets('a stale LED read cannot overwrite disconnected state', (
    tester,
  ) async {
    final read = Completer<AnimationSetting>();
    final communicator = _DeviceLedCommunicator(AnimationSetting.symmetric)
      ..readCompleter = read;
    final fixture = await _pumpSettings(tester, communicator, settle: false);
    await tester.pump();

    fixture.appState.communicator = null;
    fixture.appState.changesMade();
    await tester.pump();
    read.complete(AnimationSetting.symmetric);
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('device-led-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(find.text('Connect a device to manage its LEDs.'), findsOneWidget);
  });
}

Future<_SettingsFixture> _pumpSettings(
  WidgetTester tester,
  _DeviceLedCommunicator communicator, {
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = SharedPreferencesProvider();
  await preferences.load();
  final appState = ChameleonGUIState(preferences)..communicator = communicator;
  addTearDown(() {
    if (!identical(appState.communicator, communicator)) {
      communicator.dispose('Test cleanup');
    }
    appState.dispose();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider<ChameleonGUIState>.value(
      value: appState,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsMainPage(),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return _SettingsFixture(appState, communicator);
}

class _SettingsFixture {
  const _SettingsFixture(this.appState, this.communicator);

  final ChameleonGUIState appState;
  final _DeviceLedCommunicator communicator;
}

class _DeviceLedCommunicator extends ChameleonCommunicator {
  _DeviceLedCommunicator(this.mode) : super(Logger(level: Level.off));

  AnimationSetting mode;
  int saveAttempts = 0;
  int saveFailures = 0;
  Completer<AnimationSetting>? readCompleter;

  int get savedSettingsCount => saveAttempts;

  @override
  Future<AnimationSetting> getAnimationMode() async {
    final pendingRead = readCompleter;
    if (pendingRead != null) {
      readCompleter = null;
      return pendingRead.future;
    }
    return mode;
  }

  @override
  Future<void> setAnimationMode(AnimationSetting animation) async {
    mode = animation;
  }

  @override
  Future<void> saveSettings() async {
    saveAttempts++;
    if (saveFailures > 0) {
      saveFailures--;
      throw StateError('persistence failed');
    }
  }
}
