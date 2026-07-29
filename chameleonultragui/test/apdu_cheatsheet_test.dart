import 'package:chameleonultragui/gui/component/apdu_cheatsheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('APDU cheat sheet expands and selects concrete examples',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ApduCheatSheet(onExampleSelected: (value) => selected = value),
        ),
      ),
    ));

    await tester.tap(find.text('APDU cheat sheet'));
    await tester.pumpAndSettle();
    expect(find.text('COMMON EMV COMMANDS'), findsOneWidget);
    expect(find.text('SYNTHETIC RELAY LAB'), findsOneWidget);
    expect(find.text('GENERATE AC'), findsOneWidget);

    await tester.tap(find.text('SELECT PPSE'));
    expect(selected, '00A404000E325041592E5359532E444446303100');
  });

  testWidgets('relay legend omits standard EMV command section',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ApduCheatSheet(showEmv: false),
        ),
      ),
    ));
    await tester.tap(find.text('APDU cheat sheet'));
    await tester.pumpAndSettle();

    expect(find.text('COMMON EMV COMMANDS'), findsNothing);
    expect(find.text('SYNTHETIC RELAY LAB'), findsOneWidget);
    expect(find.text('Any private APDU'), findsOneWidget);
  });
}
