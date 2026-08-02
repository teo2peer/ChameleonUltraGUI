import 'package:chameleonultragui/gui/page/mifare_classic_nonce_history.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ChameleonGUIState> buildAppState() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    return ChameleonGUIState(preferences);
  }

  testWidgets('settings exposes the nonce history control', (tester) async {
    final appState = await buildAppState();
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

    expect(
      find.text('Remember MIFARE Classic nonces and failed keys'),
      findsOneWidget,
    );
    expect(find.text('Manage stored recovery history'), findsOneWidget);
    final toggle = find.text('Remember MIFARE Classic nonces and failed keys');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    expect(
      appState.sharedPreferencesProvider.getMifareClassicNonceHistoryEnabled(),
      isTrue,
    );
  });

  testWidgets('history can be deleted by UID', (tester) async {
    final appState = await buildAppState();
    addTearDown(appState.dispose);
    final preferences = appState.sharedPreferencesProvider;
    await preferences.setMifareClassicNonceHistoryEnabled(true);
    await preferences.recordMifareClassicNonceSample(
      '04 11 22 33',
      'weak|capture-one',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(home: MifareClassicNonceHistoryPage()),
      ),
    );

    expect(find.text('UID 04112233'), findsOneWidget);
    expect(find.textContaining('1 nonce samples'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text('No MIFARE Classic recovery history is stored.'),
      findsOneWidget,
    );
  });
}
