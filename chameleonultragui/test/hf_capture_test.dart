import 'dart:typed_data';

import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a CRC-validated continuous capture page', () {
    final record = Uint8List.fromList([
      ..._u16(24),
      hfCaptureProtocolVersion,
      1,
      ..._u32(7),
      ..._u64(32768),
      0,
      0,
      ..._u16(32),
      ..._u16(4),
      0x60,
      0x04,
      0x12,
      0x34,
    ]);
    final metadata = _metadata(
      firstSequence: 7,
      nextSequence: 8,
      storedRecords: 1,
      observedRecords: 1,
      usedBytes: record.length,
    );
    final page = _withPageCrc([
      ...metadata,
      ..._u32(7),
      ..._u32(8),
      ..._u16(1),
      ..._u16(record.length),
      ..._u32(0),
      ..._u64(7),
      ...record,
    ]);

    final decoded = HfCapturePage.decode(page);

    expect(decoded.metadata.sessionId, 0x10203040);
    expect(decoded.metadata.mode, HfCaptureMode.emulation);
    expect(decoded.records, hasLength(1));
    expect(decoded.records.single.sequence, 7);
    expect(decoded.records.single.data, [0x60, 0x04, 0x12, 0x34]);
    expect(decoded.records.single.toSniffFrame()!.isReaderToCard, isTrue);
    expect(decoded.pageBytes, page);
  });

  test('rejects corruption before exposing capture records', () {
    final metadata = _metadata(
      firstSequence: 0,
      nextSequence: 0,
      storedRecords: 0,
      observedRecords: 0,
      usedBytes: 0,
    );
    final malformed = Uint8List.fromList([
      ...metadata,
      ..._u32(0),
      ..._u32(0),
      ..._u16(0),
      ..._u16(1),
      ..._u32(0),
      ..._u64(0),
      0xAA,
    ]);

    expect(() => HfCapturePage.decode(malformed), throwsFormatException);
  });

  test('accepts an empty page when a newer frame appears in metadata', () {
    final metadata = _metadata(
      firstSequence: 0,
      nextSequence: 1,
      storedRecords: 1,
      observedRecords: 1,
      usedBytes: 23,
    );
    final page = _withPageCrc([
      ...metadata,
      ..._u32(0),
      ..._u32(0),
      ..._u16(0),
      ..._u16(0),
      ..._u32(0),
      ..._u64(0),
    ]);

    final decoded = HfCapturePage.decode(page);

    expect(decoded.records, isEmpty);
    expect(decoded.metadata.nextSequence, 1);
    expect(decoded.metadata.storedRecords, 1);
  });

  test('accepts sequence gaps explained by dropped records', () {
    final records = Uint8List.fromList([..._record(7), ..._record(9)]);
    final page = _page(
      records: records,
      firstSequence: 7,
      nextSequence: 10,
      recordCount: 2,
      droppedRecords: 1,
    );

    final decoded = HfCapturePage.decode(page);

    expect(decoded.records.map((record) => record.sequence), [7, 9]);
    expect(decoded.metadata.droppedRecords, 1);
  });

  test('rejects sequence gaps without dropped-record evidence', () {
    final records = Uint8List.fromList([..._record(7), ..._record(9)]);
    final page = _page(
      records: records,
      firstSequence: 7,
      nextSequence: 10,
      recordCount: 2,
      droppedRecords: 0,
    );

    expect(() => HfCapturePage.decode(page), throwsFormatException);
  });

  test('accepts a gap larger than half the sequence space', () {
    final records = Uint8List.fromList([..._record(0), ..._record(0x80000001)]);
    final page = _page(
      records: records,
      firstSequence: 0,
      nextSequence: 0x80000002,
      recordCount: 2,
      droppedRecords: 0x80000000,
    );

    expect(
      HfCapturePage.decode(page).records.map((record) => record.sequence),
      [0, 0x80000001],
    );
  });
}

List<int> _record(int sequence) => [
  ..._u16(21),
  hfCaptureProtocolVersion,
  1,
  ..._u32(sequence),
  ..._u64(sequence + 1),
  0,
  0,
  ..._u16(8),
  ..._u16(1),
  0x26,
];

Uint8List _page({
  required Uint8List records,
  required int firstSequence,
  required int nextSequence,
  required int recordCount,
  required int droppedRecords,
}) => _withPageCrc([
  ..._metadata(
    firstSequence: firstSequence,
    nextSequence: nextSequence,
    storedRecords: recordCount,
    observedRecords: nextSequence,
    droppedRecords: droppedRecords,
    usedBytes: records.length,
  ),
  ..._u32(firstSequence),
  ..._u32(nextSequence),
  ..._u16(recordCount),
  ..._u16(records.length),
  ..._u32(0),
  ..._u64(7),
  ...records,
]);

List<int> _metadata({
  required int firstSequence,
  required int nextSequence,
  required int storedRecords,
  required int observedRecords,
  int droppedRecords = 0,
  required int usedBytes,
}) => [
  hfCaptureProtocolVersion,
  1,
  0,
  droppedRecords > 0 ? 1 : 0,
  ..._u32(0x10203040),
  ..._u32(firstSequence),
  ..._u32(nextSequence),
  ..._u32(storedRecords),
  ..._u32(observedRecords),
  ..._u32(droppedRecords),
  ..._u16(usedBytes),
  ..._u16(8192),
  ..._u64(32768),
  ..._u32(0x55667788),
  ..._u32(0x12345678),
];

List<int> _u16(int value) => [value >> 8, value & 0xFF];

List<int> _u32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u64(int value) => [
  for (var shift = 56; shift >= 0; shift -= 8) (value >> shift) & 0xFF,
];

Uint8List _withPageCrc(List<int> values) {
  final page = Uint8List.fromList(values);
  page.setRange(60, 64, _u32(hfCaptureCrc32(page)));
  return page;
}
