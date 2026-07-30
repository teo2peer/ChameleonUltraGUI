import 'dart:typed_data';

const int pm3Hf14aRawMaxBytes = 64;

class Pm3Hf14aRawRequest {
  final Uint8List data;
  final int bitLength;
  final int responseTimeoutMs;
  final bool activateField;
  final bool waitResponse;
  final bool appendCrc;
  final bool autoSelect;
  final bool keepField;
  final bool checkResponseCrc;

  const Pm3Hf14aRawRequest({
    required this.data,
    required this.bitLength,
    required this.responseTimeoutMs,
    required this.activateField,
    required this.waitResponse,
    required this.appendCrc,
    required this.autoSelect,
    required this.keepField,
    required this.checkResponseCrc,
  });

  Uint8List encode() {
    final maximumDataLength = appendCrc
        ? pm3Hf14aRawMaxBytes - 2
        : pm3Hf14aRawMaxBytes;
    if (data.length > maximumDataLength) {
      throw RangeError.range(data.length, 0, maximumDataLength, 'data.length');
    }
    if (responseTimeoutMs < 1 || responseTimeoutMs > 0xffff) {
      throw RangeError.range(responseTimeoutMs, 1, 0xffff, 'responseTimeoutMs');
    }
    if (bitLength < 0 || bitLength > data.length * 8) {
      throw RangeError.range(bitLength, 0, data.length * 8, 'bitLength');
    }
    if (data.isEmpty != (bitLength == 0)) {
      throw ArgumentError('Empty data requires a zero bit length');
    }
    if (data.isNotEmpty && bitLength <= (data.length - 1) * 8) {
      throw ArgumentError('bitLength must include the final data byte');
    }
    if (appendCrc && (bitLength == 0 || bitLength % 8 != 0)) {
      throw ArgumentError('CRC can only be appended to a whole-byte frame');
    }

    var options = 0;
    if (checkResponseCrc) options |= 0x04;
    if (keepField) options |= 0x08;
    if (autoSelect) options |= 0x10;
    if (appendCrc) options |= 0x20;
    if (waitResponse) options |= 0x40;
    if (activateField) options |= 0x80;

    return Uint8List.fromList([
      options,
      responseTimeoutMs >> 8,
      responseTimeoutMs & 0xff,
      bitLength >> 8,
      bitLength & 0xff,
      ...data,
    ]);
  }
}

class Pm3Hf14aRawResponse {
  final int status;
  final Uint8List data;

  const Pm3Hf14aRawResponse({required this.status, required this.data});
}

class Pm3Hf14aConfig {
  final int uidCl1;
  final int uidCl2;
  final int uidCl3;
  final int rats;

  const Pm3Hf14aConfig({
    required this.uidCl1,
    required this.uidCl2,
    required this.uidCl3,
    required this.rats,
  });

  Uint8List encode() {
    for (final value in [uidCl1, uidCl2, uidCl3, rats]) {
      if (value < 0 || value > 2) {
        throw RangeError.range(value, 0, 2, 'HF14A configuration value');
      }
    }
    return Uint8List.fromList([uidCl1, uidCl2, uidCl3, rats]);
  }

  factory Pm3Hf14aConfig.decode(Uint8List data) {
    if (data.length != 4) {
      throw const FormatException(
        'HF14A configuration must contain four bytes',
      );
    }
    final config = Pm3Hf14aConfig(
      uidCl1: data[0],
      uidCl2: data[1],
      uidCl3: data[2],
      rats: data[3],
    );
    config.encode();
    return config;
  }
}

class Pm3IoProxData {
  final int version;
  final int facilityCode;
  final int cardNumber;
  final Uint8List raw;

  const Pm3IoProxData({
    required this.version,
    required this.facilityCode,
    required this.cardNumber,
    required this.raw,
  });

  factory Pm3IoProxData.decode(Uint8List data) {
    if (data.length != 16) {
      throw const FormatException('ioProx response must contain 16 bytes');
    }
    if (data.sublist(12).any((byte) => byte != 0)) {
      throw const FormatException('ioProx reserved bytes must be zero');
    }
    return Pm3IoProxData(
      version: data[0],
      facilityCode: data[1],
      cardNumber: (data[2] << 8) | data[3],
      raw: Uint8List.fromList(data.sublist(4, 12)),
    );
  }
}
