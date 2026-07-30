import 'dart:typed_data';

import 'package:chameleonultragui/helpers/pm3_offline_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('data num preserves input width and converts every radix', () {
    final conversion = pm3ConvertNumber('002A', Pm3NumberBase.hexadecimal);

    expect(conversion.decimal, '42');
    expect(conversion.hexadecimal, '2A');
    expect(conversion.binary, '0000000000101010');
    expect(conversion.ascii, '*');
  });

  test('data xor supports explicit and PM3 automatic masks', () {
    final input = Uint8List.fromList([0x99, 0xaa, 0x88, 0x88]);

    expect(pm3Xor(input, Uint8List.fromList([0x88, 0x88, 0x88, 0x88])), [
      0x11,
      0x22,
      0x00,
      0x00,
    ]);
    expect(pm3Xor(input), [0x11, 0x22, 0x00, 0x00]);
    expect(
      () => pm3Xor(input, Uint8List.fromList([0x88])),
      throwsArgumentError,
    );
  });

  test('analyse lrc matches the upstream rolling XOR example', () {
    expect(pm3Lrc(Uint8List.fromList([0x04, 0x00, 0x80, 0x64, 0xba])), 0x5a);
  });

  test('analyse chksum matches upstream byte checksum variants', () {
    final result = pm3Checksums(
      Uint8List.fromList([0x13, 0x7a, 0xf0, 0x0a, 0x0a, 0x0d]),
      mask: 0xff,
    );

    expect(result.byteAdd, 0x9e);
    expect(result.byteAddOnesComplement, 0x61);
    expect(result.byteXor, 0x94);
    expect(result.xorComplement, 0x6b);
    expect(
      pm3Checksums(Uint8List.fromList([0x1f]), mask: 0x0f).xorComplement,
      0xf0,
    );
  });

  test('analyse freq matches upstream wavelength and LC formulas', () {
    final bands = pm3FrequencyBands();

    expect(bands.first.wavelengthMeters, closeTo(2398.339664, 0.000001));
    expect(bands.first.nearFieldRangeMeters, closeTo(381.707613, 0.000001));
    expect(
      pm3ResonantFrequency(
        inductanceHenries: 0.001,
        capacitanceFarads: 0.000000001,
      ),
      closeTo(159154.9431, 0.0001),
    );
  });

  test('analyse units matches PM3 ISO14443-A conversion constants', () {
    final fromEtu = pm3UnitsFromEtu(10);
    final fromMicroseconds = pm3UnitsFromMicroseconds(94);

    expect(fromEtu.microseconds, closeTo(94.396, 0.000001));
    expect(fromEtu.sspClock, 320);
    expect(fromMicroseconds.etu, closeTo(9.95805, 0.00001));
    expect(fromMicroseconds.sspClock, 318);
  });

  test('analyse nuid matches both Proxmark3 self-test vectors', () {
    expect(
      pm3GenerateNuid(
        Uint8List.fromList([0x04, 0x0d, 0x68, 0x1a, 0xb5, 0x22, 0x81]),
      ),
      [0x8f, 0x43, 0x0f, 0xef],
    );
    expect(
      pm3GenerateNuid(
        Uint8List.fromList([0x04, 0x18, 0x3f, 0x09, 0x32, 0x1b, 0x85]),
      ),
      [0x4f, 0x50, 0x5d, 0x7d],
    );
  });
}
