import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/page/ethical_hacking.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Ethical Hacking opens PM3 categories and tool interfaces', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    preferences.setEthicalHackingAck(true);
    final appState = ChameleonGUIState(preferences);
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EthicalHackingPage(),
        ),
      ),
    );

    expect(find.text('PM3 Tools'), findsOneWidget);
    expect(find.text('29 tools'), findsOneWidget);

    await tester.tap(find.text('PM3 Tools'));
    await tester.pumpAndSettle();

    expect(find.text('ISO14443-A'), findsOneWidget);
    expect(find.text('MIFARE Classic'), findsOneWidget);
    expect(find.text('Low frequency'), findsOneWidget);
    expect(find.text('Smart cards'), findsOneWidget);
    expect(find.text('Offline analysis'), findsOneWidget);

    await tester.tap(find.text('ISO14443-A'));
    await tester.pumpAndSettle();

    expect(find.text('PM3 Tools / ISO14443-A'), findsOneWidget);
    expect(find.text('hf 14a info'), findsOneWidget);
    expect(find.text('hf 14a raw'), findsOneWidget);
    expect(find.text('hf 14a apdu'), findsOneWidget);
    expect(find.text('hf 14a sniff'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
