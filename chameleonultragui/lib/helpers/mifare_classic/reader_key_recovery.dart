import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/recovery/recovery.dart';

const int mfkey32NoKey = 0xFFFFFFFFFFFFFFFF;

class ReaderKeyTarget {
  final int uid;
  final int sector;
  final bool keyB;

  const ReaderKeyTarget({
    required this.uid,
    required this.sector,
    required this.keyB,
  });

  String get keyType => keyB ? 'B' : 'A';

  @override
  bool operator ==(Object other) =>
      other is ReaderKeyTarget &&
      uid == other.uid &&
      sector == other.sector &&
      keyB == other.keyB;

  @override
  int get hashCode => Object.hash(uid, sector, keyB);
}

class ReaderKeyTargetRecords {
  final ReaderKeyTarget target;
  final List<DetectionResult> records;
  final Set<int> blocks;

  const ReaderKeyTargetRecords({
    required this.target,
    required this.records,
    required this.blocks,
  });
}

enum ReaderKeyRecoveryFailure {
  needsMoreRecords,
  noKey,
  solverError,
  cancelled,
}

class ReaderKeyRecoveryResult {
  final ReaderKeyTarget target;
  final Uint8List? key;
  final Set<int> blocks;
  final int transcriptCount;
  final int attemptedPairs;
  final ReaderKeyRecoveryFailure? failure;
  final String? error;

  ReaderKeyRecoveryResult({
    required this.target,
    required this.key,
    required this.blocks,
    required this.transcriptCount,
    required this.attemptedPairs,
    this.failure,
    this.error,
  });
}

int readerKeySectorTrailerBlock(int sector) {
  if (sector < 0 || sector > 39) {
    throw RangeError.range(sector, 0, 39, 'sector');
  }
  return sector < 32 ? sector * 4 + 3 : 128 + (sector - 32) * 16 + 15;
}

Uint8List applyReaderKeyToTrailer({
  required Uint8List trailer,
  required Uint8List key,
  required bool keyB,
}) {
  if (trailer.length != 16) {
    throw ArgumentError.value(trailer.length, 'trailer.length', 'must be 16');
  }
  if (key.length != 6) {
    throw ArgumentError.value(key.length, 'key.length', 'must be 6');
  }

  final output = Uint8List.fromList(trailer);
  output.setRange(keyB ? 10 : 0, keyB ? 16 : 6, key);
  if (keyB) {
    var condition = readerKeyTrailerAccessCondition(output);
    if (condition == null) {
      // The firmware rejects all access when any redundant complement differs.
      // Keep the effective C bits and rebuild only their inverted copies.
      var invertedC1 = 0;
      var invertedC2 = 0;
      var invertedC3 = 0;
      for (var group = 0; group < 4; group++) {
        invertedC1 |= (((output[7] >> (4 + group)) & 1) ^ 1) << group;
        invertedC2 |= (((output[8] >> group) & 1) ^ 1) << group;
        invertedC3 |= (((output[8] >> (4 + group)) & 1) ^ 1) << group;
      }
      output[6] = invertedC1 | (invertedC2 << 4);
      output[7] = (output[7] & 0xF0) | invertedC3;
      condition = readerKeyTrailerAccessCondition(output);
    }
    if (const {0, 2, 4}.contains(condition)) {
      // A readable Key B is data, not an authentication key. Change only the
      // trailer condition to 100 and preserve all data-block access bits.
      output[6] = (output[6] | 0x80) & 0xF7;
      output[7] |= 0x88;
      output[8] &= 0x77;
    }
  }
  return output;
}

int? readerKeyTrailerAccessCondition(Uint8List trailer) {
  if (trailer.length != 16) {
    throw ArgumentError.value(trailer.length, 'trailer.length', 'must be 16');
  }

  for (var group = 0; group < 4; group++) {
    final c1 = (trailer[7] >> (4 + group)) & 1;
    final c2 = (trailer[8] >> group) & 1;
    final c3 = (trailer[8] >> (4 + group)) & 1;
    final invertedC1 = (trailer[6] >> group) & 1;
    final invertedC2 = (trailer[6] >> (4 + group)) & 1;
    final invertedC3 = (trailer[7] >> group) & 1;
    if (invertedC1 == c1 || invertedC2 == c2 || invertedC3 == c3) {
      return null;
    }
  }

  const group = 3;
  final c1 = (trailer[7] >> (4 + group)) & 1;
  final c2 = (trailer[8] >> group) & 1;
  final c3 = (trailer[8] >> (4 + group)) & 1;
  return c1 | (c2 << 1) | (c3 << 2);
}

Uint8List applyUidToSyntheticManufacturerBlock({
  required Uint8List block,
  required Uint8List uid,
}) {
  if (block.length != 16) {
    throw ArgumentError.value(block.length, 'block.length', 'must be 16');
  }
  if (uid.length != 4) {
    throw ArgumentError.value(uid.length, 'uid.length', 'must be 4');
  }
  final output = Uint8List.fromList(block);
  output.setRange(0, 4, uid);
  output[4] = uid.fold(0, (bcc, byte) => bcc ^ byte);
  return output;
}

typedef ReaderMfkey32Solver = Future<int?> Function(Mfkey32Dart request);

List<ReaderKeyTargetRecords> groupReaderKeyRecords(
  Iterable<DetectionResult> detections,
) {
  final grouped = <ReaderKeyTarget, List<DetectionResult>>{};
  final blocks = <ReaderKeyTarget, Set<int>>{};
  final seen = <ReaderKeyTarget, Set<String>>{};

  for (final detection in detections) {
    final target = ReaderKeyTarget(
      uid: detection.uid,
      sector: mfClassicGetSectorByBlock(detection.block),
      keyB: detection.type == 0x61,
    );
    blocks.putIfAbsent(target, () => <int>{}).add(detection.block);
    final transcriptId = '${detection.nt}:${detection.nr}:${detection.ar}';
    if (seen.putIfAbsent(target, () => <String>{}).add(transcriptId)) {
      grouped.putIfAbsent(target, () => <DetectionResult>[]).add(detection);
    }
  }

  final output = [
    for (final entry in grouped.entries)
      ReaderKeyTargetRecords(
        target: entry.key,
        records: List.unmodifiable(entry.value),
        blocks: Set.unmodifiable(blocks[entry.key]!),
      ),
  ];
  output.sort((a, b) {
    final uidOrder = a.target.uid.compareTo(b.target.uid);
    if (uidOrder != 0) return uidOrder;
    final sectorOrder = a.target.sector.compareTo(b.target.sector);
    if (sectorOrder != 0) return sectorOrder;
    return a.target.keyB == b.target.keyB ? 0 : (a.target.keyB ? 1 : -1);
  });
  return output;
}

String readerKeyTranscriptIdentity(DetectionResult detection) =>
    '${detection.uid}:${detection.block}:${detection.type}:'
    '${detection.isNested ? 1 : 0}:${detection.nt}:${detection.nr}:${detection.ar}';

String readerKeyEvidenceFingerprint(Iterable<DetectionResult> detections) {
  final identities =
      detections.map(readerKeyTranscriptIdentity).toSet().toList()..sort();
  return identities.join('|');
}

bool hasRecoverableReaderKeyEvidence(Iterable<DetectionResult> detections) {
  final groups = groupReaderKeyRecords(detections);
  if (groups.any((group) => group.records.length >= 2)) return true;

  final recordsByUid = <int, int>{};
  for (final group in groups) {
    recordsByUid.update(
      group.target.uid,
      (count) => count + group.records.length,
      ifAbsent: () => group.records.length,
    );
  }
  return recordsByUid.values.any((count) => count >= 2);
}

Future<List<ReaderKeyRecoveryResult>> recoverReaderKeys({
  required Iterable<DetectionResult> detections,
  required ReaderMfkey32Solver solver,
  int maxPairsPerTarget = 256,
  int maxCrossTargetPairs = 512,
  bool Function()? isCancelled,
  void Function(int completed, int total, ReaderKeyTarget target)? onProgress,
}) async {
  final groups = groupReaderKeyRecords(detections);
  final results = <ReaderKeyRecoveryResult>[];

  for (final group in groups) {
    if (isCancelled?.call() == true) {
      results.add(
        _failureResult(
          group,
          ReaderKeyRecoveryFailure.cancelled,
          attemptedPairs: 0,
        ),
      );
      break;
    }

    final records = group.records;
    if (records.length < 2) {
      results.add(
        _failureResult(
          group,
          ReaderKeyRecoveryFailure.needsMoreRecords,
          attemptedPairs: 0,
        ),
      );
      onProgress?.call(results.length, groups.length, group.target);
      continue;
    }

    Uint8List? key;
    Object? solverError;
    var attempts = 0;

    // Different tag nonces usually provide the strongest pair. A second pass
    // permits static-nonce captures where NR/AR still differ.
    for (final requireDifferentNt in [true, false]) {
      for (var i = 0; i < records.length && key == null; i++) {
        for (var j = i + 1; j < records.length && key == null; j++) {
          if ((records[i].nt != records[j].nt) != requireDifferentNt) continue;
          if (attempts >= maxPairsPerTarget || isCancelled?.call() == true) {
            break;
          }
          attempts++;
          try {
            final raw = await solver(
              Mfkey32Dart(
                uid: group.target.uid,
                nt0: records[i].nt,
                nt1: records[j].nt,
                nr0Enc: records[i].nr,
                ar0Enc: records[i].ar,
                nr1Enc: records[j].nr,
                ar1Enc: records[j].ar,
              ),
            );
            key = _mfkey32Bytes(raw);
          } catch (error) {
            solverError = error;
            break;
          }
        }
        if (attempts >= maxPairsPerTarget || solverError != null) break;
      }
      if (key != null ||
          solverError != null ||
          attempts >= maxPairsPerTarget ||
          isCancelled?.call() == true) {
        break;
      }
    }

    final cancelled = isCancelled?.call() == true;
    results.add(
      ReaderKeyRecoveryResult(
        target: group.target,
        key: key,
        blocks: group.blocks,
        transcriptCount: records.length,
        attemptedPairs: attempts,
        failure: key != null
            ? null
            : cancelled
            ? ReaderKeyRecoveryFailure.cancelled
            : solverError != null
            ? ReaderKeyRecoveryFailure.solverError
            : ReaderKeyRecoveryFailure.noKey,
        error: solverError?.toString(),
      ),
    );
    onProgress?.call(results.length, groups.length, group.target);
    if (cancelled) break;
  }

  if (isCancelled?.call() != true && maxCrossTargetPairs > 0) {
    var crossAttempts = 0;
    final resultIndexes = <ReaderKeyTarget, int>{
      for (var index = 0; index < results.length; index++)
        results[index].target: index,
    };

    for (
      var leftIndex = 0;
      leftIndex < groups.length && crossAttempts < maxCrossTargetPairs;
      leftIndex++
    ) {
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < groups.length && crossAttempts < maxCrossTargetPairs;
        rightIndex++
      ) {
        final left = groups[leftIndex];
        final right = groups[rightIndex];
        if (left.target.uid != right.target.uid) continue;

        final leftResultIndex = resultIndexes[left.target];
        final rightResultIndex = resultIndexes[right.target];
        if (leftResultIndex == null || rightResultIndex == null) continue;
        if (results[leftResultIndex].key != null &&
            results[rightResultIndex].key != null) {
          continue;
        }

        Uint8List? sharedKey;
        for (final leftRecord in left.records) {
          for (final rightRecord in right.records) {
            if (crossAttempts >= maxCrossTargetPairs ||
                isCancelled?.call() == true) {
              break;
            }
            if (leftRecord.nt == rightRecord.nt &&
                leftRecord.nr == rightRecord.nr &&
                leftRecord.ar == rightRecord.ar) {
              continue;
            }
            crossAttempts++;
            try {
              final raw = await solver(
                Mfkey32Dart(
                  uid: left.target.uid,
                  nt0: leftRecord.nt,
                  nt1: rightRecord.nt,
                  nr0Enc: leftRecord.nr,
                  ar0Enc: leftRecord.ar,
                  nr1Enc: rightRecord.nr,
                  ar1Enc: rightRecord.ar,
                ),
              );
              sharedKey = _mfkey32Bytes(raw);
            } catch (_) {
              break;
            }
            if (sharedKey != null) break;
          }
          if (sharedKey != null || isCancelled?.call() == true) break;
        }
        if (sharedKey == null) continue;

        final leftExisting = results[leftResultIndex].key;
        final rightExisting = results[rightResultIndex].key;
        if ((leftExisting != null && !_sameKey(leftExisting, sharedKey)) ||
            (rightExisting != null && !_sameKey(rightExisting, sharedKey))) {
          continue;
        }
        if (leftExisting == null) {
          results[leftResultIndex] = _recoveredResult(
            left,
            sharedKey,
            attemptedPairs: results[leftResultIndex].attemptedPairs + 1,
          );
        }
        if (rightExisting == null) {
          results[rightResultIndex] = _recoveredResult(
            right,
            sharedKey,
            attemptedPairs: results[rightResultIndex].attemptedPairs + 1,
          );
        }
      }
    }
  }

  return results;
}

Uint8List? _mfkey32Bytes(int? raw) {
  if (raw == null || raw == mfkey32NoKey) return null;
  final value = raw & 0xFFFFFFFFFFFF;
  return Uint8List.fromList([
    for (var shift = 40; shift >= 0; shift -= 8) (value >> shift) & 0xFF,
  ]);
}

bool _sameKey(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

ReaderKeyRecoveryResult _recoveredResult(
  ReaderKeyTargetRecords group,
  Uint8List key, {
  required int attemptedPairs,
}) {
  return ReaderKeyRecoveryResult(
    target: group.target,
    key: key,
    blocks: group.blocks,
    transcriptCount: group.records.length,
    attemptedPairs: attemptedPairs,
  );
}

ReaderKeyRecoveryResult _failureResult(
  ReaderKeyTargetRecords group,
  ReaderKeyRecoveryFailure failure, {
  required int attemptedPairs,
}) {
  return ReaderKeyRecoveryResult(
    target: group.target,
    key: null,
    blocks: group.blocks,
    transcriptCount: group.records.length,
    attemptedPairs: attemptedPairs,
    failure: failure,
  );
}
