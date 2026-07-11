import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_audit_status.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_characteristic_tile.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpLocalized(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(800, 600),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: textScaler),
            child: child!,
          );
        },
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'characteristic actions wrap and invoke callbacks at narrow large text',
      (tester) async {
    final actions = <String>[];
    final characteristic = BleCharacteristic(
      handle: 0x002A,
      props: 0x3E,
      uuidType: 1,
      uuid: 0x2A37,
    );

    await pumpLocalized(
      tester,
      BleCharacteristicTile(
        characteristic: characteristic,
        readValue: '01020304',
        notifying: false,
        onRead: () => actions.add('read'),
        onWrite: () => actions.add('write'),
        onSelectFuzz: () => actions.add('select'),
        onToggleNotify: () => actions.add('notify'),
      ),
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );

    expect(find.textContaining('0x002a'), findsOneWidget);
    expect(find.textContaining('= 01020304'), findsOneWidget);
    for (final label in ['Read', 'Write', 'Select fuzz', 'Notify']) {
      await tester.tap(find.widgetWithText(TextButton, label));
      await tester.pump();
    }

    expect(actions, ['read', 'write', 'select', 'notify']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('characteristic tile shows stop for an active notification',
      (tester) async {
    await pumpLocalized(
      tester,
      BleCharacteristicTile(
        characteristic: BleCharacteristic(
          handle: 1,
          props: 0x10,
          uuidType: 1,
          uuid: 0x2A37,
        ),
        readValue: null,
        notifying: true,
        onRead: () {},
        onWrite: () {},
        onSelectFuzz: () {},
        onToggleNotify: () {},
      ),
    );

    expect(find.text('Stop'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Notify'), findsNothing);
  });

  testWidgets('status renders localized state, MTU, probe error, and reason',
      (tester) async {
    await pumpLocalized(
      tester,
      BleAuditStatus(
        state: BleCentralState(
          connState: 2,
          discState: 2,
          charCount: 7,
          fuzzState: 1,
          fuzzSent: 42,
          targetAlive: true,
          lastReason: 0x13,
          probeState: 3,
          probeResult: 0x08,
        ),
        mtu: 247,
      ),
    );

    expect(find.text('connection : connected'), findsOneWidget);
    expect(find.text('discovery  : done (7 chars)'), findsOneWidget);
    expect(find.text('fuzz       : running (42 writes)'), findsOneWidget);
    expect(find.text('target up  : Yes'), findsOneWidget);
    expect(find.text('ATT MTU    : 247'), findsOneWidget);
    expect(find.text('link probe : error (0x8)'), findsOneWidget);
    expect(find.text('last disconnect reason : 0x13'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
