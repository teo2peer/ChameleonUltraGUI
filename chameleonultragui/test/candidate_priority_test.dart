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

    test('likely keys move to the front, other order preserved, none lost', () {
      final keys = List.generate(70, key);
      final likely = {bytesToHex(keys[40]), bytesToHex(keys[65])};
      final out = prioritiseCandidates(keys, likely, minLength: 0);

      expect(out.length, keys.length);
      expect(hexes(out).toSet(), hexes(keys).toSet()); // same set, nothing dropped
      expect(bytesToHex(out[0]), bytesToHex(keys[40])); // likely first (stable)
      expect(bytesToHex(out[1]), bytesToHex(keys[65]));

      final rest = hexes(out.sublist(2));
      final expectedRest =
          hexes(keys.where((k) => !likely.contains(bytesToHex(k))).toList());
      expect(rest, expectedRest); // non-priority keeps original relative order
    });

    test('no likely match returns the original list instance', () {
      final keys = List.generate(70, key);
      final out = prioritiseCandidates(keys, {'aaaaaaaaaaaa'}, minLength: 0);
      expect(identical(out, keys), true);
    });
  });

  group('narrowCandidates', () {
    test('first set (null current) is returned as-is', () {
      expect(narrowCandidates(null, {1, 2, 3}), {1, 2, 3});
    });

    test('non-empty intersection narrows', () {
      expect(narrowCandidates({1, 2, 3}, {2, 3, 4}), {2, 3});
    });

    test('empty intersection keeps the newer set (never wipes out candidates)',
        () {
      expect(narrowCandidates({1, 2}, {3, 4}), {3, 4});
    });

    test('converges to the key common to every set', () {
      var c = narrowCandidates(null, {10, 20, 30, 42});
      c = narrowCandidates(c, {20, 42, 99});
      c = narrowCandidates(c, {42, 20});
      expect(c.contains(42), true);
      expect(c.length <= 2, true);
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
