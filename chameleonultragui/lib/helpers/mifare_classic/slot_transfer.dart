import 'dart:typed_data';

const int mifareClassicBlockSize = 16;
const int mifareClassicMaxUploadBytes = 128;
const int mifareClassicMaxReadBlocks = 16;

typedef MifareClassicUploadChunk = ({int startBlock, Uint8List data});
typedef MifareClassicRead = ({int startBlock, int blockCount});
typedef FixedSizeUploadChunk = ({int startRecord, Uint8List data});

void validateSlotDump(
  List<Uint8List> records, {
  required int expectedCount,
  required int recordSize,
  int? maxStoredCount,
}) {
  if (expectedCount <= 0 || recordSize <= 0) {
    throw ArgumentError('Expected count and record size must be positive');
  }
  if (records.length > (maxStoredCount ?? expectedCount)) {
    throw FormatException(
      'Invalid dump: too many stored records (${records.length})',
    );
  }
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    if (record.isEmpty) continue;
    if (index >= expectedCount || record.length != recordSize) {
      throw FormatException(
        'Invalid dump record $index: expected $recordSize bytes inside the card geometry',
      );
    }
  }
}

List<FixedSizeUploadChunk> planFixedSizeSlotUpload(
  List<Uint8List> records, {
  required int recordCount,
  required int recordSize,
  required int maxChunkBytes,
}) {
  final chunks = <FixedSizeUploadChunk>[];
  final data = <int>[];
  int? startRecord;

  void flush() {
    if (startRecord == null) return;
    chunks.add((startRecord: startRecord!, data: Uint8List.fromList(data)));
    startRecord = null;
    data.clear();
  }

  for (var index = 0; index < recordCount && index < records.length; index++) {
    final record = records[index];
    if (record.length != recordSize) {
      flush();
      continue;
    }
    if (data.length + recordSize > maxChunkBytes) flush();
    startRecord ??= index;
    data.addAll(record);
  }
  flush();
  return chunks;
}

List<MifareClassicUploadChunk> planMifareClassicUpload(
  List<Uint8List> blocks,
  int blockCount,
) {
  if (blockCount < 0) {
    throw ArgumentError.value(blockCount, 'blockCount');
  }

  final chunks = <MifareClassicUploadChunk>[];
  final data = <int>[];
  int? startBlock;

  void flush() {
    if (startBlock == null) return;
    chunks.add((startBlock: startBlock!, data: Uint8List.fromList(data)));
    startBlock = null;
    data.clear();
  }

  for (var block = 0; block < blockCount; block++) {
    final valid =
        block < blocks.length && blocks[block].length == mifareClassicBlockSize;
    if (!valid) {
      flush();
      continue;
    }

    if (data.length + mifareClassicBlockSize > mifareClassicMaxUploadBytes) {
      flush();
    }
    startBlock ??= block;
    data.addAll(blocks[block]);
  }

  flush();
  return chunks;
}

List<MifareClassicRead> planMifareClassicReads(int blockCount) {
  if (blockCount < 0) {
    throw ArgumentError.value(blockCount, 'blockCount');
  }

  final reads = <MifareClassicRead>[];
  for (var startBlock = 0; startBlock < blockCount;) {
    final remaining = blockCount - startBlock;
    final readCount = remaining < mifareClassicMaxReadBlocks
        ? remaining
        : mifareClassicMaxReadBlocks;
    reads.add((startBlock: startBlock, blockCount: readCount));
    startBlock += readCount;
  }
  return reads;
}
