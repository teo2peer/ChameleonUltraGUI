import 'dart:math' as math;
import 'dart:typed_data';

enum Pm3NumberBase {
  decimal(10),
  hexadecimal(16),
  binary(2);

  final int radix;

  const Pm3NumberBase(this.radix);
}

class Pm3NumberConversion {
  final BigInt value;
  final String decimal;
  final String hexadecimal;
  final String binary;
  final String ascii;

  const Pm3NumberConversion({
    required this.value,
    required this.decimal,
    required this.hexadecimal,
    required this.binary,
    required this.ascii,
  });
}

class Pm3ChecksumResult {
  final int byteAdd;
  final int nibbleAdd;
  final int crumbAdd;
  final int byteSubtract;
  final int nibbleSubtract;
  final int byteAddOnesComplement;
  final int nibbleAddOnesComplement;
  final int crumbAddOnesComplement;
  final int byteSubtractOnesComplement;
  final int nibbleSubtractOnesComplement;
  final int byteXor;
  final int nibbleXor;
  final int crumbXor;
  final int bsd8;
  final int bsd4;
  final int xorComplement;

  const Pm3ChecksumResult({
    required this.byteAdd,
    required this.nibbleAdd,
    required this.crumbAdd,
    required this.byteSubtract,
    required this.nibbleSubtract,
    required this.byteAddOnesComplement,
    required this.nibbleAddOnesComplement,
    required this.crumbAddOnesComplement,
    required this.byteSubtractOnesComplement,
    required this.nibbleSubtractOnesComplement,
    required this.byteXor,
    required this.nibbleXor,
    required this.crumbXor,
    required this.bsd8,
    required this.bsd4,
    required this.xorComplement,
  });
}

class Pm3FrequencyBand {
  final String label;
  final double frequencyHz;
  final double wavelengthMeters;
  final double nearFieldRangeMeters;

  const Pm3FrequencyBand({
    required this.label,
    required this.frequencyHz,
    required this.wavelengthMeters,
    required this.nearFieldRangeMeters,
  });

  double get halfWaveMeters => wavelengthMeters / 2;
  double get quarterWaveMeters => wavelengthMeters / 4;
}

class Pm3UnitConversion {
  final double etu;
  final double microseconds;
  final int sspClock;

  const Pm3UnitConversion({
    required this.etu,
    required this.microseconds,
    required this.sspClock,
  });
}

Pm3NumberConversion pm3ConvertNumber(String input, Pm3NumberBase base) {
  final normalized = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) throw const FormatException('Enter a number');
  final pattern = switch (base) {
    Pm3NumberBase.decimal => RegExp(r'^[0-9]+$'),
    Pm3NumberBase.hexadecimal => RegExp(r'^[0-9a-fA-F]+$'),
    Pm3NumberBase.binary => RegExp(r'^[01]+$'),
  };
  if (!pattern.hasMatch(normalized)) {
    throw FormatException('Invalid base-${base.radix} number');
  }
  final value = BigInt.parse(normalized, radix: base.radix);
  var hexadecimal = value.toRadixString(16).toUpperCase();
  if (hexadecimal.length.isOdd) hexadecimal = '0$hexadecimal';
  final bytes = <int>[];
  for (var index = 0; index < hexadecimal.length; index += 2) {
    bytes.add(int.parse(hexadecimal.substring(index, index + 2), radix: 16));
  }
  final ascii = String.fromCharCodes(
    bytes.map((byte) => byte >= 0x20 && byte < 0x7f ? byte : 0x2e),
  );
  final minimumBits = switch (base) {
    Pm3NumberBase.hexadecimal => normalized.length * 4,
    Pm3NumberBase.binary => normalized.length,
    Pm3NumberBase.decimal => value.bitLength,
  };

  return Pm3NumberConversion(
    value: value,
    decimal: value.toRadixString(10),
    hexadecimal: hexadecimal,
    binary: value.toRadixString(2).padLeft(minimumBits, '0'),
    ascii: ascii,
  );
}

List<Pm3FrequencyBand> pm3FrequencyBands() {
  const speedOfLight = 299792458.0;
  const frequencies = <(String, double)>[
    ('125 kHz', 125000),
    ('134 kHz', 134000),
    ('13.56 MHz', 13560000),
  ];
  return [
    for (final (label, frequency) in frequencies)
      Pm3FrequencyBand(
        label: label,
        frequencyHz: frequency,
        wavelengthMeters: speedOfLight / frequency,
        nearFieldRangeMeters: speedOfLight / frequency / (2 * math.pi),
      ),
  ];
}

double pm3ResonantFrequency({
  required double inductanceHenries,
  required double capacitanceFarads,
}) {
  _requirePositive(inductanceHenries, 'inductanceHenries');
  _requirePositive(capacitanceFarads, 'capacitanceFarads');
  return 1 / (2 * math.pi * math.sqrt(inductanceHenries * capacitanceFarads));
}

double pm3ResonantInductance({
  required double frequencyHz,
  required double capacitanceFarads,
}) {
  _requirePositive(frequencyHz, 'frequencyHz');
  _requirePositive(capacitanceFarads, 'capacitanceFarads');
  return 1 /
      (4 * math.pi * math.pi * frequencyHz * frequencyHz * capacitanceFarads);
}

double pm3ResonantCapacitance({
  required double frequencyHz,
  required double inductanceHenries,
}) {
  _requirePositive(frequencyHz, 'frequencyHz');
  _requirePositive(inductanceHenries, 'inductanceHenries');
  return 1 /
      (4 * math.pi * math.pi * frequencyHz * frequencyHz * inductanceHenries);
}

Pm3UnitConversion pm3UnitsFromEtu(int etu) {
  if (etu < 0) throw RangeError.value(etu, 'etu', 'must not be negative');
  return Pm3UnitConversion(
    etu: etu.toDouble(),
    microseconds: etu * 9.4396,
    sspClock: etu << 5,
  );
}

Pm3UnitConversion pm3UnitsFromMicroseconds(int microseconds) {
  if (microseconds < 0) {
    throw RangeError.value(
      microseconds,
      'microseconds',
      'must not be negative',
    );
  }
  return Pm3UnitConversion(
    etu: microseconds / 9.4396,
    microseconds: microseconds.toDouble(),
    sspClock: (microseconds * 3.39).toInt(),
  );
}

int pm3Lrc(Uint8List data) {
  if (data.isEmpty) {
    throw ArgumentError.value(data, 'data', 'must not be empty');
  }
  return data.fold(0, (value, byte) => value ^ byte);
}

Pm3ChecksumResult pm3Checksums(Uint8List data, {int mask = 0xffff}) {
  if (data.isEmpty) {
    throw ArgumentError.value(data, 'data', 'must not be empty');
  }
  if (mask < 0 || mask > 0xffff) {
    throw RangeError.range(mask, 0, 0xffff, 'mask');
  }

  final nibbles = <int>[
    for (final byte in data) byte & 0x0f,
    for (final byte in data) (byte >> 4) & 0x0f,
  ];
  final crumbs = <int>[
    for (final byte in data)
      for (final shift in const [0, 2, 4, 6]) (byte >> shift) & 0x03,
  ];

  int add(Iterable<int> values) =>
      values.fold(0, (sum, value) => sum + value) & mask;
  int subtract(Iterable<int> values) =>
      values.fold(0, (sum, value) => sum - value) & mask;
  int xor(Iterable<int> values) =>
      values.fold(0, (sum, value) => sum ^ value) & mask;

  var bsd8 = 0;
  for (final byte in data) {
    bsd8 = ((bsd8 & 0xff) >> 1) | ((bsd8 & 1) << 7);
    bsd8 = (bsd8 + byte) & 0xff;
  }
  var bsd4 = 0;
  for (final byte in data) {
    for (final nibble in [(byte >> 4) & 0x0f, byte & 0x0f]) {
      bsd4 = ((bsd4 & 0x0f) >> 1) | ((bsd4 & 1) << 3);
      bsd4 = (bsd4 + nibble) & 0x0f;
    }
  }

  final byteAdd = add(data);
  final nibbleAdd = add(nibbles);
  final crumbAdd = add(crumbs);
  final byteSubtract = subtract(data);
  final nibbleSubtract = subtract(nibbles);
  final byteXor = xor(data);

  return Pm3ChecksumResult(
    byteAdd: byteAdd,
    nibbleAdd: nibbleAdd,
    crumbAdd: crumbAdd,
    byteSubtract: byteSubtract,
    nibbleSubtract: nibbleSubtract,
    byteAddOnesComplement: (~byteAdd) & mask,
    nibbleAddOnesComplement: (~nibbleAdd) & mask,
    crumbAddOnesComplement: (~crumbAdd) & mask,
    byteSubtractOnesComplement: (~byteSubtract) & mask,
    nibbleSubtractOnesComplement: (~nibbleSubtract) & mask,
    byteXor: byteXor,
    nibbleXor: xor(nibbles),
    crumbXor: xor(crumbs),
    bsd8: bsd8 & mask,
    bsd4: bsd4 & mask,
    xorComplement: 0xff - byteXor,
  );
}

Uint8List pm3Xor(Uint8List data, [Uint8List? mask]) {
  if (data.isEmpty) {
    throw ArgumentError.value(data, 'data', 'must not be empty');
  }
  var effectiveMask = mask;
  if (effectiveMask == null || effectiveMask.isEmpty) {
    final frequency = List<int>.filled(256, 0);
    var highest = 0;
    var mostFrequent = 0;
    for (final byte in data) {
      final count = ++frequency[byte];
      if (count > highest) {
        highest = count;
        mostFrequent = byte;
      }
    }
    effectiveMask = Uint8List.fromList(List.filled(data.length, mostFrequent));
  }
  if (effectiveMask.length != data.length) {
    throw ArgumentError('XOR data and mask must have identical lengths');
  }
  return Uint8List.fromList([
    for (var index = 0; index < data.length; index++)
      data[index] ^ effectiveMask[index],
  ]);
}

Uint8List pm3GenerateNuid(Uint8List uid) {
  if (uid.length != 7) {
    throw ArgumentError.value(uid.length, 'uid.length', 'must be 7');
  }
  final firstCrc = _crc16a(Uint8List.sublistView(uid, 0, 3));
  final finalCrc = _crc16a(Uint8List.sublistView(uid, 3), initial: firstCrc);
  return Uint8List.fromList([
    ((firstCrc >> 8) & 0xe0) | 0x0f,
    firstCrc & 0xff,
    (finalCrc >> 8) & 0xff,
    finalCrc & 0xff,
  ]);
}

int _crc16a(Uint8List data, {int initial = 0x6363}) {
  var crc = initial;
  for (final byte in data) {
    var value = (byte ^ crc) & 0xff;
    value ^= (value << 4) & 0xff;
    crc = ((crc >> 8) ^ (value << 8) ^ (value << 3) ^ (value >> 4)) & 0xffff;
  }
  return crc;
}

void _requirePositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw RangeError.value(value, name, 'must be finite and greater than zero');
  }
}
