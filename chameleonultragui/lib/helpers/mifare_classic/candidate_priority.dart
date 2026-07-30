import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';

// Pure, dependency-free candidate selection and ordering helpers used by the
// MIFARE Classic key-recovery engine. Kept separate from recovery.dart so they
// can be unit tested without a live device or app state.

/// Reorder [keys] so the ones whose hex is in [likely] come first (stable),
/// leaving everything else in original order. `checkKeysOnSector` breaks on the
/// first hit, so front-loading likely keys (default keys, keys already found on
/// other sectors) turns an average half-list scan into an early hit.
///
/// For short lists (< [minLength]) the reordering isn't worth it, so the list is
/// returned unchanged. If nothing matches [likely], the original list is
/// returned (no allocation of a reordered copy).
List<Uint8List> prioritiseCandidates(
  List<Uint8List> keys,
  Set<String> likely, {
  int minLength = 64,
}) {
  if (keys.length < minLength) return keys;
  final pri = <Uint8List>[];
  final rest = <Uint8List>[];
  for (final k in keys) {
    (likely.contains(bytesToHex(k)) ? pri : rest).add(k);
  }
  return pri.isEmpty ? keys : [...pri, ...rest];
}

/// Return only the candidates with the strongest support across independent
/// nonce captures. A single capture is not consensus and therefore produces no
/// candidates for on-card verification.
({List<int> candidates, int support}) rankCandidateConsensus(
  Iterable<Set<int>> samples,
) {
  final supportByKey = <int, int>{};
  for (final sample in samples) {
    for (final key in sample) {
      supportByKey[key] = (supportByKey[key] ?? 0) + 1;
    }
  }

  var strongestSupport = 0;
  for (final support in supportByKey.values) {
    if (support > strongestSupport) strongestSupport = support;
  }
  if (strongestSupport < 2) {
    return (candidates: const <int>[], support: strongestSupport);
  }

  final candidates = <int>[
    for (final entry in supportByKey.entries)
      if (entry.value == strongestSupport) entry.key,
  ]..sort();
  return (candidates: candidates, support: strongestSupport);
}

/// Rank every distinct candidate by the number of independent captures that
/// produced it. No candidate is dropped, so low-confidence keys remain a safe
/// fallback after repeated keys have been tried first.
List<int> rankCandidatesBySupport(Iterable<Iterable<int>> samples) {
  final supportByKey = <int, int>{};
  for (final sample in samples) {
    for (final key in sample.toSet()) {
      supportByKey[key] = (supportByKey[key] ?? 0) + 1;
    }
  }

  final entries = supportByKey.entries.toList()
    ..sort((a, b) {
      final supportOrder = b.value.compareTo(a.value);
      return supportOrder != 0 ? supportOrder : a.key.compareTo(b.key);
    });
  return entries.map((entry) => entry.key).toList();
}

/// Move known-likely integer candidates first and return at most [limit]
/// distinct values. Recovery uses this before sending candidates to firmware so
/// uninformative captures cannot create an unbounded authentication workload.
List<int> prioritiseAndLimitCandidates(
  List<int> candidates,
  Set<int> likely,
  int limit,
) {
  if (limit <= 0) return const [];

  final selected = <int>[];
  final seen = <int>{};
  for (final candidate in candidates) {
    if (likely.contains(candidate) && seen.add(candidate)) {
      selected.add(candidate);
      if (selected.length == limit) return selected;
    }
  }
  for (final candidate in candidates) {
    if (seen.add(candidate)) {
      selected.add(candidate);
      if (selected.length == limit) break;
    }
  }
  return selected;
}

/// Reorder [list] putting cross-sector duplicates (a hex appearing in [counts]
/// with count >= 2) and [defaults] first, most-frequent first within that
/// priority group. Used by the RF08S backdoor recovery, where a candidate key
/// shared across sectors (key reuse) is far likelier to be the real key.
List<Uint8List> prioritiseByFrequency(
  List<Uint8List> list,
  Map<String, int> counts,
  Set<String> defaults,
) {
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
  pri.sort(
    (a, b) =>
        (counts[bytesToHex(b)] ?? 0).compareTo(counts[bytesToHex(a)] ?? 0),
  );
  return [...pri, ...rest];
}
