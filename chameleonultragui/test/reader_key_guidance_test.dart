import 'package:chameleonultragui/helpers/mifare_classic/reader_key_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReaderKeyGuidance guidance({
    bool connected = true,
    bool armed = false,
    bool busy = false,
    bool recovering = false,
    bool randomUid = false,
    int detectionCount = 0,
    int resultCount = 0,
    int appliedTargetCount = 0,
    bool automatic = false,
  }) {
    return readerKeyGuidanceFor(
      connected: connected,
      armed: armed,
      busy: busy,
      recovering: recovering,
      randomUid: randomUid,
      detectionCount: detectionCount,
      resultCount: resultCount,
      appliedTargetCount: appliedTargetCount,
      automatic: automatic,
    );
  }

  test('asks the user to approach only after capture is armed', () {
    expect(guidance().step, ReaderKeyGuidanceStep.ready);
    expect(guidance(armed: true).title, 'Acerca y mantén en el lector');
  });

  test('asks the user to remove after detecting an authentication', () {
    expect(guidance(armed: true, detectionCount: 1).title, 'Aleja del lector');
  });

  test('shows processing and iterative presentation guidance', () {
    expect(
      guidance(armed: true, recovering: true).title,
      'Procesando capturas...',
    );
    expect(
      guidance(armed: true, detectionCount: 2, appliedTargetCount: 2).title,
      'Aleja y vuelve a acercar',
    );
  });

  test('starts a rearmed session by asking the user to approach', () {
    expect(
      guidance(armed: true, appliedTargetCount: 2).title,
      'Acerca y mantén en el lector',
    );
  });

  test('automatic mode keeps the device in place and stops after idle', () {
    expect(
      guidance(
        armed: true,
        detectionCount: 2,
        appliedTargetCount: 1,
        automatic: true,
      ).title,
      'Reintentando automáticamente',
    );
    final lastEvidence = DateTime(2026, 8, 2, 12);
    expect(
      readerKeyCaptureShouldAutoStop(
        automatic: true,
        armed: true,
        busy: false,
        recovering: false,
        recoveredKeyCount: 1,
        lastEvidenceAt: lastEvidence,
        now: lastEvidence.add(const Duration(seconds: 12)),
      ),
      isTrue,
    );
  });
}
