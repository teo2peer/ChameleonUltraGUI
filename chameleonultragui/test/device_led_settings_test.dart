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

  testWidgets('device LED switch uses the Undercover runtime LED control', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _DeviceLedCommunicator();
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
    expect(find.text('All device LEDs are enabled.'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(communicator.runtimeModes, [true]);
    expect(preferences.getDeviceLedsEnabled(), isFalse);
    expect(find.text('All device LEDs are disabled.'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(communicator.runtimeModes, [true, false]);
    expect(preferences.getDeviceLedsEnabled(), isTrue);
    expect(find.text('All device LEDs are enabled.'), findsOneWidget);
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

  testWidgets('failed runtime update preserves preference and can be retried', (
    tester,
  ) async {
    final fixture = await _pumpSettings(
      tester,
      _DeviceLedCommunicator()..runtimeFailures = 1,
    );
    final toggle = find.byKey(const Key('device-led-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(fixture.communicator.runtimeModes, isEmpty);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(
      fixture.appState.sharedPreferencesProvider.getDeviceLedsEnabled(),
      isTrue,
    );
    expect(
      find.textContaining('Unable to update device LEDs:'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('device-led-retry')));
    await tester.pumpAndSettle();

    expect(fixture.communicator.runtimeAttempts, 2);
    expect(fixture.communicator.runtimeModes, [true]);
    expect(find.textContaining('Unable to update device LEDs:'), findsNothing);
    expect(find.text('All device LEDs are disabled.'), findsOneWidget);
  });

  testWidgets('unsupported runtime control keeps the LED switch disabled', (
    tester,
  ) async {
    final communicator = _DeviceLedCommunicator()..supported = false;
    await _pumpSettings(tester, communicator);

    final toggle = find.byKey(const Key('device-led-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(find.text('Unavailable'), findsOneWidget);
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
  _DeviceLedCommunicator() : super(Logger(level: Level.off));

  final List<bool> runtimeModes = [];
  int runtimeAttempts = 0;
  int runtimeFailures = 0;
  bool supported = true;

  @override
  bool get usesBleTransport => true;

  @override
  bool? supportsCommandSync(ChameleonCommand command) =>
      command == ChameleonCommand.setRuntimeUndercoverMode && supported;

  @override
  Future<void> setRuntimeUndercoverMode(bool enabled) async {
    runtimeAttempts++;
    if (runtimeFailures > 0) {
      runtimeFailures--;
      throw StateError('runtime update failed');
    }
    runtimeModes.add(enabled);
  }
}
