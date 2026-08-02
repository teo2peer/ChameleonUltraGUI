import 'package:chameleonultragui/gui/component/module_version_footer.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_app.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('module registry keeps complete SemVer and ISO date metadata', () {
    expect(moduleVersions.keys.toSet(), ModuleId.values.toSet());

    for (final module in moduleVersions.values) {
      expect(module.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(module.updatedAt, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(DateTime.tryParse(module.updatedAt), isNotNull);
    }
  });

  test('Autopwn variants keep independent versions', () {
    expect(moduleReleaseFor(ModuleId.autopwn).version, '1.2.0');
    expect(moduleReleaseFor(ModuleId.autopwnPlus).version, '1.1.0');
    expect(moduleReleaseFor(ModuleId.autopwnV2).version, '1.1.0');
  });

  test('capture, batching, and sync owners expose updated releases', () {
    expect(moduleReleaseFor(ModuleId.dataSync).version, '1.2.0');
    expect(moduleReleaseFor(ModuleId.captureAndSniffing).version, '1.1.0');
    expect(moduleReleaseFor(ModuleId.mifareClassicAttacks).version, '1.1.0');
    expect(moduleReleaseFor(ModuleId.dictionaryCheck).version, '1.1.0');
  });

  test('continuous capture exposes its durability revision', () {
    expect(moduleReleaseFor(ModuleId.hfContinuousCapture).version, '1.2.0');
  });

  test('slot manager release includes reliable dump uploads', () {
    final release = moduleReleaseFor(ModuleId.slotManager);
    expect(release.version, '1.1.0');
    expect(release.updatedAt, '2026-08-02');
    expect(moduleReleaseFor(ModuleId.device).version, '1.1.0');
  });

  test('Undercover keeps an independent release', () {
    expect(moduleReleaseFor(ModuleId.undercover).version, '1.0.1');
    expect(moduleReleaseFor(ModuleId.undercover).updatedAt, '2026-08-02');
    expect(moduleReleaseFor(ModuleId.appShell).version, '1.1.0');
  });

  testWidgets('footer renders the selected module release', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ModuleVersionFooter(moduleId: ModuleId.readerKeysCapture),
        ),
      ),
    );

    expect(find.text('Reader Keys Capture'), findsOneWidget);
    expect(find.text('Version 1.0.0 / Updated 2026-07-30'), findsOneWidget);
  });

  testWidgets('navigation observer restores the root module after pop', (
    tester,
  ) async {
    final activeModule = ValueNotifier(ModuleId.device);
    addTearDown(activeModule.dispose);
    final observer = ModuleNavigationObserver(
      activeModule: activeModule,
      rootModule: ModuleId.device,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                ModulePageRoute<void>(
                  moduleId: ModuleId.tools,
                  builder: (_) => const Scaffold(body: Text('Tools page')),
                ),
              ),
              child: const Text('Open tools'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open tools'));
    await tester.pumpAndSettle();
    expect(activeModule.value, ModuleId.tools);

    Navigator.of(tester.element(find.text('Tools page'))).pop();
    await tester.pumpAndSettle();
    expect(activeModule.value, ModuleId.device);
  });

  testWidgets('navigation overlays preserve the active module', (tester) async {
    final activeModule = ValueNotifier(ModuleId.device);
    addTearDown(activeModule.dispose);
    final observer = ModuleNavigationObserver(
      activeModule: activeModule,
      rootModule: ModuleId.device,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await Navigator.push<void>(
                  context,
                  ModulePageRoute<void>(
                    moduleId: ModuleId.pm3Catalog,
                    builder: (routeContext) => Scaffold(
                      body: TextButton(
                        onPressed: () => showDialog<void>(
                          context: routeContext,
                          builder: (_) =>
                              const AlertDialog(title: Text('Overlay')),
                        ),
                        child: const Text('Open overlay'),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open PM3'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open PM3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open overlay'));
    await tester.pumpAndSettle();

    expect(find.text('Overlay'), findsOneWidget);
    expect(activeModule.value, ModuleId.pm3Catalog);
  });

  testWidgets('versioned dialogs select and restore their own module', (
    tester,
  ) async {
    final activeModule = ValueNotifier(ModuleId.device);
    addTearDown(activeModule.dispose);
    final observer = ModuleNavigationObserver(
      activeModule: activeModule,
      rootModule: ModuleId.device,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                ModulePageRoute<void>(
                  moduleId: ModuleId.bleAudit,
                  builder: (routeContext) => Scaffold(
                    body: TextButton(
                      onPressed: () => showDialog<void>(
                        context: routeContext,
                        routeSettings: const RouteSettings(
                          arguments: ModuleId.mfkeyManual,
                        ),
                        builder: (_) =>
                            const AlertDialog(title: Text('MFKey Manual')),
                      ),
                      child: const Text('Open MFKey'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open BLE Audit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open BLE Audit'));
    await tester.pumpAndSettle();
    expect(activeModule.value, ModuleId.bleAudit);

    activeModule.value = ModuleId.bleRadioIdentity;

    await tester.tap(find.text('Open MFKey'));
    await tester.pumpAndSettle();
    expect(activeModule.value, ModuleId.mfkeyManual);

    Navigator.of(tester.element(find.text('MFKey Manual'))).pop();
    await tester.pumpAndSettle();
    expect(activeModule.value, ModuleId.bleRadioIdentity);
  });

  testWidgets('BLE tabs select independent module versions', (tester) async {
    final activeModule = ValueNotifier(ModuleId.bleAudit);
    addTearDown(activeModule.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ModuleVersionScope(
          notifier: activeModule,
          child: const BleAppPage(
            auditTab: SizedBox.expand(),
            radioIdentityTab: SizedBox.expand(),
            advertisingLabTab: SizedBox.expand(),
            stressBroadcastTab: SizedBox.expand(),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.bluetooth));
    await tester.pumpAndSettle();

    expect(activeModule.value, ModuleId.bleRadioIdentity);
  });
}
