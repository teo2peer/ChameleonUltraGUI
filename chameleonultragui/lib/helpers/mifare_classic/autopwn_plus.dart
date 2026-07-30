import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

enum AutopwnPlusProfile { quick, balanced, deep }

enum AutopwnPlusPhase {
  idle,
  verifying,
  dictionary,
  recovery,
  dump,
  complete,
  cancelled,
}

class AutopwnPlusTarget {
  final int sector;
  final int keyType;

  const AutopwnPlusTarget(this.sector, this.keyType);
}

class AutopwnPlusVerifiedKey {
  final int sector;
  final int keyType;
  final Uint8List key;

  AutopwnPlusVerifiedKey({
    required this.sector,
    required this.keyType,
    required Uint8List key,
  }) : key = Uint8List.fromList(key);

  Map<String, Object> toJson() => {
    'sector': sector,
    'keyType': keyType == 0 ? 'A' : 'B',
    'keyHex': bytesToHex(key),
    'verified': true,
  };
}

class AutopwnPlusCardChanged implements Exception {
  @override
  String toString() =>
      'The card changed or left the antenna during recovery. The result was discarded.';
}

class AutopwnPlusProgress {
  final AutopwnPlusPhase phase;
  final String operation;
  final double? value;
  final Duration elapsed;

  const AutopwnPlusProgress({
    required this.phase,
    required this.operation,
    required this.value,
    required this.elapsed,
  });
}

class AutopwnPlusBlock {
  final int sector;
  final int block;
  final Uint8List? data;
  final bool syntheticKeys;

  const AutopwnPlusBlock({
    required this.sector,
    required this.block,
    required this.data,
    required this.syntheticKeys,
  });

  bool get readable => data != null;

  Map<String, Object?> toJson() => {
    'sector': sector,
    'block': block,
    'readable': readable,
    'dataHex': data == null ? null : bytesToHex(data!),
    'syntheticKeys': syntheticKeys,
  };
}

class AutopwnPlusOptions {
  final AutopwnPlusProfile profile;
  final Set<int> sectors;
  final List<Dictionary> dictionaries;
  final bool includeDefaults;
  final bool recoverMissing;
  final bool partialDump;

  const AutopwnPlusOptions({
    required this.profile,
    required this.sectors,
    required this.dictionaries,
    this.includeDefaults = true,
    this.recoverMissing = true,
    this.partialDump = true,
  });
}

class AutopwnPlusResult {
  final bool cancelled;
  final bool selectedKeysRecovered;
  final int verifiedKeySlots;
  final int selectedKeySlots;
  final List<AutopwnPlusVerifiedKey> verifiedKeys;
  final List<AutopwnPlusBlock> blocks;
  final Map<AutopwnPlusPhase, Duration> timings;
  final String error;

  const AutopwnPlusResult({
    required this.cancelled,
    required this.selectedKeysRecovered,
    required this.verifiedKeySlots,
    required this.selectedKeySlots,
    required this.verifiedKeys,
    required this.blocks,
    required this.timings,
    required this.error,
  });

  List<Uint8List> get keys =>
      verifiedKeys.map((entry) => Uint8List.fromList(entry.key)).toList();

  Map<String, Object?> toJson() => {
    'format': 'chameleon-autopwn-plus',
    'version': 1,
    'cancelled': cancelled,
    'selectedKeysRecovered': selectedKeysRecovered,
    'verifiedKeySlots': verifiedKeySlots,
    'selectedKeySlots': selectedKeySlots,
    'verifiedKeys': verifiedKeys.map((entry) => entry.toJson()).toList(),
    'timingsMs': {
      for (final entry in timings.entries)
        entry.key.name: entry.value.inMilliseconds,
    },
    'error': error,
    'blocks': blocks.map((block) => block.toJson()).toList(),
  };
}

abstract interface class AutopwnPlusRecoveryPort {
  int get sectorCount;
  bool get isCancelled;
  String get error;
  List<Uint8List> get validKeys;
  List<AutopwnPlusBlock> get dumpedBlocks;

  void cancel();
  Future<void> prepare(Set<int> sectors);
  Future<int> reverifySeededKeys(Set<int> sectors);
  List<AutopwnPlusTarget> unresolvedTargets(Set<int> sectors);
  Future<bool> checkTarget(
    AutopwnPlusTarget target,
    List<Uint8List> candidates,
  );
  Future<void> recoverMissing();
  bool selectedComplete(Set<int> sectors);
  int verifiedSlots(Set<int> sectors);
  List<AutopwnPlusVerifiedKey> verifiedKeys(Set<int> sectors);
  Future<List<AutopwnPlusBlock>> dumpSelected(
    Set<int> sectors,
    void Function(int completed, int total) onProgress, {
    Future<bool> Function()? cardGuard,
  });
}

List<Uint8List> buildAutopwnPlusCandidates({
  required AutopwnPlusProfile profile,
  required List<Dictionary> dictionaries,
  required Iterable<Uint8List> verifiedKeys,
  bool includeDefaults = true,
}) {
  final candidates = <Uint8List>[];
  final seen = <String>{};

  void add(Iterable<Uint8List> keys) {
    for (final key in keys) {
      if (key.length != 6) continue;
      final value = bytesToHex(key);
      if (seen.add(value)) candidates.add(Uint8List.fromList(key));
    }
  }

  add(verifiedKeys);
  if (includeDefaults) add(gMifareClassicKeys);
  for (final dictionary in dictionaries) {
    add(dictionary.keys);
  }

  if (profile == AutopwnPlusProfile.quick && candidates.length > 64) {
    return List.unmodifiable(candidates.take(64));
  }
  return List.unmodifiable(candidates);
}

List<List<Uint8List>> buildAutopwnPlusWaves(
  AutopwnPlusProfile profile,
  List<Uint8List> candidates,
) {
  final cutoffs = switch (profile) {
    AutopwnPlusProfile.quick => const [8, 24, 64],
    AutopwnPlusProfile.balanced => const [12, 48],
    AutopwnPlusProfile.deep => const [16, 64],
  };
  final waves = <List<Uint8List>>[];
  var offset = 0;
  for (final cutoff in cutoffs) {
    final end = cutoff < candidates.length ? cutoff : candidates.length;
    if (end > offset) waves.add(candidates.sublist(offset, end));
    offset = end;
  }
  if (offset < candidates.length) waves.add(candidates.sublist(offset));
  return waves;
}

Duration? estimateAutopwnPlusEta(Duration elapsed, double? progress) {
  if (progress == null || progress <= 0 || elapsed <= Duration.zero) {
    return null;
  }
  if (progress >= 1) return Duration.zero;
  final remainingMicros = (elapsed.inMicroseconds * (1 - progress) / progress)
      .round();
  return Duration(microseconds: remainingMicros);
}

class AutopwnPlusRunner {
  const AutopwnPlusRunner();

  Future<AutopwnPlusResult> run({
    required AutopwnPlusRecoveryPort recovery,
    required AutopwnPlusOptions options,
    void Function(AutopwnPlusProgress progress)? onProgress,
    Future<bool> Function()? cardGuard,
  }) async {
    final total = Stopwatch()..start();
    final timings = <AutopwnPlusPhase, Duration>{};
    var blocks = <AutopwnPlusBlock>[];

    void report(AutopwnPlusPhase phase, String operation, [double? value]) {
      onProgress?.call(
        AutopwnPlusProgress(
          phase: phase,
          operation: operation,
          value: value,
          elapsed: total.elapsed,
        ),
      );
    }

    Future<void> ensureCard() async {
      if (cardGuard != null && !await cardGuard()) {
        throw AutopwnPlusCardChanged();
      }
    }

    Future<void> timed(
      AutopwnPlusPhase phase,
      Future<void> Function() action,
    ) async {
      final watch = Stopwatch()..start();
      await action();
      watch.stop();
      timings[phase] = (timings[phase] ?? Duration.zero) + watch.elapsed;
    }

    try {
      await ensureCard();
      await recovery.prepare(options.sectors);
      await timed(AutopwnPlusPhase.verifying, () async {
        report(AutopwnPlusPhase.verifying, 'Re-verifying known keys');
        await recovery.reverifySeededKeys(options.sectors);
      });
      await ensureCard();

      final candidates = buildAutopwnPlusCandidates(
        profile: options.profile,
        dictionaries: options.dictionaries,
        verifiedKeys: recovery.validKeys.where((key) => key.isNotEmpty),
        includeDefaults: options.includeDefaults,
      );
      final waves = buildAutopwnPlusWaves(options.profile, candidates);

      await timed(AutopwnPlusPhase.dictionary, () async {
        for (var waveIndex = 0; waveIndex < waves.length; waveIndex++) {
          final targets = recovery.unresolvedTargets(options.sectors);
          if (targets.isEmpty || recovery.isCancelled) break;
          for (var index = 0; index < targets.length; index++) {
            if (recovery.isCancelled) break;
            final target = targets[index];
            final stillUnresolved = recovery
                .unresolvedTargets(options.sectors)
                .any(
                  (current) =>
                      current.sector == target.sector &&
                      current.keyType == target.keyType,
                );
            if (!stillUnresolved) continue;
            await ensureCard();
            report(
              AutopwnPlusPhase.dictionary,
              'Adaptive key wave ${waveIndex + 1}/${waves.length}',
              (waveIndex + (index + 1) / targets.length) /
                  (waves.isEmpty ? 1 : waves.length),
            );
            await recovery.checkTarget(target, waves[waveIndex]);
            await ensureCard();
          }
        }
      });

      if (!recovery.isCancelled &&
          options.recoverMissing &&
          !recovery.selectedComplete(options.sectors)) {
        await timed(AutopwnPlusPhase.recovery, () async {
          await ensureCard();
          report(
            AutopwnPlusPhase.recovery,
            'Running card-adaptive cryptanalytic recovery',
          );
          await recovery.recoverMissing();
          await ensureCard();
        });
      }

      if (!recovery.isCancelled && options.partialDump) {
        await timed(AutopwnPlusPhase.dump, () async {
          blocks = await recovery.dumpSelected(options.sectors, (
            completed,
            count,
          ) {
            report(
              AutopwnPlusPhase.dump,
              'Reading selected sectors',
              count == 0 ? 1 : completed / count,
            );
          }, cardGuard: cardGuard);
          await ensureCard();
        });
      }
    } on MifareClassicRecoveryCancelled {
      recovery.cancel();
      await ensureCard();
      blocks = recovery.dumpedBlocks;
    }

    total.stop();
    final cancelled = recovery.isCancelled;
    report(
      cancelled ? AutopwnPlusPhase.cancelled : AutopwnPlusPhase.complete,
      cancelled ? 'Stopped after current operation' : 'Autopwn+ complete',
      1,
    );
    return AutopwnPlusResult(
      cancelled: cancelled,
      selectedKeysRecovered: recovery.selectedComplete(options.sectors),
      verifiedKeySlots: recovery.verifiedSlots(options.sectors),
      selectedKeySlots: options.sectors.length * 2,
      verifiedKeys: recovery.verifiedKeys(options.sectors),
      blocks: List.unmodifiable(blocks),
      timings: Map.unmodifiable(timings),
      error: recovery.error,
    );
  }
}

class MifareClassicAutopwnPlusPort implements AutopwnPlusRecoveryPort {
  final MifareClassicRecovery recovery;
  Set<int> _selectedSectors = const {};
  final List<AutopwnPlusBlock> _dumpedBlocks = [];

  MifareClassicAutopwnPlusPort(this.recovery);

  @override
  int get sectorCount => mfClassicGetSectorCount(
    recovery.mifareClassicType,
    isEV1: recovery.isMifareClassicEV1,
  );

  @override
  bool get isCancelled => recovery.isCancelled;

  @override
  String get error => recovery.error;

  @override
  List<Uint8List> get validKeys => recovery.validKeys;

  @override
  List<AutopwnPlusBlock> get dumpedBlocks => List.unmodifiable(_dumpedBlocks);

  @override
  void cancel() => recovery.cancel();

  @override
  Future<void> prepare(Set<int> sectors) async {
    if (sectors.isEmpty ||
        sectors.any((sector) => sector < 0 || sector >= sectorCount)) {
      throw ArgumentError('Selected sectors are outside the detected card');
    }
    _selectedSectors = Set.unmodifiable(sectors);
    _dumpedBlocks.clear();
    recovery.clearActivityProgress();
    recovery.error = '';
    recovery.state = '';
    recovery.keyCheckProgress = null;
    recovery.hardnestedProgress = null;
    for (var sector = 0; sector < sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        final index = keyType == 0 ? sector : sector + 40;
        if (!sectors.contains(sector)) {
          recovery.checkMarks[index] = ChameleonKeyCheckmark.disabled;
          recovery.validKeys[index] = Uint8List(0);
        } else if (recovery.checkMarks[index] ==
            ChameleonKeyCheckmark.disabled) {
          recovery.checkMarks[index] = recovery.validKeys[index].isEmpty
              ? ChameleonKeyCheckmark.none
              : ChameleonKeyCheckmark.found;
        }
      }
    }
    _recalculateComplete();
    recovery.update();
  }

  @override
  Future<int> reverifySeededKeys(Set<int> sectors) async {
    var verified = 0;
    final seeds = <AutopwnPlusVerifiedKey>[];
    for (final sector in sectors.toList()..sort()) {
      for (var keyType = 0; keyType < 2; keyType++) {
        final index = keyType == 0 ? sector : sector + 40;
        final key = recovery.validKeys[index];
        if (recovery.checkMarks[index] == ChameleonKeyCheckmark.found &&
            key.isNotEmpty) {
          seeds.add(
            AutopwnPlusVerifiedKey(sector: sector, keyType: keyType, key: key),
          );
        }
        recovery.validKeys[index] = Uint8List(0);
        recovery.checkMarks[index] = ChameleonKeyCheckmark.none;
      }
    }
    recovery.update();
    recovery.setActivityProgress(
      'Seed key verification',
      completed: 0,
      total: seeds.length,
    );

    for (var seedIndex = 0; seedIndex < seeds.length; seedIndex++) {
      final seed = seeds[seedIndex];
      if (recovery.isCancelled) throw MifareClassicRecoveryCancelled();
      final index = seed.keyType == 0 ? seed.sector : seed.sector + 40;
      final valid = await recovery.appState.communicator!.mf1Auth(
        mfClassicGetSectorTrailerBlockBySector(seed.sector),
        0x60 + seed.keyType,
        seed.key,
      );
      if (valid) {
        recovery.setKeyAsFound(seed.sector, seed.keyType, seed.key);
        verified++;
      } else {
        recovery.validKeys[index] = Uint8List(0);
        recovery.checkMarks[index] = ChameleonKeyCheckmark.none;
      }
      recovery.setActivityProgress(
        'Seed key verification',
        completed: seedIndex + 1,
        total: seeds.length,
      );
      recovery.update();
    }
    _recalculateComplete();
    return verified;
  }

  @override
  List<AutopwnPlusTarget> unresolvedTargets(Set<int> sectors) => [
    for (final sector in sectors.toList()..sort())
      for (var keyType = 0; keyType < 2; keyType++)
        if (recovery.getSectorState(sector, keyType) !=
                ChameleonKeyCheckmark.found &&
            recovery.getSectorState(sector, keyType) !=
                ChameleonKeyCheckmark.disabled)
          AutopwnPlusTarget(sector, keyType),
  ];

  @override
  Future<bool> checkTarget(
    AutopwnPlusTarget target,
    List<Uint8List> candidates,
  ) async {
    if (candidates.isEmpty) return false;
    final found = await recovery.checkKeysOnSector(
      candidates,
      target.keyType,
      target.sector,
    );
    _recalculateComplete();
    return found;
  }

  @override
  Future<void> recoverMissing() async {
    final needsBootstrap =
        !_selectedSectors.contains(0) && verifiedSlots(_selectedSectors) == 0;
    if (needsBootstrap) {
      recovery.checkMarks[0] = ChameleonKeyCheckmark.none;
      recovery.checkMarks[40] = ChameleonKeyCheckmark.none;
    }
    try {
      await recovery.recoverKeys();
    } finally {
      if (needsBootstrap) {
        recovery.checkMarks[0] = ChameleonKeyCheckmark.disabled;
        recovery.checkMarks[40] = ChameleonKeyCheckmark.disabled;
        recovery.validKeys[0] = Uint8List(0);
        recovery.validKeys[40] = Uint8List(0);
      }
    }
    _recalculateComplete();
  }

  @override
  bool selectedComplete(Set<int> sectors) => unresolvedTargets(sectors).isEmpty;

  @override
  int verifiedSlots(Set<int> sectors) {
    var count = 0;
    for (final sector in sectors) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (recovery.getSectorState(sector, keyType) ==
            ChameleonKeyCheckmark.found) {
          count++;
        }
      }
    }
    return count;
  }

  @override
  List<AutopwnPlusVerifiedKey> verifiedKeys(Set<int> sectors) => [
    for (final sector in sectors.toList()..sort())
      for (var keyType = 0; keyType < 2; keyType++)
        if (recovery.getSectorState(sector, keyType) ==
                ChameleonKeyCheckmark.found &&
            recovery.getSectorKey(sector, keyType).isNotEmpty)
          AutopwnPlusVerifiedKey(
            sector: sector,
            keyType: keyType,
            key: recovery.getSectorKey(sector, keyType),
          ),
  ];

  void _recalculateComplete() {
    recovery.allKeysExists = true;
    for (var sector = 0; sector < sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        final state = recovery.getSectorState(sector, keyType);
        if (state != ChameleonKeyCheckmark.found &&
            state != ChameleonKeyCheckmark.disabled) {
          recovery.allKeysExists = false;
        }
      }
    }
  }

  @override
  Future<List<AutopwnPlusBlock>> dumpSelected(
    Set<int> sectors,
    void Function(int completed, int total) onProgress, {
    Future<bool> Function()? cardGuard,
  }) async {
    final communicator = recovery.appState.communicator!;
    final sorted = sectors.toList()..sort();
    final total = sorted.fold<int>(
      0,
      (sum, sector) => sum + mfClassicGetBlockCountBySector(sector),
    );
    _dumpedBlocks.clear();
    var completed = 0;
    recovery.setActivityProgress(
      'Card blocks',
      completed: completed,
      total: total,
    );

    for (final sector in sorted) {
      if (recovery.isCancelled) throw MifareClassicRecoveryCancelled();
      if (cardGuard != null && !await cardGuard()) {
        throw AutopwnPlusCardChanged();
      }
      final firstBlock = mfClassicGetFirstBlockCountBySector(sector);
      final blockCount = mfClassicGetBlockCountBySector(sector);
      final trailer = mfClassicGetSectorTrailerBlockBySector(sector);
      final keyTypes = <int>[
        if (recovery.getSectorKey(sector, 0).isNotEmpty) 0,
        if (recovery.getSectorKey(sector, 1).isNotEmpty) 1,
      ];
      List<Uint8List> batch = const [];
      if (keyTypes.isNotEmpty &&
          communicator.supportsCommandSync(ChameleonCommand.mf1ReadBlocks) !=
              false) {
        try {
          batch = await communicator.mf1ReadBlocks(
            firstBlock,
            blockCount,
            0x60 + keyTypes.first,
            recovery.getSectorKey(sector, keyTypes.first),
          );
        } catch (_) {
          batch = const [];
        }
      }

      for (var offset = 0; offset < blockCount; offset++) {
        if (recovery.isCancelled) throw MifareClassicRecoveryCancelled();
        final block = firstBlock + offset;
        Uint8List? data = offset < batch.length && batch[offset].length == 16
            ? Uint8List.fromList(batch[offset])
            : null;
        if (data == null) {
          for (final keyType in keyTypes) {
            try {
              final read = await communicator.mf1ReadBlock(
                block,
                0x60 + keyType,
                recovery.getSectorKey(sector, keyType),
              );
              if (read.length == 16) {
                data = Uint8List.fromList(read);
                break;
              }
            } catch (_) {}
          }
        }

        var syntheticKeys = false;
        if (data != null && block == trailer) {
          final keyA = recovery.getSectorKey(sector, 0);
          final keyB = recovery.getSectorKey(sector, 1);
          if (keyA.isNotEmpty) {
            data.setRange(0, 6, keyA);
            syntheticKeys = true;
          }
          if (keyB.isNotEmpty) {
            data.setRange(10, 16, keyB);
            syntheticKeys = true;
          }
        }
        if (data != null) recovery.cardData[block] = Uint8List.fromList(data);
        _dumpedBlocks.add(
          AutopwnPlusBlock(
            sector: sector,
            block: block,
            data: data,
            syntheticKeys: syntheticKeys,
          ),
        );
        completed++;
        recovery.setActivityProgress(
          'Card blocks',
          completed: completed,
          total: total,
        );
        onProgress(completed, total);
      }
    }
    return List.unmodifiable(_dumpedBlocks);
  }
}
