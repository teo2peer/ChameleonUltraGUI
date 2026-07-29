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
  cancelled
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
      results.add(_failureResult(
        group,
        ReaderKeyRecoveryFailure.cancelled,
        attemptedPairs: 0,
      ));
      break;
    }

    final records = group.records;
    if (records.length < 2) {
      results.add(_failureResult(
        group,
        ReaderKeyRecoveryFailure.needsMoreRecords,
        attemptedPairs: 0,
      ));
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
            final raw = await solver(Mfkey32Dart(
              uid: group.target.uid,
              nt0: records[i].nt,
              nt1: records[j].nt,
              nr0Enc: records[i].nr,
              ar0Enc: records[i].ar,
              nr1Enc: records[j].nr,
              ar1Enc: records[j].ar,
            ));
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
    results.add(ReaderKeyRecoveryResult(
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
    ));
    onProgress?.call(results.length, groups.length, group.target);
    if (cancelled) break;
  }

  if (isCancelled?.call() != true && maxCrossTargetPairs > 0) {
    var crossAttempts = 0;
    final resultIndexes = <ReaderKeyTarget, int>{
      for (var index = 0; index < results.length; index++)
        results[index].target: index,
    };

    for (var leftIndex = 0;
        leftIndex < groups.length && crossAttempts < maxCrossTargetPairs;
        leftIndex++) {
      for (var rightIndex = leftIndex + 1;
          rightIndex < groups.length && crossAttempts < maxCrossTargetPairs;
          rightIndex++) {
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
              final raw = await solver(Mfkey32Dart(
                uid: left.target.uid,
                nt0: leftRecord.nt,
                nt1: rightRecord.nt,
                nr0Enc: leftRecord.nr,
                ar0Enc: leftRecord.ar,
                nr1Enc: rightRecord.nr,
                ar1Enc: rightRecord.ar,
              ));
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
          results[leftResultIndex] = _recoveredResult(left, sharedKey,
              attemptedPairs: results[leftResultIndex].attemptedPairs + 1);
        }
        if (rightExisting == null) {
          results[rightResultIndex] = _recoveredResult(right, sharedKey,
              attemptedPairs: results[rightResultIndex].attemptedPairs + 1);
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
