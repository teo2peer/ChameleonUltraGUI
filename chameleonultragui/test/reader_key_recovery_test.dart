import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/reader_key_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

DetectionResult record({
  int uid = 0x11223344,
  required int block,
  int type = 0x60,
  required int nt,
  required int nr,
  required int ar,
  bool nested = false,
}) {
  return DetectionResult(
    block: block,
    type: type,
    isNested: nested,
    uid: uid,
    nt: nt,
    nr: nr,
    ar: ar,
  );
}

void main() {
  group('reader-key grouping', () {
    test('combines different blocks from the same sector and key type', () {
      final groups = groupReaderKeyRecords([
        record(block: 4, nt: 1, nr: 2, ar: 3),
        record(block: 5, nt: 4, nr: 5, ar: 6),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.target.sector, 1);
      expect(groups.single.target.keyType, 'A');
      expect(groups.single.records, hasLength(2));
      expect(groups.single.blocks, {4, 5});
    });

    test('keeps sectors, UIDs, and key A/B as separate targets', () {
      final groups = groupReaderKeyRecords([
        record(block: 4, nt: 1, nr: 2, ar: 3),
        record(block: 8, nt: 1, nr: 2, ar: 3),
        record(block: 4, type: 0x61, nt: 1, nr: 2, ar: 3),
        record(uid: 7, block: 4, nt: 1, nr: 2, ar: 3),
      ]);

      expect(groups, hasLength(4));
    });

    test('deduplicates exact transcripts but retains static-nonce exchanges',
        () {
      final duplicate = record(block: 4, nt: 1, nr: 2, ar: 3);
      final groups = groupReaderKeyRecords([
        duplicate,
        record(block: 5, nt: 1, nr: 2, ar: 3),
        record(block: 6, nt: 1, nr: 8, ar: 9),
      ]);

      expect(groups.single.records, hasLength(2));
      expect(groups.single.blocks, {4, 5, 6});
    });
  });

  group('reader-key recovery', () {
    test('rejects failure sentinel and continues to a later pair', () async {
      var calls = 0;
      final results = await recoverReaderKeys(
        detections: [
          record(block: 4, nt: 1, nr: 10, ar: 20),
          record(block: 5, nt: 2, nr: 11, ar: 21),
          record(block: 6, nt: 3, nr: 12, ar: 22),
        ],
        solver: (_) async => ++calls == 1 ? mfkey32NoKey : 0xA0A1A2A3A4A5,
      );

      expect(calls, 2);
      expect(results.single.key, isNotNull);
      expect(bytesToHex(results.single.key!), 'a0a1a2a3a4a5');
      expect(results.single.attemptedPairs, 2);
    });

    test('accepts all-FF 48-bit key without confusing it with sentinel',
        () async {
      final results = await recoverReaderKeys(
        detections: [
          record(block: 4, nt: 1, nr: 2, ar: 3),
          record(block: 5, nt: 2, nr: 3, ar: 4),
        ],
        solver: (_) async => 0x0000FFFFFFFFFFFF,
      );

      expect(bytesToHex(results.single.key!), 'ffffffffffff');
    });

    test('tries equal-NT records when reader challenges differ', () async {
      var calls = 0;
      final results = await recoverReaderKeys(
        detections: [
          record(block: 4, nt: 1, nr: 2, ar: 3),
          record(block: 5, nt: 1, nr: 8, ar: 9),
        ],
        solver: (_) async {
          calls++;
          return 0x010203040506;
        },
      );

      expect(calls, 1);
      expect(bytesToHex(results.single.key!), '010203040506');
    });

    test('returns one result per sector even when key values repeat', () async {
      final results = await recoverReaderKeys(
        detections: [
          record(block: 4, nt: 1, nr: 2, ar: 3),
          record(block: 5, nt: 2, nr: 3, ar: 4),
          record(block: 8, nt: 3, nr: 4, ar: 5),
          record(block: 9, nt: 4, nr: 5, ar: 6),
        ],
        solver: (_) async => 0xA0A1A2A3A4A5,
      );

      expect(results, hasLength(2));
      expect(results.map((result) => result.target.sector), [1, 2]);
      expect(results.every((result) => result.key != null), isTrue);
    });

    test('recovers a shared key from one transcript in each sector', () async {
      final results = await recoverReaderKeys(
        detections: [
          record(block: 4, nt: 1, nr: 2, ar: 3),
          record(block: 8, nt: 2, nr: 4, ar: 6),
        ],
        solver: (_) async => 0xA0A1A2A3A4A5,
      );

      expect(results, hasLength(2));
      expect(results.every((result) => result.key != null), isTrue);
      expect(
        results.map((result) => bytesToHex(result.key!)),
        ['a0a1a2a3a4a5', 'a0a1a2a3a4a5'],
      );
    });

    test('reports targets that need another authentication capture', () async {
      final results = await recoverReaderKeys(
        detections: [record(block: 4, nt: 1, nr: 2, ar: 3)],
        solver: (_) async => fail('solver should not run'),
      );

      expect(results.single.key, isNull);
      expect(results.single.failure, ReaderKeyRecoveryFailure.needsMoreRecords);
    });
  });
}
