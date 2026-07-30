import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/pm3_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mirrors existing firmware commands used by PM3 interfaces', () {
    expect(ChameleonCommand.hf14ARawCommand.value, 2010);
    expect(ChameleonCommand.hf14aScanKeep.value, 2016);
    expect(ChameleonCommand.hf14aSetFieldOn.value, 2100);
    expect(ChameleonCommand.hf14aSetFieldOff.value, 2101);
    expect(ChameleonCommand.hf14aGetConfig.value, 2200);
    expect(ChameleonCommand.hf14aSetConfig.value, 2201);
    expect(ChameleonCommand.readLfAdc.value, 3009);
    expect(ChameleonCommand.ioProxDecodeRaw.value, 3012);
    expect(ChameleonCommand.ioProxComposeId.value, 3013);
    expect(ChameleonCommand.writeT55xxBlock.value, 3016);
    expect(ChameleonCommand.scanJablotronTag.value, 3019);
    expect(ChameleonCommand.writeJablotronToT5577.value, 3020);
  });

  test('encodes PM3-compatible HF14A raw request flags and lengths', () {
    final request = Pm3Hf14aRawRequest(
      data: Uint8List.fromList([0x26]),
      bitLength: 7,
      responseTimeoutMs: 100,
      activateField: true,
      waitResponse: true,
      appendCrc: false,
      autoSelect: false,
      keepField: true,
      checkResponseCrc: false,
    );

    expect(request.encode(), [0xC8, 0x00, 0x64, 0x00, 0x07, 0x26]);
  });

  test('rejects invalid raw frame and CRC combinations', () {
    Pm3Hf14aRawRequest request({
      required Uint8List data,
      required int bits,
      bool appendCrc = false,
    }) => Pm3Hf14aRawRequest(
      data: data,
      bitLength: bits,
      responseTimeoutMs: 100,
      activateField: true,
      waitResponse: true,
      appendCrc: appendCrc,
      autoSelect: false,
      keepField: false,
      checkResponseCrc: false,
    );

    expect(
      () => request(data: Uint8List(0), bits: 1).encode(),
      throwsArgumentError,
    );
    expect(
      () => request(data: Uint8List.fromList([0x26]), bits: 9).encode(),
      throwsRangeError,
    );
    expect(
      () => request(
        data: Uint8List.fromList([0x26]),
        bits: 7,
        appendCrc: true,
      ).encode(),
      throwsArgumentError,
    );
    expect(
      () =>
          request(data: Uint8List(63), bits: 63 * 8, appendCrc: true).encode(),
      throwsRangeError,
    );
  });

  test('HF14A config accepts only firmware enum values', () {
    const config = Pm3Hf14aConfig(uidCl1: 0, uidCl2: 1, uidCl3: 2, rats: 0);

    expect(config.encode(), [0, 1, 2, 0]);
    expect(Pm3Hf14aConfig.decode(config.encode()).uidCl3, 2);
    expect(
      () => const Pm3Hf14aConfig(
        uidCl1: 3,
        uidCl2: 0,
        uidCl3: 0,
        rats: 0,
      ).encode(),
      throwsRangeError,
    );
    expect(() => Pm3Hf14aConfig.decode(Uint8List(3)), throwsFormatException);
    expect(
      () => Pm3Hf14aConfig.decode(Uint8List.fromList([0, 1, 3, 0])),
      throwsRangeError,
    );
  });

  test('decodes the documented ioProx firmware layout', () {
    final value = Pm3IoProxData.decode(
      Uint8List.fromList([
        2,
        17,
        0x12,
        0x34,
        0x00,
        0xf0,
        17,
        2,
        0x12,
        0x34,
        0xaa,
        0xbb,
        0,
        0,
        0,
        0,
      ]),
    );

    expect(value.version, 2);
    expect(value.facilityCode, 17);
    expect(value.cardNumber, 0x1234);
    expect(value.raw, [0x00, 0xf0, 17, 2, 0x12, 0x34, 0xaa, 0xbb]);
  });
}
