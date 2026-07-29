import 'dart:typed_data';

import 'package:chameleonultragui/helpers/ble/ble_advertising.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structured profile encodes operator values in Bluetooth byte order',
      () {
    final profile = bleBuildAdvertisingProfile(
      serviceUuid: 0x180f,
      companyId: 0x1234,
      manufacturerData: Uint8List.fromList([0xaa, 0xbb]),
    );

    expect(profile.advertising, [0x02, 0x01, 0x06, 0x03, 0x03, 0x0f, 0x18]);
    expect(profile.scanResponse, [0x05, 0xff, 0x34, 0x12, 0xaa, 0xbb]);
  });

  test('structured profile supports generic 16-bit service data', () {
    final profile = bleBuildAdvertisingProfile(
      serviceUuid: 0x181a,
      serviceDataUuid: 0x181a,
      serviceData: Uint8List.fromList([1, 2]),
    );
    expect(profile.advertising, [0x02, 0x01, 0x06, 0x03, 0x03, 0x1a, 0x18]);
    expect(profile.scanResponse, [0x05, 0x16, 0x1a, 0x18, 1, 2]);
    expect(
        () => bleBuildAdvertisingProfile(serviceData: Uint8List.fromList([1])),
        throwsFormatException);
  });

  test('pairing discovery profiles produce complete legacy packets', () {
    final apple = bleBuildAppleProximityProfile(modelCode: 0x0e20);
    expect(apple.advertising.length, 31);
    expect(apple.advertising.sublist(0, 9),
        [0x1e, 0xff, 0x4c, 0, 7, 0x19, 7, 0x0e, 0x20]);

    final android = bleBuildFastPairProfile(modelId: 0x2d7a23);
    expect(android.advertising, [
      2,
      1,
      6,
      3,
      3,
      0x2c,
      0xfe,
      6,
      0x16,
      0x2c,
      0xfe,
      0x2d,
      0x7a,
      0x23,
      2,
      0x0a,
      0xec,
    ]);
  });

  test('rotating names produce the versioned big-endian request', () {
    final config = BleAdvertisingLabConfig(
      profile: BleAdvertisingProfile.rotating,
      mode: BleAdvertisingMode.scannable,
      nameTarget: BleAdvertisingNameTarget.advertisement,
      advertisingData: Uint8List.fromList([0x02, 0x01, 0x06]),
      scanResponseData: Uint8List(0),
      names: const ['Lab A', 'Lab B'],
      intervalMs: 100,
      rotationMs: 1000,
    );

    expect(config.toWire(), [
      1,
      2,
      1,
      1,
      0,
      160,
      3,
      232,
      0,
      0,
      0,
      3,
      0,
      2,
      2,
      1,
      6,
      5,
      76,
      97,
      98,
      32,
      65,
      5,
      76,
      97,
      98,
      32,
      66,
    ]);
    expect(config.previewPackets().advertising,
        [2, 1, 6, 6, 9, 76, 97, 98, 32, 65]);
  });

  test('raw editor rejects truncated and oversized structures', () {
    expect(
      () => bleValidateAdvertisingData(Uint8List.fromList([0x05, 0x09, 0x41])),
      throwsFormatException,
    );
    expect(
      () => bleValidateAdvertisingData(Uint8List(32)),
      throwsFormatException,
    );
    expect(
      () => bleValidateAdvertisingData(Uint8List.fromList([0x02, 0x01, 0x06]),
          scanResponse: true),
      throwsFormatException,
    );
  });

  test('rotation validation uses the quantized advertising interval', () {
    final config = BleAdvertisingLabConfig(
      profile: BleAdvertisingProfile.rotating,
      mode: BleAdvertisingMode.scannable,
      nameTarget: BleAdvertisingNameTarget.advertisement,
      advertisingData: Uint8List.fromList([2, 1, 6]),
      scanResponseData: Uint8List(0),
      names: const ['A', 'B'],
      intervalMs: 101,
      rotationMs: 101,
    );
    expect(config.toWire, throwsFormatException);
  });

  test('status parser rejects malformed frames and exposes rotation count', () {
    expect(() => BleAdvertisingLabStatus.fromWire(Uint8List(19)),
        throwsFormatException);
    final status = BleAdvertisingLabStatus.fromWire(Uint8List.fromList([
      1,
      2,
      2,
      1,
      0,
      1,
      2,
      10,
      6,
      0,
      160,
      3,
      232,
      0,
      0,
      0,
      0,
      0,
      0,
      7,
    ]));
    expect(status.running, isTrue);
    expect(status.profile, BleAdvertisingProfile.rotating);
    expect(status.activeNameIndex, 1);
    expect(status.rotationCount, 7);
  });
}
