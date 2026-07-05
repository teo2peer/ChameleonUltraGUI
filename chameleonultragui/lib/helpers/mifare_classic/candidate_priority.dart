import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';

// Pure, dependency-free candidate-ordering helpers used by the MIFARE Classic
// key-recovery engine. Kept separate from recovery.dart so they can be unit
// tested without a live device / app state. All are ORDER-ONLY: they never add,
// drop or mutate keys — the caller always confirms candidates on-card.

/// Reorder [keys] so the ones whose hex is in [likely] come first (stable),
/// leaving everything else in original order. `checkKeysOnSector` breaks on the
/// first hit, so front-loading likely keys (default keys, keys already found on
/// other sectors) turns an average half-list scan into an early hit.
///
/// For short lists (< [minLength]) the reordering isn't worth it, so the list is
/// returned unchanged. If nothing matches [likely], the original list is
/// returned (no allocation of a reordered copy).
List<Uint8List> prioritiseCandidates(List<Uint8List> keys, Set<String> likely,
    {int minLength = 64}) {
  if (keys.length < minLength) return keys;
  final pri = <Uint8List>[];
  final rest = <Uint8List>[];
  for (final k in keys) {
    (likely.contains(bytesToHex(k)) ? pri : rest).add(k);
  }
  return pri.isEmpty ? keys : [...pri, ...rest];
}

/// Intersect [current] with [next]. If [current] is null this is the first set,
/// so [next] is returned as-is. If the intersection is empty (e.g. a bad nonce
/// pair), the newer set [next] is kept instead — so narrowing can never wipe out
/// every candidate and leave nothing to test. The real key is present in every
/// valid set, so repeated intersection only removes false candidates.
Set<int> narrowCandidates(Set<int>? current, Set<int> next) {
  if (current == null) return next;
  final inter = current.intersection(next);
  return inter.isEmpty ? next : inter;
}

/// Reorder [list] putting cross-sector duplicates (a hex appearing in [counts]
/// with count >= 2) and [defaults] first, most-frequent first within that
/// priority group. Used by the RF08S backdoor recovery, where a candidate key
/// shared across sectors (key reuse) is far likelier to be the real key.
List<Uint8List> prioritiseByFrequency(
    List<Uint8List> list, Map<String, int> counts, Set<String> defaults) {
  final pri = <Uint8List>[];
  final rest = <Uint8List>[];
  for (final k in list) {
    final h = bytesToHex(k);
    if ((counts[h] ?? 0) >= 2 || defaults.contains(h)) {
      pri.add(k);
    } else {
      rest.add(k);
    }
  }
  pri.sort((a, b) =>
      (counts[bytesToHex(b)] ?? 0).compareTo(counts[bytesToHex(a)] ?? 0));
  return [...pri, ...rest];
}
