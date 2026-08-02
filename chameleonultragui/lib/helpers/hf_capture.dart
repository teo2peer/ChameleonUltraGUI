import 'dart:typed_data';

import 'package:chameleonultragui/helpers/hf_sniff.dart';

const int hfCaptureProtocolVersion = 2;
const int hfCaptureMetadataSize = 48;
const int hfCapturePageHeaderSize = 72;
const int hfCaptureRecordHeaderSize = 22;
const int hfCaptureMinimumPageSize = 605;

enum HfCaptureMode {
  emulation(0),
  passive(1),
  reader(2);

  const HfCaptureMode(this.value);
  final int value;
}

enum HfCaptureState {
  running(1),
  stopped(2);

  const HfCaptureState(this.value);
  final int value;

  static HfCaptureState fromValue(int value) => values.firstWhere(
    (state) => state.value == value,
    orElse: () => throw FormatException('Invalid HF capture state: $value'),
  );
}

enum HfCaptureRecordType {
  frame(1),
  field(2);

  const HfCaptureRecordType(this.value);
  final int value;

  static HfCaptureRecordType fromValue(int value) => values.firstWhere(
    (type) => type.value == value,
    orElse: () =>
        throw FormatException('Invalid HF capture record type: $value'),
  );
}

enum HfCaptureDirection {
  readerToCard(0),
  cardToReader(1),
  event(2);

  const HfCaptureDirection(this.value);
  final int value;

  static HfCaptureDirection fromValue(int value) => values.firstWhere(
    (direction) => direction.value == value,
    orElse: () => throw FormatException('Invalid HF capture direction: $value'),
  );
}

class HfCaptureMetadata {
  const HfCaptureMetadata({
    required this.state,
    required this.mode,
    required this.sessionId,
    required this.firstSequence,
    required this.nextSequence,
    required this.storedRecords,
    required this.observedRecords,
    required this.droppedRecords,
    required this.usedBytes,
    required this.capacityBytes,
    required this.elapsedTicks,
    required this.bootId,
    required this.startToken,
    required this.overflowed,
  });

  final HfCaptureState state;
  final HfCaptureMode mode;
  final int sessionId;
  final int firstSequence;
  final int nextSequence;
  final int storedRecords;
  final int observedRecords;
  final int droppedRecords;
  final int usedBytes;
  final int capacityBytes;
  final int elapsedTicks;
  final int bootId;
  final int startToken;
  final bool overflowed;

  bool get isRunning => state == HfCaptureState.running;

  factory HfCaptureMetadata.decode(Uint8List data, {int offset = 0}) {
    if (offset < 0 || data.length - offset < hfCaptureMetadataSize) {
      throw const FormatException('Truncated HF capture metadata');
    }
    if (data[offset] != hfCaptureProtocolVersion) {
      throw FormatException(
        'Unsupported HF capture protocol version: ${data[offset]}',
      );
    }
    final modeValue = data[offset + 2];
    if (modeValue >= HfCaptureMode.values.length) {
      throw FormatException('Invalid HF capture mode: $modeValue');
    }
    final flags = data[offset + 3];
    if ((flags & ~0x01) != 0) {
      throw FormatException('Unknown HF capture metadata flags: $flags');
    }
    final sessionId = _u32(data, offset + 4);
    final usedBytes = _u16(data, offset + 28);
    final capacityBytes = _u16(data, offset + 30);
    final storedRecords = _u32(data, offset + 16);
    final observedRecords = _u32(data, offset + 20);
    final droppedRecords = _u32(data, offset + 24);
    final bootId = _u32(data, offset + 40);
    final startToken = _u32(data, offset + 44);
    final firstSequence = _u32(data, offset + 8);
    final nextSequence = _u32(data, offset + 12);
    if (sessionId == 0 ||
        bootId == 0 ||
        startToken == 0 ||
        capacityBytes == 0 ||
        usedBytes > capacityBytes ||
        storedRecords > observedRecords ||
        droppedRecords > observedRecords ||
        (storedRecords == 0 &&
            (usedBytes != 0 || firstSequence != nextSequence)) ||
        (storedRecords > 0 && usedBytes == 0) ||
        (droppedRecords > 0 && (flags & 0x01) == 0)) {
      throw const FormatException('Invalid HF capture metadata values');
    }
    return HfCaptureMetadata(
      state: HfCaptureState.fromValue(data[offset + 1]),
      mode: HfCaptureMode.values[modeValue],
      sessionId: sessionId,
      firstSequence: firstSequence,
      nextSequence: nextSequence,
      storedRecords: storedRecords,
      observedRecords: observedRecords,
      droppedRecords: droppedRecords,
      usedBytes: usedBytes,
      capacityBytes: capacityBytes,
      elapsedTicks: _u64(data, offset + 32),
      bootId: bootId,
      startToken: startToken,
      overflowed: (flags & 0x01) != 0,
    );
  }
}

class HfCaptureRecord {
  const HfCaptureRecord({
    required this.type,
    required this.sequence,
    required this.timestampTicks,
    required this.direction,
    required this.flags,
    required this.bitLength,
    required this.data,
    required this.encoded,
  });

  final HfCaptureRecordType type;
  final int sequence;
  final int timestampTicks;
  final HfCaptureDirection direction;
  final int flags;
  final int bitLength;
  final Uint8List data;
  final Uint8List encoded;

  bool get parityPacked => (flags & 0x01) != 0;
  bool get crcAutomatic => (flags & 0x02) != 0;
  bool get hasRfError => (flags & 0x04) != 0;
  bool get isFrame => type == HfCaptureRecordType.frame;

  HfSniffFrame? toSniffFrame() {
    if (!isFrame || direction == HfCaptureDirection.event) return null;
    if (parityPacked) {
      final header =
          bitLength |
          (direction == HfCaptureDirection.cardToReader ? 0x8000 : 0);
      final parsed = parseHf14aSniffFrames(
        Uint8List.fromList([header >> 8, header & 0xFF, ...data]),
      );
      if (parsed.length != 1) {
        throw const FormatException('Invalid parity-packed HF capture frame');
      }
      return parsed.single;
    }
    return HfSniffFrame(
      rawBitLength: bitLength,
      bitLength: bitLength,
      data: Uint8List.fromList(data),
      direction: direction == HfCaptureDirection.readerToCard
          ? HfSniffDirection.readerToCard
          : HfSniffDirection.cardToReader,
    );
  }
}

class HfCapturePage {
  const HfCapturePage({
    required this.metadata,
    required this.firstSequence,
    required this.nextSequence,
    required this.deliveryToken,
    required this.records,
    required this.recordBytes,
    required this.pageBytes,
  });

  final HfCaptureMetadata metadata;
  final int firstSequence;
  final int nextSequence;
  final int deliveryToken;
  final List<HfCaptureRecord> records;
  final Uint8List recordBytes;
  final Uint8List pageBytes;

  int? get lastSequence => records.isEmpty ? null : records.last.sequence;

  factory HfCapturePage.decode(Uint8List data) {
    if (data.length < hfCapturePageHeaderSize) {
      throw const FormatException('Truncated HF capture page');
    }
    final metadata = HfCaptureMetadata.decode(data);
    final firstSequence = _u32(data, 48);
    final nextSequence = _u32(data, 52);
    final recordCount = _u16(data, 56);
    final dataLength = _u16(data, 58);
    final deliveryToken = _u64(data, 64);
    if (data.length != hfCapturePageHeaderSize + dataLength) {
      throw const FormatException('Invalid HF capture page length');
    }
    final expectedCrc = _u32(data, 60);
    final protectedBytes = Uint8List.fromList(data)..fillRange(60, 64, 0);
    final recordBytes = Uint8List.fromList(
      data.sublist(hfCapturePageHeaderSize),
    );
    if (hfCaptureCrc32(protectedBytes) != expectedCrc) {
      throw const FormatException('HF capture page CRC32 mismatch');
    }
    final records = decodeHfCaptureRecords(recordBytes);
    if (records.length != recordCount) {
      throw const FormatException('HF capture page record count mismatch');
    }
    if (records.isEmpty) {
      if (firstSequence != nextSequence || deliveryToken != 0) {
        throw const FormatException('Invalid empty HF capture page sequence');
      }
    } else {
      if (deliveryToken <= 0 ||
          records.first.sequence != firstSequence ||
          ((records.last.sequence + 1) & 0xFFFFFFFF) != nextSequence ||
          metadata.firstSequence != firstSequence ||
          metadata.storedRecords < records.length) {
        throw const FormatException('Invalid HF capture page sequence range');
      }
      var missingRecords = 0;
      for (var index = 1; index < records.length; index++) {
        final distance = hfCaptureSequenceDistance(
          records[index - 1].sequence,
          records[index].sequence,
        );
        if (distance == 0) {
          throw const FormatException('Invalid HF capture record order');
        }
        missingRecords += distance - 1;
      }
      if (missingRecords > metadata.droppedRecords) {
        throw const FormatException('Unexplained HF capture sequence gap');
      }
    }
    return HfCapturePage(
      metadata: metadata,
      firstSequence: firstSequence,
      nextSequence: nextSequence,
      deliveryToken: deliveryToken,
      records: List.unmodifiable(records),
      recordBytes: recordBytes,
      pageBytes: Uint8List.fromList(data),
    );
  }
}

List<HfCaptureRecord> decodeHfCaptureRecords(Uint8List data) {
  final records = <HfCaptureRecord>[];
  var offset = 0;
  while (offset < data.length) {
    if (data.length - offset < hfCaptureRecordHeaderSize) {
      throw const FormatException('Truncated HF capture record');
    }
    final bodyLength = _u16(data, offset);
    final totalLength = bodyLength + 2;
    if (bodyLength < hfCaptureRecordHeaderSize - 2 ||
        offset + totalLength > data.length) {
      throw const FormatException('Invalid HF capture record length');
    }
    if (data[offset + 2] != hfCaptureProtocolVersion) {
      throw const FormatException('Unsupported HF capture record version');
    }
    final type = HfCaptureRecordType.fromValue(data[offset + 3]);
    final direction = HfCaptureDirection.fromValue(data[offset + 16]);
    final flags = data[offset + 17];
    if ((flags & ~0x07) != 0) {
      throw FormatException('Unknown HF capture record flags: $flags');
    }
    final bitLength = _u16(data, offset + 18);
    final payloadLength = _u16(data, offset + 20);
    if (bodyLength != 20 + payloadLength ||
        (payloadLength == 0 ? bitLength != 0 : bitLength > payloadLength * 8)) {
      throw const FormatException('Invalid HF capture record payload');
    }
    final payload = data.sublist(
      offset + hfCaptureRecordHeaderSize,
      offset + totalLength,
    );
    if (type == HfCaptureRecordType.field) {
      if (direction != HfCaptureDirection.event ||
          flags != 0 ||
          bitLength != 0 ||
          payloadLength != 1 ||
          payload.single > 1) {
        throw const FormatException('Invalid HF capture field record');
      }
    } else if (direction == HfCaptureDirection.event ||
        payloadLength != (bitLength + 7) ~/ 8) {
      throw const FormatException('Invalid HF capture frame record');
    }
    final encoded = Uint8List.fromList(
      data.sublist(offset, offset + totalLength),
    );
    records.add(
      HfCaptureRecord(
        type: type,
        sequence: _u32(data, offset + 4),
        timestampTicks: _u64(data, offset + 8),
        direction: direction,
        flags: flags,
        bitLength: bitLength,
        data: Uint8List.fromList(payload),
        encoded: encoded,
      ),
    );
    offset += totalLength;
  }
  return records;
}

int _u16(Uint8List data, int offset) => (data[offset] << 8) | data[offset + 1];

int _u32(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

int _u64(Uint8List data, int offset) {
  var value = 0;
  for (var index = 0; index < 8; index++) {
    value = (value << 8) | data[offset + index];
  }
  return value;
}

int hfCaptureSequenceDistance(int from, int to) => (to - from) & 0xFFFFFFFF;

String hfCaptureRawHex(HfCaptureRecord record) => record.data
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

int hfCaptureCrc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320);
    }
  }
  return (~crc) & 0xFFFFFFFF;
}
