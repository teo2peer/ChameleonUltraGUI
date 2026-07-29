import 'dart:typed_data';

import 'package:chameleonultragui/helpers/mifare_classic/slot_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List block(int value) =>
    Uint8List.fromList(List.filled(mifareClassicBlockSize, value));

void main() {
  group('planMifareClassicUpload', () {
    test('preserves indices across leading, middle, and trailing gaps', () {
      final blocks = <Uint8List>[
        Uint8List(0),
        Uint8List(0),
        block(2),
        block(3),
        Uint8List(0),
        block(5),
        Uint8List(0),
        Uint8List(0),
      ];

      final chunks = planMifareClassicUpload(blocks, blocks.length);

      expect(chunks.map((chunk) => chunk.startBlock), [2, 5]);
      expect(chunks.map((chunk) => chunk.data.length), [32, 16]);
      expect(chunks[0].data, [...block(2), ...block(3)]);
      expect(chunks[1].data, block(5));
    });

    test('splits contiguous blocks at the protocol chunk maximum', () {
      final blocks = List.generate(10, block);

      final chunks = planMifareClassicUpload(blocks, blocks.length);

      expect(chunks.map((chunk) => chunk.startBlock), [0, 8]);
      expect(chunks.map((chunk) => chunk.data.length), [128, 32]);
      expect(
          chunks.every(
              (chunk) => chunk.data.length <= mifareClassicMaxUploadBytes),
          isTrue);
    });

    test('treats malformed and missing entries as gaps', () {
      final chunks =
          planMifareClassicUpload([block(0), Uint8List(15), block(2)], 5);

      expect(chunks.map((chunk) => chunk.startBlock), [0, 2]);
      expect(chunks.map((chunk) => chunk.data.length), [16, 16]);
    });
  });

  group('planMifareClassicReads', () {
    test('covers Mini, 1K, 1K EV1, 2K, and 4K exactly once', () {
      for (final blockCount in [20, 64, 72, 128, 256]) {
        final reads = planMifareClassicReads(blockCount);
        final visited = <int>[];
        for (final read in reads) {
          expect(read.blockCount, inInclusiveRange(1, 16));
          expect(
              read.startBlock + read.blockCount, lessThanOrEqualTo(blockCount));
          visited.addAll(List.generate(
              read.blockCount, (offset) => read.startBlock + offset));
        }

        expect(visited, List.generate(blockCount, (block) => block));
      }
    });

    test('uses one bounded remainder read', () {
      expect(planMifareClassicReads(20), [
        (startBlock: 0, blockCount: 16),
        (startBlock: 16, blockCount: 4),
      ]);
      expect(planMifareClassicReads(72).last, (startBlock: 64, blockCount: 8));
    });
  });
}
