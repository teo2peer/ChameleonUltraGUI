import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/candidate_priority.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List key(int n) => hexToBytes(n.toRadixString(16).padLeft(12, '0'));
List<String> hexes(List<Uint8List> l) => l.map(bytesToHex).toList();

void main() {
  group('prioritiseCandidates', () {
    test('short lists are returned unchanged (same instance)', () {
      final keys = [key(1), key(2), key(3)];
      final out = prioritiseCandidates(keys, {bytesToHex(keys[2])});
      expect(identical(out, keys), true);
    });

    test('short lists can still apply probability priors when requested', () {
      final keys = [key(1), key(2), key(3)];
      final out = prioritiseCandidates(keys, {
        bytesToHex(keys[2]),
      }, minLength: 0);
      expect(hexes(out), hexes([keys[2], keys[0], keys[1]]));
    });

    test('likely keys move to the front, other order preserved, none lost', () {
      final keys = List.generate(70, key);
      final likely = {bytesToHex(keys[40]), bytesToHex(keys[65])};
      final out = prioritiseCandidates(keys, likely, minLength: 0);

      expect(out.length, keys.length);
      expect(
        hexes(out).toSet(),
        hexes(keys).toSet(),
      ); // same set, nothing dropped
      expect(bytesToHex(out[0]), bytesToHex(keys[40])); // likely first (stable)
      expect(bytesToHex(out[1]), bytesToHex(keys[65]));

      final rest = hexes(out.sublist(2));
      final expectedRest = hexes(
        keys.where((k) => !likely.contains(bytesToHex(k))).toList(),
      );
      expect(rest, expectedRest); // non-priority keeps original relative order
    });

    test('no likely match returns the original list instance', () {
      final keys = List.generate(70, key);
      final out = prioritiseCandidates(keys, {'aaaaaaaaaaaa'}, minLength: 0);
      expect(identical(out, keys), true);
    });
  });

  group('rankCandidateConsensus', () {
    test('one sample is never enough for on-card verification', () {
      final result = rankCandidateConsensus([
        {1, 2, 3},
      ]);
      expect(result.candidates, isEmpty);
      expect(result.support, 1);
    });

    test(
      'disjoint samples are rejected instead of replacing prior evidence',
      () {
        final result = rankCandidateConsensus([
          {1, 2},
          {3, 4},
        ]);
        expect(result.candidates, isEmpty);
        expect(result.support, 1);
      },
    );

    test('ranks candidates by support across captures', () {
      final result = rankCandidateConsensus([
        {10, 20, 42},
        {20, 42, 99},
        {42, 100},
      ]);
      expect(result.candidates, [42]);
      expect(result.support, 3);
    });

    test('an incompatible outlier cannot destroy existing consensus', () {
      final result = rankCandidateConsensus([
        {10, 42},
        {20, 42},
        {100, 200, 300},
      ]);
      expect(result.candidates, [42]);
      expect(result.support, 2);
    });

    test('equally supported candidates have deterministic ordering', () {
      final result = rankCandidateConsensus([
        {30, 10},
        {10, 30},
      ]);
      expect(result.candidates, [10, 30]);
      expect(result.support, 2);
    });
  });

  group('rankCandidatesBySupport', () {
    test('puts repeated candidates first without dropping singletons', () {
      final ranked = rankCandidatesBySupport([
        [30, 10, 42],
        [20, 42, 10],
        [42, 99],
      ]);

      expect(ranked, [42, 10, 20, 30, 99]);
    });

    test('does not count duplicates twice within one capture', () {
      final ranked = rankCandidatesBySupport([
        [7, 7, 8],
        [8],
      ]);

      expect(ranked, [8, 7]);
    });
  });

  group('prioritiseAndLimitCandidates', () {
    test('moves likely candidates ahead of the verification budget', () {
      final candidates = List<int>.generate(100, (index) => index);

      final selected = prioritiseAndLimitCandidates(candidates, {42, 99}, 5);

      expect(selected, [42, 99, 0, 1, 2]);
    });

    test('deduplicates candidates and enforces zero budget', () {
      expect(prioritiseAndLimitCandidates([1, 1, 2, 3], {}, 3), [1, 2, 3]);
      expect(prioritiseAndLimitCandidates([1, 2], {2}, 0), isEmpty);
    });
  });

  group('prioritiseByFrequency', () {
    test('duplicates + defaults first, most-frequent first, nothing lost', () {
      final a = key(1); // count 3  -> duplicate
      final b = key(2); // count 2  -> duplicate
      final c = key(3); // count 1, not default -> rest
      final d = key(0xFF); // count 1 but default -> priority
      final counts = {
        bytesToHex(a): 3,
        bytesToHex(b): 2,
        bytesToHex(c): 1,
        bytesToHex(d): 1,
      };
      final defaults = {bytesToHex(d)};

      final out = prioritiseByFrequency([c, b, d, a], counts, defaults);

      expect(out.length, 4); // nothing lost
      expect(bytesToHex(out[0]), bytesToHex(a)); // freq 3 first
      expect(bytesToHex(out[1]), bytesToHex(b)); // freq 2 next
      expect(bytesToHex(out[2]), bytesToHex(d)); // default, in priority group
      expect(bytesToHex(out[3]), bytesToHex(c)); // non-priority last
    });
  });
}
