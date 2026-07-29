import 'dart:convert';
import 'dart:typed_data';

const Map<int, String> bleCompanyIds = {
  0x0006: 'Microsoft',
  0x0059: 'Nordic',
  0x004C: 'Apple',
  0x0075: 'Samsung',
  0x0087: 'Garmin',
  0x00E0: 'Google',
  0x0157: 'Huawei',
  0x0171: 'Amazon',
  0x02E5: 'Espressif',
  0x038F: 'Xiaomi',
  0x0499: 'Ruuvi',
  0x0A12: 'Sony',
};

// Common Bluetooth SIG 16-bit UUIDs (services 0x18xx, characteristics 0x2Axx).
const Map<int, String> bleUuidNames = {
  0x1800: 'Generic Access',
  0x1801: 'Generic Attribute',
  0x1802: 'Immediate Alert',
  0x1803: 'Link Loss',
  0x1804: 'Tx Power',
  0x1805: 'Current Time',
  0x1808: 'Glucose',
  0x1809: 'Health Thermometer',
  0x180A: 'Device Information',
  0x180D: 'Heart Rate',
  0x180F: 'Battery',
  0x1810: 'Blood Pressure',
  0x1812: 'HID',
  0x1816: 'Cycling Speed',
  0x1818: 'Cycling Power',
  0x1819: 'Location and Navigation',
  0x181A: 'Environmental Sensing',
  0x181C: 'User Data',
  0x1826: 'Fitness Machine',
  0xFE59: 'Nordic DFU',
  0xFD6F: 'Exposure Notification',
  0x2A00: 'Device Name',
  0x2A01: 'Appearance',
  0x2A04: 'Preferred Conn Params',
  0x2A05: 'Service Changed',
  0x2A06: 'Alert Level',
  0x2A19: 'Battery Level',
  0x2A23: 'System ID',
  0x2A24: 'Model Number',
  0x2A25: 'Serial Number',
  0x2A26: 'Firmware Rev',
  0x2A27: 'Hardware Rev',
  0x2A28: 'Software Rev',
  0x2A29: 'Manufacturer',
  0x2A2B: 'Current Time',
  0x2A37: 'Heart Rate Meas',
  0x2A38: 'Body Sensor Loc',
  0x2A50: 'PnP ID',
  0x2A6E: 'Temperature',
  0x2A6F: 'Humidity',
  0x2900: 'Char Ext Props',
  0x2901: 'Char User Desc',
  0x2902: 'CCCD',
  0x2903: 'Server Char Config',
  0x2904: 'Char Presentation Fmt',
  0x2905: 'Char Aggregate Fmt',
  0x2908: 'Report Reference',
};

// BLE appearance categories (top 10 bits) and common specific subtypes.
const Map<int, String> bleAppearanceCategoryNames = {
  0x0040: 'Phone',
  0x0080: 'Computer',
  0x00C0: 'Watch',
  0x0100: 'Clock',
  0x0140: 'Display',
  0x0180: 'Remote Control',
  0x01C0: 'Eye-glasses',
  0x0200: 'Tag',
  0x0240: 'Keyring',
  0x0280: 'Media Player',
  0x02C0: 'Barcode Scanner',
  0x0300: 'Thermometer',
  0x0340: 'Heart Rate Sensor',
  0x0380: 'Blood Pressure',
  0x03C0: 'HID',
  0x0400: 'Glucose Meter',
  0x0440: 'Running/Walking Sensor',
  0x0480: 'Cycling',
};

const Map<int, String> bleAppearanceSpecificNames = {
  0x03C1: 'Keyboard',
  0x03C2: 'Mouse',
  0x03C3: 'Joystick',
  0x03C4: 'Gamepad',
  0x0341: 'Heart Rate Belt',
};

String? bleAdvertisingName(Uint8List advertisingData) {
  int offset = 0;
  String? name;
  while (offset < advertisingData.length) {
    final length = advertisingData[offset];
    if (length == 0) break;
    final type =
        offset + 1 < advertisingData.length ? advertisingData[offset + 1] : 0;
    final end = offset + 1 + length <= advertisingData.length
        ? offset + 1 + length
        : advertisingData.length;
    final value =
        advertisingData.sublist(offset + 2 <= end ? offset + 2 : end, end);
    if (type == 0x08 || type == 0x09) {
      name = utf8.decode(value, allowMalformed: true);
    }
    offset += length + 1;
  }
  return name;
}

String bleAdvertisingSummary(Uint8List advertisingData,
    {String serviceAbbreviation = 'svc'}) {
  final parts = <String>[];
  int offset = 0;
  while (offset + 1 < advertisingData.length) {
    final length = advertisingData[offset];
    if (length == 0) break;
    final type = advertisingData[offset + 1];
    final end = offset + 1 + length <= advertisingData.length
        ? offset + 1 + length
        : advertisingData.length;
    final value =
        advertisingData.sublist(offset + 2 <= end ? offset + 2 : end, end);
    if (type == 0x01 && value.isNotEmpty) {
      final flags = <String>[];
      if (value[0] & 0x02 != 0) flags.add('LE-gen');
      if (value[0] & 0x04 != 0) flags.add('no-BR/EDR');
      if (flags.isNotEmpty) parts.add(flags.join('|'));
    } else if ((type == 0x02 || type == 0x03) && value.length >= 2) {
      parts.add('${value.length ~/ 2} $serviceAbbreviation');
    } else if (type == 0x0A && value.isNotEmpty) {
      parts.add('${value[0] > 127 ? value[0] - 256 : value[0]}dBm');
    } else if (type == 0xFF && value.length >= 2) {
      final company = value[0] | (value[1] << 8);
      parts.add(bleCompanyIds[company] ??
          '0x${company.toRadixString(16).padLeft(4, '0')}');
    }
    offset += length + 1;
  }
  return parts.join(' \u00B7 ');
}

List<String> bleAdvertisingDetails(Uint8List advertisingData) {
  final fields = <String>[];
  int offset = 0;
  while (offset + 1 < advertisingData.length) {
    final length = advertisingData[offset];
    if (length == 0) break;
    final type = advertisingData[offset + 1];
    final end = offset + 1 + length <= advertisingData.length
        ? offset + 1 + length
        : advertisingData.length;
    final value =
        advertisingData.sublist(offset + 2 <= end ? offset + 2 : end, end);
    if (type == 0x01 && value.isNotEmpty) {
      final flags = <String>[];
      if (value[0] & 0x01 != 0) flags.add('LE-limited');
      if (value[0] & 0x02 != 0) flags.add('LE-general');
      if (value[0] & 0x04 != 0) flags.add('no-BR/EDR');
      fields.add(
          'flags: ${flags.isEmpty ? '0x${value[0].toRadixString(16)}' : flags.join('|')}');
    } else if (type == 0x02 || type == 0x03) {
      final uuids = <String>[];
      for (int i = 0; i + 1 < value.length; i += 2) {
        final uuid = value[i] | (value[i + 1] << 8);
        final name = bleUuidName(uuid);
        uuids.add(
            '0x${uuid.toRadixString(16).padLeft(4, '0')}${name.isNotEmpty ? '($name)' : ''}');
      }
      if (uuids.isNotEmpty) fields.add('services16: ${uuids.join(', ')}');
    } else if (type == 0x06 || type == 0x07) {
      fields.add('services128: ${value.length ~/ 16}');
    } else if (type == 0x08 || type == 0x09) {
      fields.add('name: ${String.fromCharCodes(value)}');
    } else if (type == 0x0A && value.isNotEmpty) {
      fields.add('tx_power: ${value[0] > 127 ? value[0] - 256 : value[0]} dBm');
    } else if (type == 0x19 && value.length >= 2) {
      final appearance = value[0] | (value[1] << 8);
      final name = bleAppearanceName(appearance);
      fields.add(
          'appearance: 0x${appearance.toRadixString(16).padLeft(4, '0')}${name.isNotEmpty ? ' ($name)' : ''}');
    } else if (type == 0xFF && value.length >= 2) {
      final company = value[0] | (value[1] << 8);
      final name = bleCompanyIds[company] ??
          '0x${company.toRadixString(16).padLeft(4, '0')}';
      fields.add('mfr: $name [${bleFormatHexBytes(value.sublist(2))}]');
    } else if (type == 0x16 && value.length >= 2) {
      final service = value[0] | (value[1] << 8);
      fields.add(
          'svc_data 0x${service.toRadixString(16).padLeft(4, '0')}: ${bleFormatHexBytes(value.sublist(2))}');
    }
    offset += length + 1;
  }
  return fields;
}

String bleUuidName(int uuid) => bleUuidNames[uuid] ?? '';

String bleAppearanceName(int appearance) =>
    bleAppearanceSpecificNames[appearance] ??
    bleAppearanceCategoryNames[appearance & 0xFFC0] ??
    '';

String bleCharacteristicPropertiesString(int properties) {
  final names = <String>[];
  if (properties & 0x02 != 0) names.add('read');
  if (properties & 0x04 != 0) names.add('write-nr');
  if (properties & 0x08 != 0) names.add('write');
  if (properties & 0x10 != 0) names.add('notify');
  if (properties & 0x20 != 0) names.add('indicate');
  return names.isEmpty ? '-' : names.join(',');
}

bool bleCanWriteWithResponse(int properties) => properties & 0x08 != 0;

bool bleCanFuzzWithoutResponse(int properties) => properties & 0x04 != 0;

String bleAttStatusDescription(int status) {
  final name = switch (status) {
    0x05 => 'insufficient authentication',
    0x08 => 'insufficient authorization',
    0x0C => 'insufficient encryption key size',
    0x0F => 'insufficient encryption',
    _ => 'ATT error',
  };
  return '$name (0x${status.toRadixString(16).padLeft(2, '0').toUpperCase()})';
}

Uint8List bleParseHexBytes(String value) {
  if (value.isEmpty || value.length.isOdd) {
    throw const FormatException('need an even number of hex digits');
  }
  return Uint8List.fromList([
    for (int i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

String bleFormatHexBytes(Uint8List bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

String bleDeviceInfoLabel(int uuid) {
  final name = bleUuidName(uuid);
  return name.isNotEmpty ? name : '0x${uuid.toRadixString(16).padLeft(4, '0')}';
}

String bleDeviceInfoValue(int uuid, int status, Uint8List data) {
  if (status != 0) {
    return '(read failed, ATT 0x${status.toRadixString(16)})';
  }
  if (uuid == 0x2A19 && data.isNotEmpty) {
    return '${data[0]}%';
  }
  if (uuid == 0x2A01 && data.length >= 2) {
    return '0x${((data[1] << 8) | data[0]).toRadixString(16).padLeft(4, '0')}';
  }
  var value = data;
  while (value.isNotEmpty && value.last == 0) {
    value = value.sublist(0, value.length - 1);
  }
  if (value.isNotEmpty && value.every((byte) => byte >= 0x20 && byte < 0x7F)) {
    return '"${String.fromCharCodes(value)}"';
  }
  return value.isEmpty ? '(empty)' : bleFormatHexBytes(value);
}

int bleParseHexOrDecimal(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    throw const FormatException('empty value');
  }
  if (text.startsWith('0x') || text.startsWith('0X')) {
    if (text.length == 2) throw const FormatException('missing hex digits');
    return int.parse(text.substring(2), radix: 16);
  }
  return int.parse(text, radix: 10);
}
