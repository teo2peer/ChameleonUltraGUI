import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/undercover/undercover_dashboards.dart';
import 'package:chameleonultragui/gui/undercover/undercover_catalog.dart';
import 'package:chameleonultragui/gui/undercover/undercover_grid.dart';
import 'package:chameleonultragui/gui/undercover/undercover_launcher.dart';
import 'package:chameleonultragui/gui/page/ethical_hacking.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Key Recovery chart values follow the sector key bands', () {
    final values = buildRecoverySectorChartValues(
      seed: 42,
      keysPerSector: const [0, 1, 2, 0],
    );

    expect(values, hasLength(4));
    expect(values[0], inInclusiveRange(-25, -3));
    expect(values[1], inInclusiveRange(3, 24));
    expect(values[2], inInclusiveRange(27, 50));
    expect(values[3], inInclusiveRange(-25, -3));
  });

  test(
    'HF emulation accepts valid fixed UIDs and generates safe random UIDs',
    () {
      expect(
        parseUndercoverEmulationUid('04:A1-B2 C3'),
        orderedEquals([0x04, 0xA1, 0xB2, 0xC3]),
      );
      expect(parseUndercoverEmulationUid('04 A1 B2 C3 D4 E5 F6'), hasLength(7));
      expect(parseUndercoverEmulationUid('AABBCC'), isNull);
      expect(parseUndercoverEmulationUid('04A1B2ZZ'), isNull);

      final randomUid = generateUndercoverEmulationUid(length: 7, seed: 42);
      expect(randomUid, hasLength(7));
      expect(randomUid.first, isNot(0x88));
      expect(randomUid.any((byte) => byte != 0), isTrue);
      expect(
        () => generateUndercoverEmulationUid(length: 5),
        throwsArgumentError,
      );
    },
  );

  testWidgets('catalog exposes five dashboards and a final tool folder page', (
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
        'home',
        'markets',
        'recorder',
        'studio',
        'signals',
        'tools',
      ]),
    );
    expect(
      screens.map((screen) => screen.title),
      orderedEquals([
        'Select Card',
        'Key Recovery',
        'HF Capture',
        'Emulation',
        'HF 14A Sniff',
        'Tools',
      ]),
    );
    expect(screens.take(5).every((screen) => screen.apps.isEmpty), isTrue);
    expect(
      screens.take(5).every((screen) => screen.dashboardBuilder != null),
      isTrue,
    );
    expect(screens.last.apps, hasLength(6));
    expect(screens.last.apps.every((app) => app.opensDirectly), isTrue);
  });

  testWidgets(
    'catalog does not invoke a root or folder opener while building',
    (tester) async {
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

      expect(screens, hasLength(6));
      expect(screens.last.apps, hasLength(6));
      expect(legacyOpenCount, 0);
    },
  );

  testWidgets('tool folders open their category directly', (tester) async {
    late List<UndercoverMenuScreen> screens;
    String? openedLabel;
    Widget? openedPage;
    bool? requiredAcknowledgement;
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
                    page, {
                    required bool requiresConnection,
                    required bool requiresEthicalAck,
                  }) {
                    openedLabel = label;
                    openedPage = page;
                    requiredAcknowledgement = requiresEthicalAck;
                  },
            );
            return const SizedBox();
          },
        ),
      ),
    );

    screens.last.apps.first.onOpen();

    expect(openedLabel, 'PM3 Tools');
    expect(openedPage, isA<EthicalHackingPage>());
    expect(requiredAcknowledgement, isTrue);
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
    expect(find.byKey(const Key('undercover-dock-phone')), findsOneWidget);
    expect(find.byKey(const Key('undercover-page-home')), findsOneWidget);
  });

  testWidgets('real dashboards render offline on a compact device', (
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

    expect(find.byKey(const Key('undercover-card-weather')), findsOneWidget);
    expect(find.text('Madrid'), findsOneWidget);
    expect(find.text('Selected card'), findsOneWidget);
    expect(find.text('No card selected'), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Device Mode'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.byType(UndercoverSquircleIcon), findsWidgets);
    for (var slot = 1; slot <= 8; slot++) {
      expect(find.byKey(Key('undercover-slot-$slot')), findsNothing);
    }

    const ids = ['home', 'markets', 'recorder', 'studio', 'signals'];
    const expectedLabels = <String, List<String>>{
      'markets': [
        'MFC KEY INDEX',
        'UUID',
        'ATK',
        'SAK',
        'KEYS',
        'Scan HF Card',
        'Run Autopwn',
        'Dictionaries',
        'Save Card',
        'Copy Keys',
        'Copy Dump',
      ],
      'recorder': [
        'HF CAPTURE',
        'Observed',
        'Stored',
        'Dropped',
        'BUFFER 0%',
        'Emulation',
        'Passive Sniff',
        'Reader Mode',
        'Start Capture',
        'Select Slot',
        'Probe Reader',
        'Recover Session',
        'Reload Slots',
      ],
      'studio': [
        'HF EMULATION',
        'Slot UID',
        'Random UID',
        'Custom UID',
        'Start Emulation',
        'Captured Nonces',
        'Recovered Keys',
        'Recovered Sectors',
        'Reload Slots',
      ],
      'signals': [
        'HF 14A SNIFF',
        'OUTGOING',
        'INCOMING',
        'NONCES',
        'Duration',
        '5s',
        'Start Sniff',
        'Packets / Nonces',
        '0 / 0',
      ],
    };
    for (var page = 0; page < ids.length; page++) {
      final dashboard = find.byKey(Key('undercover-dashboard-${ids[page]}'));
      expect(dashboard, findsOneWidget);
      for (final label in expectedLabels[ids[page]] ?? const <String>[]) {
        expect(
          find.descendant(of: dashboard, matching: find.text(label)),
          findsOneWidget,
          reason: '${ids[page]}: $label',
        );
      }
      if (ids[page] == 'markets') {
        expect(
          find.descendant(
            of: dashboard,
            matching: find.byKey(const Key('undercover-recovery-stock-chart')),
          ),
          findsOneWidget,
        );
        for (final removedLabel in const [
          'Scan LF Card',
          'View Keys',
          'View Sectors',
          'Partial Result',
          'Detected HF Card',
          'Autopwn Status',
        ]) {
          expect(
            find.descendant(of: dashboard, matching: find.text(removedLabel)),
            findsNothing,
            reason: 'removed Key Recovery control: $removedLabel',
          );
        }
      }
      if (ids[page] == 'recorder') {
        expect(
          find.descendant(
            of: dashboard,
            matching: find.byKey(const Key('undercover-capture-status')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dashboard,
            matching: find.byKey(const Key('undercover-capture-signal')),
          ),
          findsOneWidget,
        );
        for (final removedLabel in const [
          'Observed Frames',
          'Stored Frames',
          'Dropped Frames',
          'Recent Captured Frames',
          'Capture Slot',
        ]) {
          expect(
            find.descendant(of: dashboard, matching: find.text(removedLabel)),
            findsNothing,
            reason: 'removed HF Capture control: $removedLabel',
          );
        }
      }
      if (ids[page] == 'signals') {
        for (final key in const [
          Key('undercover-activity-review'),
          Key('undercover-activity-pulse'),
        ]) {
          expect(
            find.descendant(of: dashboard, matching: find.byKey(key)),
            findsOneWidget,
          );
        }
        for (final removedLabel in const [
          'Quick',
          'Standard',
          'Extended',
          'Run Review',
          'Outgoing',
          'Incoming',
          'Pending',
          'Total',
          'Activity Summary',
          'View Activity',
          'Copy Details',
          'View Frames',
          'Copy Raw Data',
          'Captured Nonces',
          'Reader to Card',
          'Card to Reader',
          'Total Frames',
          'HF Capture Summary',
          'Capture Duration',
        ]) {
          expect(
            find.descendant(of: dashboard, matching: find.text(removedLabel)),
            findsNothing,
            reason: 'removed HF 14A sniff control: $removedLabel',
          );
        }
      }
      if (ids[page] == 'studio') {
        for (final key in const [
          Key('undercover-emulation-activity'),
          Key('undercover-emulation-activity-rings'),
          Key('undercover-emulation-slot-selector'),
          Key('undercover-emulation-slot-previous'),
          Key('undercover-emulation-slot-next'),
        ]) {
          expect(
            find.descendant(of: dashboard, matching: find.byKey(key)),
            findsOneWidget,
          );
        }
        for (var slot = 1; slot <= 8; slot++) {
          expect(
            find.descendant(
              of: dashboard,
              matching: find.byKey(Key('undercover-emulation-slot-$slot')),
            ),
            findsNothing,
          );
        }
        expect(
          find.descendant(of: dashboard, matching: find.text('Device Mode')),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull, reason: ids[page]);
      if (page == ids.length - 1) break;
      await tester.tap(find.byKey(Key('undercover-page-${ids[page + 1]}')));
      await tester.pumpAndSettle();
    }
    expect(find.text('HF Sniffing'), findsNothing);
  });

  testWidgets('HF 14A sniff reflows at constrained height with insets', (
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
            builder: (context) {
              final media = MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.6),
                padding: const EdgeInsets.only(top: 24, bottom: 20),
                viewPadding: const EdgeInsets.only(top: 24, bottom: 20),
              );
              return MediaQuery(
                data: media,
                child: const SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 320,
                      height: 420,
                      child: UndercoverSniffDashboard(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('HF 14A SNIFF'), findsOneWidget);
    expect(find.byKey(const Key('undercover-activity-pulse')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled icons keep their glyph and show their value', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 84,
            child: UndercoverGridTile(
              label: 'Captured Frames',
              value: '12',
              icon: Icons.sensors,
              color: Colors.blue,
              enabled: false,
            ),
          ),
        ),
      ),
    );

    final squircle = tester.widget<UndercoverSquircleIcon>(
      find.byType(UndercoverSquircleIcon),
    );
    expect(squircle.enabled, isFalse);
    expect(squircle.icon, Icons.sensors);
    expect(find.byIcon(Icons.sensors), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('card screen shows the active card and toggles device mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _CardScreenCommunicator();
    final appState = ChameleonGUIState(preferences)
      ..communicator = communicator;
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(home: UndercoverSlotsDashboard()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Office Pass'), findsOneWidget);
    expect(find.text('Reader Mode'), findsOneWidget);

    await tester.tap(find.byKey(const Key('undercover-device-mode')));
    await tester.pumpAndSettle();

    expect(communicator.readerMode, isFalse);
    expect(find.text('Emulation'), findsOneWidget);
  });

  testWidgets(
    'HF emulation navigates slots and restores a temporary custom UID',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesProvider();
      await preferences.load();
      final communicator = _EmulationCommunicator();
      final appState = ChameleonGUIState(preferences)
        ..connector = (_ConnectedSerial()..connected = true)
        ..communicator = communicator;
      addTearDown(appState.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ChameleonGUIState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(body: UndercoverEmulationDashboard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Office Pass'), findsWidgets);
      expect(find.text('Start Recovery'), findsOneWidget);
      await tester.tap(find.byKey(const Key('undercover-emulation-slot-next')));
      await tester.pump();
      expect(find.text('Lab Tag'), findsWidgets);
      await tester.tap(
        find.byKey(const Key('undercover-emulation-random-uid')),
      );
      await tester.pump();
      expect(find.text('7B'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('undercover-emulation-slot-previous')),
      );
      await tester.pump();
      expect(find.text('Office Pass'), findsWidgets);
      expect(find.text('4B'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('undercover-emulation-custom-uid')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('undercover-emulation-custom-uid-field')),
        'DE AD BE EF',
      );
      await tester.tap(
        find.byKey(const Key('undercover-emulation-custom-uid-apply')),
      );
      await tester.pumpAndSettle();

      expect(find.text('DE AD BE EF'), findsOneWidget);
      await tester.tap(find.byKey(const Key('undercover-routine-toggle')));
      await tester.pumpAndSettle();

      expect(communicator.readerMode, isFalse);
      expect(
        communicator.antiCollision.uid,
        orderedEquals([0xDE, 0xAD, 0xBE, 0xEF]),
      );
      expect(communicator.randomUidMode, isFalse);
      expect(communicator.useFirstBlockUid, isFalse);
      expect(communicator.detectionEnabled, isTrue);
      expect(communicator.animationEnabled, isTrue);

      communicator.failNextAntiCollisionWrite = true;
      await tester.tap(find.byKey(const Key('undercover-routine-toggle')));
      await tester.pumpAndSettle();

      expect(communicator.readerMode, isTrue);
      expect(find.text('Restore UID'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('undercover-emulation-reload-or-restore')),
      );
      await tester.pumpAndSettle();

      expect(communicator.readerMode, isTrue);
      expect(
        communicator.antiCollision.uid,
        orderedEquals([0x04, 0x11, 0x22, 0x33]),
      );
      expect(communicator.randomUidMode, isTrue);
      expect(communicator.useFirstBlockUid, isTrue);
      expect(communicator.detectionEnabled, isFalse);
      expect(communicator.animationEnabled, isFalse);
      expect(communicator.antiCollisionWrites, 2);
      expect(find.text('Device Mode'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('HF recovery starts without optional random UID commands', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _EmulationCommunicator(
      supportsRandomUidCommands: false,
    );
    final appState = ChameleonGUIState(preferences)
      ..connector = (_ConnectedSerial()..connected = true)
      ..communicator = communicator;
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(
          home: Scaffold(body: UndercoverEmulationDashboard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('undercover-routine-toggle')));
    await tester.pumpAndSettle();

    expect(communicator.readerMode, isFalse);
    expect(communicator.detectionEnabled, isTrue);

    await tester.tap(find.byKey(const Key('undercover-routine-toggle')));
    await tester.pumpAndSettle();
    expect(communicator.readerMode, isTrue);
    expect(communicator.detectionEnabled, isFalse);
  });

  testWidgets('HF 14A sniff cycles duration, captures, and copies frames', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    String? copiedFrames;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedFrames =
            (call.arguments as Map<Object?, Object?>)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _ActivityReviewCommunicator();
    final appState = ChameleonGUIState(preferences)
      ..connector = (_ConnectedSerial()..connected = true)
      ..communicator = communicator;
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(
          home: Scaffold(body: UndercoverSniffDashboard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('undercover-sniff-duration')));
    await tester.pump();
    expect(find.text('10s'), findsOneWidget);
    await tester.tap(find.byKey(const Key('undercover-activity-run')));
    await tester.pumpAndSettle();

    expect(communicator.lastTimeoutMs, 10000);
    expect(communicator.readerMode, isTrue);
    expect(find.text('CAPTURED'), findsOneWidget);
    expect(find.text('1 / 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('undercover-sniff-counter')));
    await tester.pump();
    expect(copiedFrames, '00000000800401002600');

    communicator.failNextReview = true;
    await tester.tap(find.byKey(const Key('undercover-activity-run')));
    await tester.pumpAndSettle();

    expect(find.text('CAPTURED'), findsNothing);
    expect(find.text('0 / 0'), findsOneWidget);
    final counter = tester.widget<UndercoverGridTile>(
      find.byKey(const Key('undercover-sniff-counter')),
    );
    expect(counter.enabled, isFalse);
  });

  testWidgets('Key Recovery stocks show card values after an HF scan', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final appState = ChameleonGUIState(preferences)
      ..communicator = _RecoveryStockCommunicator();
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(home: UndercoverRecoveryDashboard()),
      ),
    );
    await tester.pump();

    expect(find.text('--'), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('undercover-recovery-hf')));
    await tester.pumpAndSettle();

    expect(find.text('DEADBEEF'), findsOneWidget);
    expect(find.text('0400'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('0/32'), findsOneWidget);
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

    expect(find.text('Reader'), findsOneWidget);
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
    expect(find.byIcon(Icons.sensors), findsWidgets);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
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
    expect(find.byIcon(Icons.sensors), findsWidgets);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
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

    await tester.tap(find.byKey(const Key('undercover-dock-chrome')));
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

  testWidgets('six pages fit compact SpringBoard above the fixed dock', (
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
              screens: List.generate(
                6,
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

    expect(find.byKey(const Key('undercover-dock-phone')), findsOneWidget);
    expect(find.byKey(const Key('undercover-dock-messages')), findsOneWidget);
    expect(find.byKey(const Key('undercover-dock-camera')), findsOneWidget);
    expect(find.byKey(const Key('undercover-dock-chrome')), findsOneWidget);

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

class _CardScreenCommunicator extends ChameleonCommunicator {
  _CardScreenCommunicator() : super(Logger());

  bool readerMode = true;

  @override
  Future<int> getActiveSlot() async => 0;

  @override
  Future<List<SlotNames>> getSlotTagNames() async => List.generate(
    8,
    (index) => SlotNames(hf: index == 0 ? 'Office Pass' : 'Card ${index + 1}'),
  );

  @override
  Future<List<SlotTypes>> getSlotTagTypes() async => List.generate(
    8,
    (index) => SlotTypes(hf: index == 0 ? TagType.mifare1K : TagType.unknown),
  );

  @override
  Future<List<EnabledSlotInfo>> getEnabledSlots() async =>
      List.generate(8, (index) => EnabledSlotInfo(hf: index == 0));

  @override
  Future<bool> isReaderDeviceMode() async => readerMode;

  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {
    this.readerMode = readerMode;
  }
}

class _RecoveryStockCommunicator extends ChameleonCommunicator {
  _RecoveryStockCommunicator() : super(Logger());

  @override
  Future<bool> isReaderDeviceMode() async => true;

  @override
  Future<CardData?> scan14443aTag() async => CardData(
    uid: Uint8List.fromList(const [0xDE, 0xAD, 0xBE, 0xEF]),
    sak: 0x20,
    atqa: Uint8List.fromList(const [0x04, 0x00]),
    ats: Uint8List(0),
  );

  @override
  Future<bool> detectMf1Support() async => false;
}

class _ActivityReviewCommunicator extends ChameleonCommunicator {
  _ActivityReviewCommunicator() : super(Logger(level: Level.off));

  bool readerMode = true;
  bool failNextReview = false;
  int? lastTimeoutMs;

  @override
  bool? supportsCommandSync(ChameleonCommand command) =>
      command == ChameleonCommand.hf14aSniff
      ? true
      : super.supportsCommandSync(command);

  @override
  Future<bool> isReaderDeviceMode() async => readerMode;

  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {
    this.readerMode = readerMode;
  }

  @override
  Future<Uint8List> hf14aSniff({int timeoutMs = 5000}) async {
    lastTimeoutMs = timeoutMs;
    if (failNextReview) {
      failNextReview = false;
      throw StateError('Simulated activity review failure');
    }
    return Uint8List.fromList(const [0x00, 0x08, 0x26]);
  }
}

class _EmulationCommunicator extends ChameleonCommunicator {
  _EmulationCommunicator({this.supportsRandomUidCommands = true})
    : super(Logger(level: Level.off));

  final bool supportsRandomUidCommands;
  int activeSlot = 0;
  bool readerMode = true;
  bool randomUidMode = true;
  bool useFirstBlockUid = true;
  bool failNextAntiCollisionWrite = false;
  bool detectionEnabled = false;
  bool animationEnabled = false;
  int antiCollisionWrites = 0;
  CardData antiCollision = CardData(
    uid: Uint8List.fromList(const [0x04, 0x11, 0x22, 0x33]),
    sak: 0x08,
    atqa: Uint8List.fromList(const [0x04, 0x00]),
    ats: Uint8List(0),
  );

  @override
  bool? supportsCommandSync(ChameleonCommand command) => switch (command) {
    ChameleonCommand.mf1GetRandomUidMode ||
    ChameleonCommand.mf1SetRandomUidMode => supportsRandomUidCommands,
    _ => super.supportsCommandSync(command),
  };

  @override
  Future<int> getActiveSlot() async => activeSlot;

  @override
  Future<void> activateSlot(int slot) async {
    activeSlot = slot;
  }

  @override
  Future<List<SlotNames>> getSlotTagNames() async => List.generate(
    8,
    (index) => SlotNames(
      hf: switch (index) {
        0 => 'Office Pass',
        2 => 'Lab Tag',
        _ => 'Slot ${index + 1}',
      },
    ),
  );

  @override
  Future<List<SlotTypes>> getSlotTagTypes() async => List.generate(
    8,
    (index) => SlotTypes(
      hf: switch (index) {
        0 => TagType.mifare1K,
        2 => TagType.ntag213,
        _ => TagType.unknown,
      },
    ),
  );

  @override
  Future<List<EnabledSlotInfo>> getEnabledSlots() async => List.generate(
    8,
    (index) => EnabledSlotInfo(hf: index == 0 || index == 2),
  );

  @override
  Future<bool> isReaderDeviceMode() async => readerMode;

  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {
    this.readerMode = readerMode;
  }

  @override
  Future<CardData> mf1GetAntiCollData() async => CardData(
    uid: Uint8List.fromList(antiCollision.uid),
    sak: antiCollision.sak,
    atqa: Uint8List.fromList(antiCollision.atqa),
    ats: Uint8List.fromList(antiCollision.ats),
  );

  @override
  Future<void> setMf1AntiCollision(CardData card) async {
    if (failNextAntiCollisionWrite) {
      failNextAntiCollisionWrite = false;
      throw StateError('Simulated anti-collision write failure');
    }
    antiCollisionWrites++;
    antiCollision = CardData(
      uid: Uint8List.fromList(card.uid),
      sak: card.sak,
      atqa: Uint8List.fromList(card.atqa),
      ats: Uint8List.fromList(card.ats),
    );
  }

  @override
  Future<bool> getMf1RandomUidMode() async {
    if (!supportsRandomUidCommands) throw UnsupportedError('Random UID');
    return randomUidMode;
  }

  @override
  Future<void> setMf1RandomUidMode(bool enabled) async {
    if (!supportsRandomUidCommands) throw UnsupportedError('Random UID');
    randomUidMode = enabled;
  }

  @override
  Future<bool> isMf1UseFirstBlockColl() async => useFirstBlockUid;

  @override
  Future<void> setMf1UseFirstBlockColl(bool useColl) async {
    useFirstBlockUid = useColl;
  }

  @override
  Future<void> setMf1DetectionStatus(bool status) async {
    detectionEnabled = status;
  }

  @override
  Future<void> setMf1ReaderKeysAnim(bool enabled) async {
    animationEnabled = enabled;
  }

  @override
  Future<int> getMf1DetectionCount() async => 0;

  @override
  Future<List<DetectionResult>> getMf1DetectionRecords(
    int count, {
    int startIndex = 0,
  }) async => const [];
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
