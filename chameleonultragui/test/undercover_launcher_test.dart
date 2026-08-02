import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/undercover/undercover_catalog.dart';
import 'package:chameleonultragui/gui/undercover/undercover_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catalog exposes every Undercover menu and unique app id', (
    tester,
  ) async {
    late List<UndercoverMenuScreen> screens;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            screens = buildUndercoverCatalog(
              context,
              openRoot: (_, _, {required bool requiresConnection}) {},
              openPage:
                  (
                    _,
                    _,
                    _,
                    _, {
                    required bool requiresConnection,
                    required bool requiresEthicalAck,
                  }) {},
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      screens.map((screen) => screen.id),
      orderedEquals([
        'device',
        'library',
        'recovery',
        'capture',
        'tools',
        'diagnostics',
      ]),
    );
    final apps = screens.expand((screen) => screen.apps).toList();
    expect(apps.length, greaterThanOrEqualTo(35));
    expect(apps.map((app) => app.id).toSet().length, apps.length);
    expect(apps.every((app) => app.title.isNotEmpty), isTrue);
    expect(apps.every((app) => app.menuPath.isNotEmpty), isTrue);
  });

  testWidgets('catalog gates device and ethical actions before opening', (
    tester,
  ) async {
    late List<UndercoverMenuScreen> screens;
    String? opened;
    bool? openedRequiresConnection;
    bool? openedRequiresEthicalAck;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            screens = buildUndercoverCatalog(
              context,
              openRoot: (_, _, {required bool requiresConnection}) {},
              openPage:
                  (
                    _,
                    label,
                    _,
                    _, {
                    required bool requiresConnection,
                    required bool requiresEthicalAck,
                  }) {
                    opened = label;
                    openedRequiresConnection = requiresConnection;
                    openedRequiresEthicalAck = requiresEthicalAck;
                  },
            );
            return const SizedBox();
          },
        ),
      ),
    );

    screens
        .expand((screen) => screen.apps)
        .singleWhere((app) => app.id == 'autopwn')
        .onOpen();
    expect(opened, 'Autopwn');
    expect(openedRequiresConnection, isTrue);
    expect(openedRequiresEthicalAck, isTrue);

    screens
        .expand((screen) => screen.apps)
        .singleWhere((app) => app.id == 'data-sync')
        .onOpen();
    expect(opened, 'Data Sync');
    expect(openedRequiresConnection, isFalse);
    expect(openedRequiresEthicalAck, isFalse);
  });

  testWidgets('tap opens an action board before the real app', (tester) async {
    UndercoverAppEntry? opened;
    late final UndercoverAppEntry app;
    app = UndercoverAppEntry(
      id: 'reader',
      title: 'Reader',
      menuPath: 'Device / Reader',
      icon: Icons.sensors,
      accent: Colors.green,
      onOpen: () => opened = app,
    );

    await _pumpLauncher(tester, screens: _screens(app));

    expect(find.text('Device / Reader'), findsOneWidget);
    await tester.tap(find.byKey(const Key('undercover-app-reader')));
    await tester.pump();

    expect(find.byKey(const Key('undercover-action-board')), findsOneWidget);
    expect(opened, isNull);
    await tester.tap(find.byKey(const Key('undercover-action-open-reader')));
    await tester.pump();

    expect(opened, same(app));
  });

  testWidgets('action search filters icons and app info stays on SpringBoard', (
    tester,
  ) async {
    await _pumpLauncher(tester, screens: _screens(_noopApp()));
    await tester.tap(find.byKey(const Key('undercover-app-reader')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('undercover-action-search')),
      'info',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('undercover-action-open-reader')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('undercover-action-info-reader')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('undercover-action-info-reader')));
    await tester.pump();
    expect(find.byKey(const Key('undercover-app-info')), findsOneWidget);
  });

  testWidgets('horizontal swipe changes between menu screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpLauncher(tester, screens: _screens(_noopApp()));

    expect(find.text('Device'), findsOneWidget);
    await tester.fling(
      find.byKey(const Key('undercover-page-view')),
      const Offset(-360, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('Security'), findsOneWidget);
    expect(find.byKey(const Key('undercover-app-security')), findsOneWidget);
  });

  testWidgets('connection-required apps stay disabled while local', (
    tester,
  ) async {
    var opens = 0;
    final app = UndercoverAppEntry(
      id: 'reader',
      title: 'Reader',
      menuPath: 'Device / Reader',
      icon: Icons.sensors,
      accent: Colors.green,
      requiresConnection: true,
      onOpen: () => opens++,
    );
    await _pumpLauncher(tester, connected: false, screens: _screens(app));

    await tester.tap(find.byKey(const Key('undercover-app-reader')));
    await tester.pump();

    expect(opens, 0);
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);
  });

  testWidgets('connection loss closes a connection-required action board', (
    tester,
  ) async {
    var opens = 0;
    final app = UndercoverAppEntry(
      id: 'reader',
      title: 'Reader',
      menuPath: 'Device / Reader',
      icon: Icons.sensors,
      accent: Colors.green,
      requiresConnection: true,
      onOpen: () => opens++,
    );
    final screens = _screens(app);
    await _pumpLauncher(tester, connected: true, screens: screens);
    await tester.tap(find.byKey(const Key('undercover-app-reader')));
    await tester.pump();
    expect(find.byKey(const Key('undercover-action-board')), findsOneWidget);

    await _pumpLauncher(tester, connected: false, screens: screens);

    expect(find.byKey(const Key('undercover-action-board')), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);
    expect(opens, 0);
  });

  testWidgets('long press, visible control and escape request exit', (
    tester,
  ) async {
    var exits = 0;
    await _pumpLauncher(
      tester,
      screens: _screens(_noopApp()),
      onExitRequested: () => exits++,
    );

    await tester.longPress(find.byKey(const Key('undercover-exit-anchor')));
    await tester.pump();
    expect(exits, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(exits, 2);

    await tester.tap(find.byKey(const Key('undercover-exit-button')));
    await tester.pump();
    expect(exits, 3);
  });

  testWidgets('launcher remains responsive from narrow mobile to desktop', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [
      Size(320, 568),
      Size(375, 812),
      Size(768, 1024),
      Size(1024, 768),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await _pumpLauncher(
        tester,
        screens: _screens(_noopApp()),
        textScale: size.width == 320 ? 1.6 : 1,
      );
      expect(find.byKey(const Key('undercover-launcher')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('full catalog fits compact SpringBoard across every page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: UndercoverLauncher(
              connected: true,
              screens: buildUndercoverCatalog(
                context,
                openRoot: (_, _, {required bool requiresConnection}) {},
                openPage:
                    (
                      _,
                      _,
                      _,
                      _, {
                      required bool requiresConnection,
                      required bool requiresEthicalAck,
                    }) {},
              ),
              onExitRequested: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (var page = 1; page < 6; page++) {
      await tester.fling(
        find.byKey(const Key('undercover-page-view')),
        const Offset(-320, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

UndercoverAppEntry _noopApp() => UndercoverAppEntry(
  id: 'reader',
  title: 'Reader',
  menuPath: 'Device / Reader',
  icon: Icons.sensors,
  accent: Colors.green,
  onOpen: () {},
);

List<UndercoverMenuScreen> _screens(UndercoverAppEntry app) => [
  UndercoverMenuScreen(
    id: 'device',
    title: 'Device',
    subtitle: 'Reader and writer operations',
    icon: Icons.memory,
    accent: Colors.blue,
    apps: [app],
  ),
  UndercoverMenuScreen(
    id: 'security',
    title: 'Security',
    subtitle: 'Authorized diagnostics',
    icon: Icons.security,
    accent: Colors.red,
    apps: [
      UndercoverAppEntry(
        id: 'security',
        title: 'Security Lab',
        menuPath: 'Security / Lab',
        icon: Icons.security,
        accent: Colors.red,
        onOpen: () {},
      ),
    ],
  ),
];

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required List<UndercoverMenuScreen> screens,
  bool connected = true,
  double textScale = 1,
  VoidCallback? onExitRequested,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: UndercoverLauncher(
          connected: connected,
          screens: screens,
          onExitRequested: onExitRequested ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}
