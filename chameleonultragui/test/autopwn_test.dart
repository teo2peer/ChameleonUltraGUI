import 'package:chameleonultragui/gui/menu/hacking/autopwn.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Autopwn progress tracks terminal phases and overall progress', () {
    final progress = AutopwnRunProgress(exhaustive: true);

    progress.complete(AutopwnPhase.scan, 'Card detected');
    progress.skip(AutopwnPhase.darkside, 'Known key available');
    progress.start(AutopwnPhase.nested, 'Collecting capture', progress: 0.5);

    expect(progress.phase(AutopwnPhase.scan).progress, 1);
    expect(
      progress.phase(AutopwnPhase.darkside).status,
      AutopwnPhaseStatus.skipped,
    );
    expect(
      progress.phase(AutopwnPhase.nested).status,
      AutopwnPhaseStatus.active,
    );
    expect(progress.overallProgress, closeTo(2.5 / 8, 0.0001));
  });

  test('Autopwn finish closes active and pending phases', () {
    final progress = AutopwnRunProgress(exhaustive: false)
      ..complete(AutopwnPhase.scan, 'Card detected')
      ..start(AutopwnPhase.nested, 'Collecting candidates');

    progress.finish();

    expect(
      progress.phase(AutopwnPhase.nested).status,
      AutopwnPhaseStatus.failed,
    );
    expect(
      progress.phase(AutopwnPhase.dump).status,
      AutopwnPhaseStatus.skipped,
    );
    expect(progress.endedAt, isNotNull);
  });

  test('Autopwn errors between phases fail the next pending phase', () {
    final progress = AutopwnRunProgress(exhaustive: false)
      ..complete(AutopwnPhase.scan, 'Card detected')
      ..complete(AutopwnPhase.dictionary, 'Dictionary checked');

    progress.failCurrent('Card disconnected');
    progress.finish();

    expect(
      progress.phase(AutopwnPhase.backdoor).status,
      AutopwnPhaseStatus.failed,
    );
    expect(progress.overallProgress, lessThan(1));
  });

  test('Autopwn can defer a probed phase without progress regression', () {
    final progress = AutopwnRunProgress(exhaustive: false)
      ..start(AutopwnPhase.backdoor, 'Probing backdoor')
      ..defer(AutopwnPhase.backdoor, 'Backdoor available if needed');

    expect(
      progress.phase(AutopwnPhase.backdoor).status,
      AutopwnPhaseStatus.pending,
    );
    expect(progress.overallProgress, 0);

    progress.start(AutopwnPhase.darkside, 'Checking Darkside');
    expect(
      AutopwnPhase.values
          .where(
            (phase) =>
                progress.phase(phase).status == AutopwnPhaseStatus.active,
          )
          .toList(),
      [AutopwnPhase.darkside],
    );
  });

  testWidgets('Autopwn checklist exposes phase status and green completion', (
    tester,
  ) async {
    final progress = AutopwnRunProgress(exhaustive: true);
    progress.complete(AutopwnPhase.scan, 'Card detected');
    progress.start(
      AutopwnPhase.dictionary,
      'Checking sector 1 key A',
      progress: 0.25,
    );
    progress.skip(AutopwnPhase.darkside, 'Known key available');
    progress.fail(AutopwnPhase.nested, 'No candidates');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AutopwnProgressChecklist(progress: progress),
          ),
        ),
      ),
    );

    expect(find.text('Deep recovery checklist'), findsOneWidget);
    expect(
      find.textContaining('Current step: Checking sector 1 key A'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final completedIcon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
    expect(completedIcon.color, Colors.green);
  });

  testWidgets('Autopwn checklist remains usable on a narrow scaled viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final progress = AutopwnRunProgress(exhaustive: true)
      ..start(
        AutopwnPhase.staticNested,
        'Static Nested fallback: sector 16/16 key B',
        progress: 0.7,
      );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: AutopwnProgressChecklist(progress: progress),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('autopwn-progress-checklist')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
