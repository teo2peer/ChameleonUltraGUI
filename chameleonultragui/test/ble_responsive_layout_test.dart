import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_app.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_audit.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_capability_gate.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_radio_identity.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_responsive.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_stress.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pumpAtNarrowLargeText(
    WidgetTester tester,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          );
        },
        home: child,
      ),
    );
    await tester.pump();
  }

  testWidgets('BLE hub tabs remain scrollable at narrow width and large text',
      (tester) async {
    final appState = ChameleonGUIState(SharedPreferencesProvider());
    addTearDown(appState.dispose);

    await pumpAtNarrowLargeText(
      tester,
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const BleAppPage(
          auditTab: SizedBox.expand(),
          radioIdentityTab: SizedBox.expand(),
          stressBroadcastTab: SizedBox.expand(),
        ),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.tabAlignment, TabAlignment.start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BLE capability gate blocks incomplete operations',
      (tester) async {
    final appState = ChameleonGUIState(SharedPreferencesProvider())
      ..communicator =
          _CapabilityCommunicator(unsupported: {ChameleonCommand.bleScanStart});
    addTearDown(appState.dispose);

    await pumpAtNarrowLargeText(
      tester,
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const Scaffold(
          body: BleCapabilityGate(
            feature: 'passive scan',
            requiredCommands: [
              ChameleonCommand.bleScanStart,
              ChameleonCommand.bleScanStop,
            ],
            child: Text('audit content'),
          ),
        ),
      ),
    );

    expect(find.text('audit content'), findsNothing);
    expect(find.textContaining('does not advertise support'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BLE audit tabs remain scrollable at narrow width and large text',
      (tester) async {
    final appState = ChameleonGUIState(SharedPreferencesProvider());
    addTearDown(appState.dispose);

    await pumpAtNarrowLargeText(
      tester,
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const BleAuditPage(),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.tabAlignment, TabAlignment.start);
    expect(tester.takeException(), isNull);
  });

  for (final page in <String, Widget>{
    'audit': const BleAuditPage(embedded: true),
    'radio': const BleRadioIdentityPage(embedded: true),
    'stress': const BleStressPage(embedded: true),
  }.entries) {
    testWidgets('connected BLE ${page.key} page has no narrow overflow',
        (tester) async {
      final appState = ChameleonGUIState(SharedPreferencesProvider())
        ..connector = (_ConnectedSerial()..connected = true)
        ..communicator = _CapabilityCommunicator(unsupported: const {});
      addTearDown(appState.dispose);

      await pumpAtNarrowLargeText(
        tester,
        ChangeNotifierProvider<ChameleonGUIState>.value(
          value: appState,
          child: Scaffold(body: page.value),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('BLE responsive fields and key values stack without overflow',
      (tester) async {
    const firstFieldKey = Key('first-field');
    const secondFieldKey = Key('second-field');

    await pumpAtNarrowLargeText(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              BleResponsiveFieldGroup(
                children: [
                  TextField(
                    key: firstFieldKey,
                    decoration: InputDecoration(
                      labelText: 'Long localized first BLE field label',
                    ),
                  ),
                  TextField(
                    key: secondFieldKey,
                    decoration: InputDecoration(
                      labelText: 'Long localized second BLE field label',
                    ),
                  ),
                ],
              ),
              BleResponsiveKeyValueRow(
                label: 'Long localized BLE setting label',
                value: 'RANDOM_PRIVATE_NON_RESOLVABLE',
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(secondFieldKey)).dy,
      greaterThan(tester.getBottomLeft(find.byKey(firstFieldKey)).dy),
    );
    final labelTop = tester.getTopLeft(
      find.text('Long localized BLE setting label'),
    );
    final valueTop = tester.getTopLeft(
      find.text('RANDOM_PRIVATE_NON_RESOLVABLE'),
    );
    expect(valueTop.dy, greaterThan(labelTop.dy));
    expect(tester.takeException(), isNull);
  });
}

class _CapabilityCommunicator extends ChameleonCommunicator {
  final Set<ChameleonCommand> unsupported;

  _CapabilityCommunicator({required this.unsupported})
      : super(Logger(level: Level.off));

  @override
  bool? supportsCommandSync(ChameleonCommand command) =>
      !unsupported.contains(command);
}

class _ConnectedSerial extends AbstractSerial {
  _ConnectedSerial() : super(log: Logger(level: Level.off));

  @override
  Future<void> open() async {
    isOpen = true;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => true;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;

  @override
  bool isManualConnectionSupported() => false;
}
