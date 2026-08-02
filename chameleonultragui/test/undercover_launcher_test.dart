import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/undercover/undercover_catalog.dart';
import 'package:chameleonultragui/gui/undercover/undercover_launcher.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catalog exposes only five persistent disguised dashboards', (
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
      orderedEquals(['home', 'markets', 'recorder', 'studio', 'signals']),
    );
    expect(screens.every((screen) => screen.apps.isEmpty), isTrue);
    expect(screens.every((screen) => screen.dashboardBuilder != null), isTrue);
  });

  testWidgets('catalog cannot invoke a legacy root or page opener', (
    tester,
  ) async {
    late List<UndercoverMenuScreen> screens;
    var legacyOpenCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            screens = buildUndercoverCatalog(
              context,
              openRoot: (_, _, {required bool requiresConnection}) {
                legacyOpenCount++;
              },
              openPage:
                  (
                    _,
                    label,
                    _,
                    _, {
                    required bool requiresConnection,
                    required bool requiresEthicalAck,
                  }) {
                    legacyOpenCount++;
                  },
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(screens, hasLength(5));
    expect(screens.expand((screen) => screen.apps), isEmpty);
    expect(legacyOpenCount, 0);
  });

  testWidgets('dashboard screens bypass search and app action boards', (
    tester,
  ) async {
    final screens = [
      UndercoverMenuScreen(
        id: 'home',
        title: 'Home',
        subtitle: 'Positions',
        icon: Icons.home,
        accent: Colors.blue,
        dashboardBuilder: (_) =>
            const Center(child: Text('Persistent dashboard')),
      ),
    ];
    await _pumpLauncher(tester, screens: screens);

    expect(find.text('Persistent dashboard'), findsOneWidget);
    expect(find.byKey(const Key('undercover-app-search')), findsNothing);
    expect(find.byKey(const Key('undercover-action-board')), findsNothing);
  });

  testWidgets('all real dashboards render offline on a compact device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final appState = ChameleonGUIState(preferences);
    addTearDown(appState.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: UndercoverLauncher(
                connected: false,
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
      ),
    );
    await tester.pump();

    const ids = ['home', 'markets', 'recorder', 'studio', 'signals'];
    for (var page = 0; page < ids.length; page++) {
      expect(
        find.byKey(Key('undercover-dashboard-${ids[page]}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: ids[page]);
      if (page == ids.length - 1) break;
      await tester.fling(
        find.byKey(const Key('undercover-page-view')),
        const Offset(-320, 0),
        1000,
      );
      await tester.pumpAndSettle();
    }
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

  testWidgets('five dashboard pages fit compact SpringBoard', (tester) async {
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
              screens: List.generate(
                5,
                (index) => UndercoverMenuScreen(
                  id: 'dashboard-$index',
                  title: 'Dashboard $index',
                  subtitle: 'Persistent widgets',
                  icon: Icons.widgets,
                  accent: Colors.blue,
                  dashboardBuilder: (_) => ListView(
                    children: List.generate(
                      24,
                      (cell) => SizedBox(
                        height: 30,
                        child: Text('Cell $index-$cell'),
                      ),
                    ),
                  ),
                ),
              ),
              onExitRequested: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (var page = 1; page < 5; page++) {
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
