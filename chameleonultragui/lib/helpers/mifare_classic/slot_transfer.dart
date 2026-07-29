import 'dart:typed_data';

const int mifareClassicBlockSize = 16;
const int mifareClassicMaxUploadBytes = 128;
const int mifareClassicMaxReadBlocks = 16;

typedef MifareClassicUploadChunk = ({int startBlock, Uint8List data});
typedef MifareClassicRead = ({int startBlock, int blockCount});

List<MifareClassicUploadChunk> planMifareClassicUpload(
    List<Uint8List> blocks, int blockCount) {
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
