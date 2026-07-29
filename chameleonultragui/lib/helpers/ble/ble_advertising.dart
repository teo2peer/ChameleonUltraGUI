import 'dart:convert';
import 'dart:typed_data';

enum BleAdvertisingProfile { custom, rotating, raw }

enum BleAdvertisingMode { connectable, scannable, nonScannable }

enum BleAdvertisingNameTarget { none, advertisement, scanResponse }

class BleAdStructure {
  final int type;
  final Uint8List value;

  const BleAdStructure(this.type, this.value);
}

List<BleAdStructure> bleValidateAdvertisingData(Uint8List data,
    {bool scanResponse = false}) {
  if (data.length > 31) {
    throw const FormatException(
        'Legacy advertising data must be at most 31 bytes');
  }
  final fields = <BleAdStructure>[];
  var offset = 0;
  var hasName = false;
  while (offset < data.length) {
    final length = data[offset];
    if (length == 0 || offset + length + 1 > data.length) {
      throw const FormatException('Truncated BLE AD structure');
    }
    final type = data[offset + 1];
    if (scanResponse && type == 0x01) {
      throw const FormatException('Flags are not valid in scan-response data');
    }
    if (type == 0x08 || type == 0x09) {
      if (hasName) {
        throw const FormatException('Multiple local-name AD structures');
      }
      hasName = true;
    }
    fields.add(BleAdStructure(
        type, Uint8List.sublistView(data, offset + 2, offset + length + 1)));
    offset += length + 1;
  }
  return fields;
}

Uint8List bleParseAdvertisingHex(String value) {
  final compact = value.replaceAll(RegExp(r'[\s:]'), '');
  if (compact.isEmpty) return Uint8List(0);
  if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) {
    throw const FormatException('Enter complete hexadecimal bytes');
  }
  final output = Uint8List(compact.length ~/ 2);
  for (var index = 0; index < output.length; index++) {
    output[index] =
        int.parse(compact.substring(index * 2, index * 2 + 2), radix: 16);
  }
  return output;
}

String bleFormatAdvertisingHex(Uint8List data) =>
    data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

({Uint8List advertising, Uint8List scanResponse}) bleBuildAdvertisingProfile({
  int flags = 0x06,
  int? serviceUuid,
  int? serviceDataUuid,
  Uint8List? serviceData,
  int? companyId,
  Uint8List? manufacturerData,
}) {
  if (flags < 0 || flags > 0xff) {
    throw const FormatException('Flags must be 0..255');
  }
  final advertising = <int>[2, 0x01, flags];
  final scanResponse = <int>[];
  if (serviceUuid != null) {
    if (serviceUuid < 0 || serviceUuid > 0xffff) {
      throw const FormatException('Service UUID must be 0..65535');
    }
    advertising
        .addAll([3, 0x03, serviceUuid & 0xff, (serviceUuid >> 8) & 0xff]);
  }
  final serviceValue = serviceData ?? Uint8List(0);
  if (serviceDataUuid == null && serviceValue.isNotEmpty) {
    throw const FormatException(
        'Service Data UUID is required with service data');
  }
  if (serviceDataUuid != null) {
    if (serviceDataUuid < 0 || serviceDataUuid > 0xffff) {
      throw const FormatException('Service Data UUID must be 0..65535');
    }
    if (serviceValue.length > 27) {
      throw const FormatException('Service data must be at most 27 bytes');
    }
    final value = <int>[
      serviceDataUuid & 0xff,
      (serviceDataUuid >> 8) & 0xff,
      ...serviceValue,
    ];
    scanResponse.addAll([value.length + 1, 0x16, ...value]);
  }
  final manufacturer = manufacturerData ?? Uint8List(0);
  if (companyId == null && manufacturer.isNotEmpty) {
    throw const FormatException(
        'Company ID is required with manufacturer data');
  }
  if (companyId != null) {
    if (companyId < 0 || companyId > 0xffff) {
      throw const FormatException('Company ID must be 0..65535');
    }
    if (manufacturer.length > 27) {
      throw const FormatException('Manufacturer data must be at most 27 bytes');
    }
    final value = <int>[
      companyId & 0xff,
      (companyId >> 8) & 0xff,
      ...manufacturer,
    ];
    scanResponse.addAll([value.length + 1, 0xff, ...value]);
  }
  final adv = Uint8List.fromList(advertising);
  final scan = Uint8List.fromList(scanResponse);
  bleValidateAdvertisingData(adv);
  bleValidateAdvertisingData(scan, scanResponse: true);
  return (advertising: adv, scanResponse: scan);
}

({Uint8List advertising, Uint8List scanResponse}) bleBuildAppleProximityProfile(
    {int modelCode = 0x0e20}) {
  if (modelCode < 0 || modelCode > 0xffff) {
    throw const FormatException('Model code must be 0..65535');
  }
  final advertising = Uint8List.fromList([
    0x1e,
    0xff,
    0x4c,
    0x00,
    0x07,
    0x19,
    0x07,
    (modelCode >> 8) & 0xff,
    modelCode & 0xff,
    0x75,
    0xaa,
    0x30,
    0x01,
    0x00,
    0x00,
    0x45,
    0x12,
    0x12,
    0x12,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
  bleValidateAdvertisingData(advertising);
  return (advertising: advertising, scanResponse: Uint8List(0));
}

({Uint8List advertising, Uint8List scanResponse}) bleBuildFastPairProfile({
  int modelId = 0x2d7a23,
  int txPower = -20,
}) {
  if (modelId < 0 || modelId > 0xffffff) {
    throw const FormatException('Model ID must be 0..16777215');
  }
  if (txPower < -127 || txPower > 20) {
    throw const FormatException('Tx power must be -127..20 dBm');
  }
  final advertising = Uint8List.fromList([
    0x02,
    0x01,
    0x06,
    0x03,
    0x03,
    0x2c,
    0xfe,
    0x06,
    0x16,
    0x2c,
    0xfe,
    (modelId >> 16) & 0xff,
    (modelId >> 8) & 0xff,
    modelId & 0xff,
    0x02,
    0x0a,
    txPower & 0xff,
  ]);
  bleValidateAdvertisingData(advertising);
  return (advertising: advertising, scanResponse: Uint8List(0));
}

class BleAdvertisingLabConfig {
  final BleAdvertisingProfile profile;
  final BleAdvertisingMode mode;
  final BleAdvertisingNameTarget nameTarget;
  final int intervalMs;
  final int rotationMs;
  final int durationMs;
  final int maxAdvertisingEvents;
  final Uint8List advertisingData;
  final Uint8List scanResponseData;
  final List<String> names;

  const BleAdvertisingLabConfig({
    required this.profile,
    required this.mode,
    required this.advertisingData,
    required this.scanResponseData,
    this.nameTarget = BleAdvertisingNameTarget.none,
    this.names = const [],
    this.intervalMs = 250,
    this.rotationMs = 0,
    this.durationMs = 0,
    this.maxAdvertisingEvents = 0,
  });

  Uint8List toWire() {
    final advFields = bleValidateAdvertisingData(advertisingData);
    final scanFields =
        bleValidateAdvertisingData(scanResponseData, scanResponse: true);
    if (advFields.any((field) => field.type == 0x08 || field.type == 0x09) &&
        scanFields.any((field) => field.type == 0x08 || field.type == 0x09)) {
      throw const FormatException('Local names cannot appear in both packets');
    }
    if (intervalMs < 20 ||
        intervalMs > 10240 ||
        (mode != BleAdvertisingMode.connectable && intervalMs < 100)) {
      throw const FormatException(
          'Interval is outside the selected mode range');
    }
    if (durationMs != 0 &&
        (durationMs < 10 || durationMs > 655350 || durationMs % 10 != 0)) {
      throw const FormatException(
          'Duration must be 0 or a 10 ms multiple up to 655350');
    }
    if (maxAdvertisingEvents < 0 || maxAdvertisingEvents > 255) {
      throw const FormatException('Maximum events must be 0..255');
    }
    if (names.length > 32) {
      throw const FormatException('At most 32 names may be rotated');
    }
    if ((profile == BleAdvertisingProfile.custom && names.length > 1) ||
        (profile == BleAdvertisingProfile.rotating && names.isEmpty) ||
        (profile == BleAdvertisingProfile.raw && names.isNotEmpty)) {
      throw const FormatException('Profile does not match the name list');
    }
    if (names.isEmpty &&
        (nameTarget != BleAdvertisingNameTarget.none || rotationMs != 0)) {
      throw const FormatException('Name options require at least one name');
    }
    if (names.isNotEmpty && nameTarget == BleAdvertisingNameTarget.none) {
      throw const FormatException('Select where names should be advertised');
    }
    if (names.isNotEmpty &&
        [...advFields, ...scanFields]
            .any((field) => field.type == 0x08 || field.type == 0x09)) {
      throw const FormatException(
          'Base data already contains a local-name field');
    }
    if (mode == BleAdvertisingMode.nonScannable &&
        (scanResponseData.isNotEmpty ||
            nameTarget == BleAdvertisingNameTarget.scanResponse)) {
      throw const FormatException(
          'Non-scannable mode cannot use scan-response data');
    }
    final intervalUnits = (intervalMs * 1000 + 624) ~/ 625;
    final effectiveIntervalMs = (intervalUnits * 625 + 999) ~/ 1000;
    if (names.length > 1 &&
        (rotationMs < 100 ||
            rotationMs < effectiveIntervalMs ||
            rotationMs > 65535)) {
      throw const FormatException(
          'Rotation must be at least 100 ms and the advertising interval');
    }
    if (names.length <= 1 && rotationMs != 0) {
      throw const FormatException(
          'Rotation must be zero unless multiple names are supplied');
    }

    final encodedNames = <int>[];
    final targetLength = nameTarget == BleAdvertisingNameTarget.advertisement
        ? advertisingData.length
        : scanResponseData.length;
    for (final name in names) {
      final encoded = utf8.encode(name);
      if (encoded.isEmpty ||
          encoded.length > 26 ||
          encoded.any((byte) => byte < 0x20 || byte == 0x7f)) {
        throw const FormatException(
            'Names must be 1..26 UTF-8 bytes without control characters');
      }
      if (targetLength + encoded.length + 2 > 31) {
        throw const FormatException(
            'A name does not fit in its selected packet');
      }
      encodedNames.addAll([encoded.length, ...encoded]);
    }

    final header = ByteData(14)
      ..setUint8(0, 1)
      ..setUint8(1, profile.index + 1)
      ..setUint8(2, mode.index)
      ..setUint8(3, nameTarget.index)
      ..setUint16(4, intervalUnits, Endian.big)
      ..setUint16(6, rotationMs, Endian.big)
      ..setUint16(8, durationMs ~/ 10, Endian.big)
      ..setUint8(10, maxAdvertisingEvents)
      ..setUint8(11, advertisingData.length)
      ..setUint8(12, scanResponseData.length)
      ..setUint8(13, names.length);
    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...advertisingData,
      ...scanResponseData,
      ...encodedNames,
    ]);
  }

  ({Uint8List advertising, Uint8List scanResponse}) previewPackets() {
    toWire();
    final advertising = <int>[...advertisingData];
    final scanResponse = <int>[...scanResponseData];
    if (names.isNotEmpty) {
      final encoded = utf8.encode(names.first);
      final field = <int>[encoded.length + 1, 0x09, ...encoded];
      if (nameTarget == BleAdvertisingNameTarget.advertisement) {
        advertising.addAll(field);
      } else {
        scanResponse.addAll(field);
      }
    }
    return (
      advertising: Uint8List.fromList(advertising),
      scanResponse: Uint8List.fromList(scanResponse),
    );
  }
}

class BleAdvertisingLabStatus {
  final int state;
  final BleAdvertisingProfile? profile;
  final BleAdvertisingMode mode;
  final int reason;
  final int? activeNameIndex;
  final int nameCount;
  final int advertisingLength;
  final int scanResponseLength;
  final int intervalUnits;
  final int rotationMs;
  final int durationUnits;
  final int maxAdvertisingEvents;
  final int rotationCount;

  const BleAdvertisingLabStatus({
    required this.state,
    required this.profile,
    required this.mode,
    required this.reason,
    required this.activeNameIndex,
    required this.nameCount,
    required this.advertisingLength,
    required this.scanResponseLength,
    required this.intervalUnits,
    required this.rotationMs,
    required this.durationUnits,
    required this.maxAdvertisingEvents,
    required this.rotationCount,
  });

  bool get running => state == 2;
  bool get connected => state == 3;

  factory BleAdvertisingLabStatus.fromWire(Uint8List data) {
    if (data.length != 20 ||
        data[0] != 1 ||
        !const [0, 2, 3, 4].contains(data[1]) ||
        data[2] > 3 ||
        data[3] > 2 ||
        !const [0, 1, 2, 3, 4, 7].contains(data[4]) ||
        data[6] > 32 ||
        data[7] > 31 ||
        data[8] > 31 ||
        (data[6] == 0 && data[5] != 0xff) ||
        (data[6] != 0 && (data[5] == 0xff || data[5] >= data[6]))) {
      throw const FormatException('Malformed BLE advertising-lab status');
    }
    final bytes = ByteData.sublistView(data);
    return BleAdvertisingLabStatus(
      state: data[1],
      profile: data[2] == 0 ? null : BleAdvertisingProfile.values[data[2] - 1],
      mode: BleAdvertisingMode.values[data[3]],
      reason: data[4],
      activeNameIndex: data[5] == 0xff ? null : data[5],
      nameCount: data[6],
      advertisingLength: data[7],
      scanResponseLength: data[8],
      intervalUnits: bytes.getUint16(9, Endian.big),
      rotationMs: bytes.getUint16(11, Endian.big),
      durationUnits: bytes.getUint16(13, Endian.big),
      maxAdvertisingEvents: data[15],
      rotationCount: bytes.getUint32(16, Endian.big),
    );
  }
}
