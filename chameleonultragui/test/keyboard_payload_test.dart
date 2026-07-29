import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/chameleon_keyboard.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/keyboard_payload.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/keyboard_layout.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('layout selector defaults to US and invalidates compilation',
      (tester) async {
    final appState = ChameleonGUIState(SharedPreferencesProvider())
      ..connector = (_ConnectedSerial()
        ..connected = true
        ..connectionType = ConnectionType.usb)
      ..communicator = _KeyboardCapabilityCommunicator();
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KeyboardPayloadPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('US English'), findsOneWidget);
    final compileButton = find.widgetWithText(FilledButton, 'Compile');
    await tester.ensureVisible(compileButton);
    await tester.tap(compileButton);
    await tester.pump();
    expect(find.textContaining('Compiled'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Upload'))
          .onPressed,
      isNotNull,
    );

    final selector = find.byType(DropdownButtonFormField<KeyboardLayout>);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('German').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Compiled'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Upload'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('BLE output exposes the host pairing menu', (tester) async {
    final appState = ChameleonGUIState(SharedPreferencesProvider())
      ..connector = (_ConnectedSerial()
        ..connected = true
        ..connectionType = ConnectionType.usb)
      ..communicator = _KeyboardCapabilityCommunicator();
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KeyboardPayloadPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final outputSelector = tester.widget<SegmentedButton<KeyboardOutput>>(
      find.byType(SegmentedButton<KeyboardOutput>),
    );
    outputSelector.onSelectionChanged!({KeyboardOutput.ble});
    await tester.pumpAndSettle();

    final nameField =
        find.widgetWithText(TextFormField, 'Temporary Bluetooth name');
    await tester.enterText(nameField, 'Lab Keyboard');
    expect(tester.widget<TextFormField>(nameField).controller?.text,
        'Lab Keyboard');

    final pairButton = find.widgetWithText(OutlinedButton, 'Pair BLE host');
    expect(pairButton, findsOneWidget);
    await tester.ensureVisible(pairButton);
    await tester.tap(pairButton);
    await tester.pumpAndSettle();

    expect(find.text('Pair Bluetooth keyboard'), findsOneWidget);
    expect(find.text('Pairing: Disabled'), findsOneWidget);
    expect(find.text('Enable pairing'), findsOneWidget);
    expect(find.text('Open Bluetooth settings'), findsOneWidget);
    expect(find.text('Temporary Bluetooth name'), findsOneWidget);
    expect(find.text('Current requested name: Lab Keyboard'), findsOneWidget);
    expect(find.text('Advertise and arm'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Advertise and arm'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('legacy keyboard firmware keeps existing controls available',
      (tester) async {
    final appState = ChameleonGUIState(SharedPreferencesProvider())
      ..connector = (_ConnectedSerial()
        ..connected = true
        ..connectionType = ConnectionType.usb)
      ..communicator = _LegacyKeyboardCommunicator();
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KeyboardPayloadPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compile'), findsOneWidget);
    expect(find.textContaining('firmware does not support'), findsNothing);
    final outputSelector = tester.widget<SegmentedButton<KeyboardOutput>>(
      find.byType(SegmentedButton<KeyboardOutput>),
    );
    outputSelector.onSelectionChanged!({KeyboardOutput.ble});
    await tester.pumpAndSettle();
    expect(find.textContaining('Update firmware'), findsOneWidget);
  });

  testWidgets('saves a precompiled script and exposes it in the library',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final appState = ChameleonGUIState(preferences)
      ..connector = (_ConnectedSerial()
        ..connected = true
        ..connectionType = ConnectionType.usb)
      ..communicator = _KeyboardCapabilityCommunicator();
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KeyboardPayloadPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Save script');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Mobile demo');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved Mobile demo'), findsOneWidget);
    expect(preferences.getKeyboardScripts(), hasLength(1));
    expect(preferences.getKeyboardScripts().single.program, isNotEmpty);

    await tester.tap(find.byTooltip('Saved scripts').first);
    await tester.pumpAndSettle();
    expect(find.text('Mobile demo'), findsOneWidget);
    expect(find.textContaining('US English | USB |'), findsOneWidget);
    expect(find.byTooltip('Quick launch'), findsOneWidget);
  });
}

class _KeyboardCapabilityCommunicator extends ChameleonCommunicator {
  _KeyboardCapabilityCommunicator() : super(Logger(level: Level.off));

  @override
  bool? supportsCommandSync(ChameleonCommand command) => true;

  @override
  Future<bool> isBLEPairEnabled() async => false;
}

class _LegacyKeyboardCommunicator extends _KeyboardCapabilityCommunicator {
  @override
  bool? supportsCommandSync(ChameleonCommand command) =>
      command != ChameleonCommand.keyboardSetTemporaryBleName &&
      command != ChameleonCommand.keyboardArmBle;
}

class _ConnectedSerial extends AbstractSerial {
  _ConnectedSerial() : super(log: Logger(level: Level.off));

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => true;
}
