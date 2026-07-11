import 'dart:typed_data';

import 'package:chameleonultragui/helpers/ble/ble_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts display order to SoftDevice little-endian order', () {
    expect(
      bleAddressToLittleEndian('C0:11:22:33:44:55'),
      Uint8List.fromList([0x55, 0x44, 0x33, 0x22, 0x11, 0xC0]),
    );
  });

  test('round trips a BLE address', () {
    const address = 'DA:7A:01:02:03:04';
    expect(
        bleAddressFromLittleEndian(bleAddressToLittleEndian(address)), address);
  });

  test('rejects malformed octets', () {
    expect(
        () => bleAddressToLittleEndian('A:B:C:D:E:F'), throwsFormatException);
    expect(() => bleAddressToLittleEndian('0011:22:33:44:55'),
        throwsFormatException);
  });

  test('validates the static-random high bits', () {
    expect(
      () => bleAddressToLittleEndian('80:11:22:33:44:55',
          requireStaticRandom: true),
      throwsFormatException,
    );
    expect(
      bleAddressToLittleEndian('C0:11:22:33:44:55', requireStaticRandom: true),
      hasLength(6),
    );
  });
}
