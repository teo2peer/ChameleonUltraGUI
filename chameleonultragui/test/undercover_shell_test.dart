import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/undercover/undercover_shell.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell persists around pushed submenu routes', (tester) async {
    final activeModule = ValueNotifier(ModuleId.device);
    final overlayActive = ValueNotifier(false);
    addTearDown(activeModule.dispose);
    addTearDown(overlayActive.dispose);
    final observer = ModuleNavigationObserver(
      activeModule: activeModule,
      rootModule: ModuleId.device,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        builder: (context, child) => UndercoverShell(
          activeModule: activeModule,
          overlayActive: overlayActive,
          rootLabel: 'Device',
          connected: true,
          onBack: () => Navigator.of(context).maybePop(),
          onLauncher: () {},
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  ModulePageRoute<void>(
                    moduleId: ModuleId.tools,
                    builder: (_) => const Scaffold(body: Text('Submenu')),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('undercover-shell')), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Submenu'), findsOneWidget);
    expect(find.byKey(const Key('undercover-shell')), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
  });

  testWidgets('shell themes controls as iOS widgets and exposes navigation', (
    tester,
  ) async {
    final activeModule = ValueNotifier(ModuleId.settings);
    final overlayActive = ValueNotifier(false);
    addTearDown(activeModule.dispose);
    addTearDown(overlayActive.dispose);
    var back = 0;
    var launcher = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: UndercoverShell(
          activeModule: activeModule,
          overlayActive: overlayActive,
          rootLabel: 'Settings',
          connected: false,
          onBack: () => back++,
          onLauncher: () => launcher++,
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(key: Key('undercover-input')),
                  FilledButton(onPressed: null, child: Text('Execute')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final input = tester.widget<TextField>(
      find.byKey(const Key('undercover-input')),
    );
    final inputContext = tester.element(find.byWidget(input));
    expect(Theme.of(inputContext).brightness, Brightness.dark);
    expect(Theme.of(inputContext).platform, TargetPlatform.iOS);
    expect(Theme.of(inputContext).inputDecorationTheme.filled, isTrue);

    await tester.tap(
      find.byKey(const Key('undercover-shell-back')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const Key('undercover-shell-launcher')),
      warnIfMissed: false,
    );
    expect(back, 1);
    expect(launcher, 1);

    overlayActive.value = true;
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('undercover-shell-back')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const Key('undercover-shell-launcher')),
      warnIfMissed: false,
    );
    expect(back, 1);
    expect(launcher, 1);
  });

  testWidgets('shell header fits compact mobile with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final activeModule = ValueNotifier(ModuleId.readerKeysCapture);
    final overlayActive = ValueNotifier(false);
    addTearDown(activeModule.dispose);
    addTearDown(overlayActive.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: UndercoverShell(
            activeModule: activeModule,
            overlayActive: overlayActive,
            rootLabel: 'Reader Keys Capture / Authorized Diagnostics',
            connected: true,
            onBack: () {},
            onLauncher: () {},
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('undercover-shell')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
