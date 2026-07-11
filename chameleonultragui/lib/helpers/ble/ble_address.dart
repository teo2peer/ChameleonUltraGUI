import 'dart:typed_data';

Uint8List bleAddressToLittleEndian(String address,
    {bool requireStaticRandom = false}) {
  final parts = address.trim().replaceAll('-', ':').split(':');
  if (parts.length != 6 ||
      parts.any((part) => !RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(part))) {
    throw const FormatException(
        'BLE address must be 6 two-digit hex octets (AA:BB:CC:DD:EE:FF)');
  }

  final bytes = parts.map((part) => int.parse(part, radix: 16)).toList();
  if (requireStaticRandom && bytes.first & 0xC0 != 0xC0) {
    throw const FormatException(
        'Static-random address must start with a byte in C0..FF');
  }
  return Uint8List.fromList(bytes.reversed.toList());
}

String bleAddressFromLittleEndian(Uint8List address) {
  if (address.length != 6) {
    throw ArgumentError.value(address.length, 'address.length', 'must be 6');
  }
  return address.reversed
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}
