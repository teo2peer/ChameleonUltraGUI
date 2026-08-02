import 'dart:typed_data';

import 'package:chameleonultragui/helpers/mifare_classic/slot_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List block(int value) =>
    Uint8List.fromList(List.filled(mifareClassicBlockSize, value));

void main() {
  group('validateSlotDump', () {
    test('accepts a complete fixed-size dump', () {
      expect(
        () => validateSlotDump(
          List.generate(72, block),
          expectedCount: 72,
          recordSize: mifareClassicBlockSize,
        ),
        returnsNormally,
      );
    });

    test('accepts sparse and canonical padded dumps', () {
      final padded = List.generate(256, (_) => Uint8List(0));
      for (var index = 0; index < 64; index++) {
        padded[index] = block(index);
      }
      expect(
        () => validateSlotDump(
          padded,
          expectedCount: 64,
          recordSize: mifareClassicBlockSize,
          maxStoredCount: 256,
        ),
        returnsNormally,
      );
      expect(
        () => validateSlotDump(
          List.generate(68, block),
          expectedCount: 72,
          recordSize: mifareClassicBlockSize,
        ),
        returnsNormally,
      );
      expect(
        () => validateSlotDump(
          List.generate(16, (index) => Uint8List(4)),
          expectedCount: 48,
          recordSize: 4,
        ),
        returnsNormally,
      );
    });

    test('rejects data outside the declared card geometry', () {
      final records = List.generate(256, (_) => Uint8List(0));
      records[64] = block(64);
      expect(
        () => validateSlotDump(
          records,
          expectedCount: 64,
          recordSize: mifareClassicBlockSize,
          maxStoredCount: 256,
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed records before upload', () {
      final records = List.generate(64, block)..[17] = Uint8List(15);
      expect(
        () => validateSlotDump(
          records,
          expectedCount: 64,
          recordSize: mifareClassicBlockSize,
        ),
        throwsFormatException,
      );
    });
  });

  group('planFixedSizeSlotUpload', () {
    test('preserves sparse page indices and chunk limits', () {
      final pages = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList([1, 1, 1, 1]),
        Uint8List.fromList([2, 2, 2, 2]),
        Uint8List(0),
        Uint8List.fromList([4, 4, 4, 4]),
      ];
      final chunks = planFixedSizeSlotUpload(
        pages,
        recordCount: 8,
        recordSize: 4,
        maxChunkBytes: 8,
      );

      expect(chunks.map((chunk) => chunk.startRecord), [1, 4]);
      expect(chunks.map((chunk) => chunk.data.length), [8, 4]);
    });
  });

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
          (chunk) => chunk.data.length <= mifareClassicMaxUploadBytes,
        ),
        isTrue,
      );
    });

    test('treats malformed and missing entries as gaps', () {
      final chunks = planMifareClassicUpload([
        block(0),
        Uint8List(15),
        block(2),
      ], 5);

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
            read.startBlock + read.blockCount,
            lessThanOrEqualTo(blockCount),
          );
          visited.addAll(
            List.generate(
              read.blockCount,
              (offset) => read.startBlock + offset,
            ),
          );
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
