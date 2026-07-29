import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/nested.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpNestedPage(
    WidgetTester tester,
    NestedVariant variant,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NestedPage(variant: variant),
      ),
    );
    await tester.pump();
  }

  testWidgets('static encrypted nonce variant does not require a known key', (
    tester,
  ) async {
    await pumpNestedPage(tester, NestedVariant.staticEncryptedNonce);

    expect(find.text('Static Encrypted Nested'), findsOneWidget);
    expect(
      find.text(
        'Fudan FM11RF08S static-encrypted nested via the factory backdoor',
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Recover key'), findsOneWidget);
  });

  testWidgets('known-key nested variants retain their recovery inputs', (
    tester,
  ) async {
    for (final variant in [
      NestedVariant.weak,
      NestedVariant.staticNonce,
      NestedVariant.hard,
    ]) {
      await pumpNestedPage(tester, variant);
      expect(find.byType(TextField), findsNWidgets(3));
    }
  });
}
