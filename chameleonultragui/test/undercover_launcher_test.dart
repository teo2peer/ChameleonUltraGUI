import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/undercover/undercover_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launcher opens benign facades without exposing product labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(const UndercoverLauncher(connected: true, onExitRequested: _noop)),
    );

    expect(find.byKey(const Key('undercover-launcher')), findsOneWidget);
    expect(find.textContaining('Chameleon'), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);

    await tester.tap(find.byKey(const Key('undercover-app-wallet')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('undercover-facade')), findsOneWidget);
    expect(find.text('Daily card'), findsOneWidget);
    expect(find.textContaining('Slot'), findsNothing);
  });

  testWidgets('long pressing the calendar requests the concealed exit', (
    tester,
  ) async {
    var exits = 0;
    await tester.pumpWidget(
      _app(
        UndercoverLauncher(connected: false, onExitRequested: () => exits++),
      ),
    );

    await tester.longPress(find.byKey(const Key('undercover-exit-anchor')));
    await tester.pump();

    expect(exits, 1);
  });

  testWidgets('escape closes a facade before requesting exit', (tester) async {
    var exits = 0;
    await tester.pumpWidget(
      _app(UndercoverLauncher(connected: true, onExitRequested: () => exits++)),
    );

    await tester.tap(find.byKey(const Key('undercover-app-wallet')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('undercover-facade')), findsNothing);
    expect(exits, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('launcher remains responsive on tablet and desktop widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [Size(768, 1024), Size(1024, 768)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _app(
          MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.3),
            ),
            child: const UndercoverLauncher(
              connected: true,
              onExitRequested: _noop,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('undercover-launcher')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    const narrowSize = Size(320, 568);
    await tester.binding.setSurfaceSize(narrowSize);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(
            size: narrowSize,
            textScaler: TextScaler.linear(2),
          ),
          child: const UndercoverLauncher(
            connected: true,
            onExitRequested: _noop,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('undercover-app-wallet')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);
