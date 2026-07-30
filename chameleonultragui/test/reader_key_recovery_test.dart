import 'dart:typed_data';

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

List<int> accessBytes(List<int> conditions) {
  var byte6 = 0;
  var byte7 = 0;
  var byte8 = 0;
  for (var group = 0; group < 4; group++) {
    final condition = conditions[group];
    final c1 = condition & 1;
    final c2 = (condition >> 1) & 1;
    final c3 = (condition >> 2) & 1;
    byte6 |= (c1 ^ 1) << group;
    byte6 |= (c2 ^ 1) << (4 + group);
    byte7 |= c1 << (4 + group);
    byte7 |= (c3 ^ 1) << group;
    byte8 |= c2 << group;
    byte8 |= c3 << (4 + group);
  }
  return [byte6, byte7, byte8, 0x69];
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

    test(
      'deduplicates exact transcripts but retains static-nonce exchanges',
      () {
        final duplicate = record(block: 4, nt: 1, nr: 2, ar: 3);
        final groups = groupReaderKeyRecords([
          duplicate,
          record(block: 5, nt: 1, nr: 2, ar: 3),
          record(block: 6, nt: 1, nr: 8, ar: 9),
        ]);

        expect(groups.single.records, hasLength(2));
        expect(groups.single.blocks, {4, 5, 6});
      },
    );
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

    test(
      'accepts all-FF 48-bit key without confusing it with sentinel',
      () async {
        final results = await recoverReaderKeys(
          detections: [
            record(block: 4, nt: 1, nr: 2, ar: 3),
            record(block: 5, nt: 2, nr: 3, ar: 4),
          ],
          solver: (_) async => 0x0000FFFFFFFFFFFF,
        );

        expect(bytesToHex(results.single.key!), 'ffffffffffff');
      },
    );

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

    test(
      'retains every distinct key recovered from different sectors',
      () async {
        final results = await recoverReaderKeys(
          detections: [
            record(block: 4, nt: 1, nr: 2, ar: 3),
            record(block: 5, nt: 2, nr: 3, ar: 4),
            record(block: 8, nt: 3, nr: 4, ar: 5),
            record(block: 9, nt: 4, nr: 5, ar: 6),
          ],
          solver: (request) async =>
              request.nt0 < 3 ? 0x010203040506 : 0xA0A1A2A3A4A5,
          maxCrossTargetPairs: 0,
        );

        expect(results.map((result) => bytesToHex(result.key!)).toSet(), {
          '010203040506',
          'a0a1a2a3a4a5',
        });
      },
    );

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
      expect(results.map((result) => bytesToHex(result.key!)), [
        'a0a1a2a3a4a5',
        'a0a1a2a3a4a5',
      ]);
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

  group('reader-key work slot', () {
    test('maps every Classic sector to its trailer block', () {
      expect(readerKeySectorTrailerBlock(0), 3);
      expect(readerKeySectorTrailerBlock(31), 127);
      expect(readerKeySectorTrailerBlock(32), 143);
      expect(readerKeySectorTrailerBlock(39), 255);
      expect(() => readerKeySectorTrailerBlock(40), throwsRangeError);
    });

    test('replaces only Key A in an existing trailer', () {
      final trailer = Uint8List.fromList([
        ...List.filled(6, 0xFF),
        0xFF,
        0x07,
        0x80,
        0x69,
        ...List.filled(6, 0xAA),
      ]);
      final patched = applyReaderKeyToTrailer(
        trailer: trailer,
        key: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        keyB: false,
      );

      expect(patched.sublist(0, 6), [1, 2, 3, 4, 5, 6]);
      expect(patched.sublist(6), trailer.sublist(6));
    });

    test('makes a readable Key B usable for authentication', () {
      final patched = applyReaderKeyToTrailer(
        trailer: Uint8List.fromList([
          ...List.filled(6, 0xFF),
          0xFF,
          0x07,
          0x80,
          0x69,
          ...List.filled(6, 0xFF),
        ]),
        key: Uint8List.fromList([6, 5, 4, 3, 2, 1]),
        keyB: true,
      );

      expect(patched.sublist(6, 10), [0xF7, 0x8F, 0x00, 0x69]);
      expect(patched.sublist(10), [6, 5, 4, 3, 2, 1]);
      expect(readerKeyTrailerAccessCondition(patched), 1);
    });

    test('preserves every data-block access condition for recovered Key B', () {
      final trailer = Uint8List.fromList([
        ...List.filled(6, 0xFF),
        ...accessBytes([7, 6, 5, 4]),
        ...List.filled(6, 0xFF),
      ]);
      final patched = applyReaderKeyToTrailer(
        trailer: trailer,
        key: Uint8List.fromList([6, 5, 4, 3, 2, 1]),
        keyB: true,
      );

      for (final index in [6, 7, 8]) {
        expect(patched[index] & 0x77, trailer[index] & 0x77);
      }
      expect(readerKeyTrailerAccessCondition(patched), 1);
    });

    test('keeps an existing authenticatable Key B condition', () {
      final trailer = Uint8List.fromList([
        ...List.filled(6, 0xFF),
        ...accessBytes([0, 0, 0, 6]),
        ...List.filled(6, 0xFF),
      ]);
      final patched = applyReaderKeyToTrailer(
        trailer: trailer,
        key: Uint8List.fromList([6, 5, 4, 3, 2, 1]),
        keyB: true,
      );

      expect(patched.sublist(6, 10), trailer.sublist(6, 10));
      expect(readerKeyTrailerAccessCondition(patched), 6);
    });

    test(
      'repairs invalid complements without changing effective data bits',
      () {
        final trailer = Uint8List.fromList([
          ...List.filled(6, 0xFF),
          ...accessBytes([7, 6, 5, 6]),
          ...List.filled(6, 0xFF),
        ]);
        trailer[6] ^= 0x01;
        expect(readerKeyTrailerAccessCondition(trailer), isNull);

        final patched = applyReaderKeyToTrailer(
          trailer: trailer,
          key: Uint8List.fromList([6, 5, 4, 3, 2, 1]),
          keyB: true,
        );

        expect(patched[7] & 0xF0, trailer[7] & 0xF0);
        expect(patched[8], trailer[8]);
        expect(readerKeyTrailerAccessCondition(patched), 6);
      },
    );

    test('keeps a synthetic manufacturer block consistent with fixed UID', () {
      final patched = applyUidToSyntheticManufacturerBlock(
        block: Uint8List.fromList(List.generate(16, (index) => index)),
        uid: Uint8List.fromList([0x11, 0x22, 0x33, 0x44]),
      );

      expect(patched.sublist(0, 4), [0x11, 0x22, 0x33, 0x44]);
      expect(patched[4], 0x44);
      expect(patched.sublist(5), List.generate(11, (index) => index + 5));
    });
  });
}
