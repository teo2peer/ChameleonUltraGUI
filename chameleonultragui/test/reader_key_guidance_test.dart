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
    );
  }

  test('asks the user to approach only after capture is armed', () {
    expect(guidance().step, ReaderKeyGuidanceStep.ready);
    expect(guidance(armed: true).title, 'Acerca al lector');
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
      'Acerca al lector',
    );
  });
}
