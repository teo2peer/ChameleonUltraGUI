import 'dart:typed_data';

import 'package:chameleonultragui/helpers/ble/ble_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ATT security statuses are presented with actionable names', () {
    expect(bleAttStatusDescription(0x05), 'insufficient authentication (0x05)');
    expect(bleAttStatusDescription(0x0F), 'insufficient encryption (0x0F)');
  });
  group('BLE advertising presentation', () {
    test('handles malformed structure bounds without throwing', () {
      final truncated = Uint8List.fromList([0x08, 0x09, 0x43, 0x55]);
      final missingType = Uint8List.fromList([0x03]);

      expect(bleAdvertisingName(truncated), 'CU');
      expect(bleAdvertisingSummary(truncated), isEmpty);
      expect(bleAdvertisingDetails(truncated), ['name: CU']);
      expect(bleAdvertisingName(missingType), isNull);
      expect(bleAdvertisingSummary(missingType), isEmpty);
      expect(bleAdvertisingDetails(missingType), isEmpty);
    });

    test('formats name and compact summary', () {
      final data = Uint8List.fromList([
        2,
        0x01,
        0x06,
        5,
        0x09,
        0x54,
        0x61,
        0x67,
        0x31,
        3,
        0xFF,
        0x4C,
        0x00,
        2,
        0x0A,
        0xF6,
      ]);

      expect(bleAdvertisingName(data), 'Tag1');
      expect(bleAdvertisingSummary(data),
          'LE-gen|no-BR/EDR \u00B7 Apple \u00B7 -10dBm');
    });
  });

  test('formats characteristic properties and write predicates', () {
    expect(bleCharacteristicPropertiesString(0), '-');
    expect(bleCharacteristicPropertiesString(0x3E),
        'read,write-nr,write,notify,indicate');
    expect(bleCanWriteWithResponse(0x08), isTrue);
    expect(bleCanWriteWithResponse(0x04), isFalse);
    expect(bleCanFuzzWithoutResponse(0x04), isTrue);
    expect(bleCanFuzzWithoutResponse(0x08), isFalse);
  });

  test('round-trips hexadecimal bytes', () {
    final bytes = Uint8List.fromList([0x00, 0x7F, 0xA5, 0xFF]);
    final formatted = bleFormatHexBytes(bytes);

    expect(formatted, '007FA5FF');
    expect(bleParseHexBytes(formatted), bytes);
    expect(() => bleParseHexBytes('ABC'), throwsFormatException);
  });

  test('formats device-info battery and padded strings', () {
    expect(bleDeviceInfoLabel(0x2A19), 'Battery Level');
    expect(bleDeviceInfoValue(0x2A19, 0, Uint8List.fromList([87])), '87%');
    expect(
        bleDeviceInfoValue(
            0x2A29, 0, Uint8List.fromList([0x41, 0x63, 0x6D, 0x65, 0, 0])),
        '"Acme"');
  });

  test('parses explicit hexadecimal and decimal numbers', () {
    expect(bleParseHexOrDecimal(' 0x20 '), 32);
    expect(bleParseHexOrDecimal('20'), 20);
    expect(() => bleParseHexOrDecimal('0x'), throwsFormatException);
    expect(() => bleParseHexOrDecimal(''), throwsFormatException);
  });
}
