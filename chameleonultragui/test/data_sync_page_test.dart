import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/page/data_sync.dart';
import 'package:chameleonultragui/helpers/data_sync.dart';
import 'package:chameleonultragui/helpers/data_sync_storage.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferencesProvider> preferences() async {
    SharedPreferences.setMockInitialValues({});
    final result = SharedPreferencesProvider();
    await result.load();
    return result;
  }

  Widget localized(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  testWidgets('page exposes nearby and encrypted file actions', (tester) async {
    final prefs = await preferences();
    final app = ChameleonGUIState(prefs);
    addTearDown(app.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      localized(
        ChangeNotifierProvider<ChameleonGUIState>.value(
          value: app,
          child: const DataSyncPage(),
        ),
      ),
    );

    expect(find.text('Data Sync'), findsOneWidget);
    expect(find.text('Host nearby sync'), findsWidgets);
    expect(find.text('Join nearby sync'), findsWidgets);
    expect(find.text('Create and share file'), findsOneWidget);
    expect(find.text('Import sync file'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Join nearby sync').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('data-sync-pairing-code')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('file password requires length and matching confirmation', (
    tester,
  ) async {
    final prefs = await preferences();
    final app = ChameleonGUIState(prefs);
    addTearDown(app.dispose);

    await tester.pumpWidget(
      localized(
        ChangeNotifierProvider<ChameleonGUIState>.value(
          value: app,
          child: const DataSyncPage(),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Create and share file'));
    await tester.tap(find.text('Create and share file'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('data-sync-password')),
      'short',
    );
    await tester.enterText(
      find.byKey(const Key('data-sync-password-confirm')),
      'short',
    );
    await tester.tap(find.text('Create file'));
    await tester.pump();
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('data-sync-password')),
      'long-enough',
    );
    await tester.enterText(
      find.byKey(const Key('data-sync-password-confirm')),
      'different',
    );
    await tester.tap(find.text('Create file'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('setting conflict can select the remote value', (tester) async {
    final plan = SyncMergePlan.merge(
      SyncSnapshot(settings: const {'theme': 'local'}),
      SyncSnapshot(settings: const {'theme': 'remote'}),
    );
    SyncSnapshot? result;

    await tester.pumpWidget(
      localized(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDataSyncConflictDialog(
                  context,
                  plan,
                  actionLabel: 'Apply test merge',
                );
              },
              child: const Text('Open conflicts'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open conflicts'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Every distinct key'), findsOneWidget);
    expect(find.text('Remote: "remote"'), findsOneWidget);
    await tester.tap(find.text('Remote: "remote"'));
    await tester.tap(find.text('Apply test merge'));
    await tester.pumpAndSettle();

    expect(result?.settings['theme'], 'remote');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('decided coordinator recovery is surfaced on the page', (
    tester,
  ) async {
    final prefs = await preferences();
    final source = await prefs.createSyncState();
    await prefs.prepareSyncSnapshot(
      'visible-recovery',
      source.snapshot,
      expectedCheckpoint: source.checkpoint,
      role: SyncTransactionRole.coordinator,
      peerCheckpoint: source.checkpoint,
    );
    await prefs.commitDataSyncTransaction('visible-recovery');
    final app = ChameleonGUIState(prefs);
    addTearDown(app.dispose);

    await tester.pumpWidget(
      localized(
        ChangeNotifierProvider<ChameleonGUIState>.value(
          value: app,
          child: const DataSyncPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('awaiting peer confirmation'), findsOneWidget);
    expect(find.textContaining('visible-recovery'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'pending participant requires coordinator resume and shows transaction ID',
    (tester) async {
      final prefs = await preferences();
      final source = await prefs.createSyncState();
      await prefs.prepareSyncSnapshot(
        'participant-to-abort',
        source.snapshot,
        expectedCheckpoint: source.checkpoint,
      );
      final app = ChameleonGUIState(prefs);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        localized(
          ChangeNotifierProvider<ChameleonGUIState>.value(
            value: app,
            child: const DataSyncPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('participant-to-abort'), findsOneWidget);
      expect(find.textContaining('authenticated coordinator'), findsOneWidget);
      expect(find.text('Abort pending sync'), findsNothing);
      expect(
        (await prefs.getDataSyncTransactionReceipt(
          'participant-to-abort',
        ))?.outcome,
        SyncTransactionOutcome.prepared,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
