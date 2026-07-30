import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

enum AutopwnV2Phase {
  preflight,
  seeds,
  classify,
  backdoor,
  bootstrap,
  nested,
  staticNested,
  hardnested,
  verify,
  dump,
  complete,
  cancelled,
}

enum AutopwnV2Attack { nested, staticNested, hardnested }

enum AutopwnV2AttemptOutcome { found, noKey, incompatible }

enum AutopwnV2CandidateOrigin { selectedDictionary, defaultKey, backdoorKey }

class AutopwnV2Target {
  final int sector;
  final int keyType;

  const AutopwnV2Target(this.sector, this.keyType);

  String get label => 'sector ${sector + 1} key ${keyType == 0 ? 'A' : 'B'}';

  @override
  bool operator ==(Object other) =>
      other is AutopwnV2Target &&
      other.sector == sector &&
      other.keyType == keyType;

  @override
  int get hashCode => Object.hash(sector, keyType);
}

class AutopwnV2CardProfile {
  final NTLevel ntLevel;
  final bool hasBackdoor;

  const AutopwnV2CardProfile({
    required this.ntLevel,
    required this.hasBackdoor,
  });
}

class AutopwnV2CandidateEvidence {
  final Uint8List key;
  final Set<AutopwnV2CandidateOrigin> origins;
  final int support;

  AutopwnV2CandidateEvidence({
    required Uint8List key,
    required Set<AutopwnV2CandidateOrigin> origins,
    required this.support,
  }) : key = Uint8List.fromList(key),
       origins = Set.unmodifiable(origins);

  Map<String, Object> toJson() => {
    'keyHex': bytesToHex(key),
    'origins': origins.map((origin) => origin.name).toList(),
    'support': support,
  };
}

class _MutableCandidateEvidence {
  final Uint8List key;
  final int firstSeen;
  final Set<AutopwnV2CandidateOrigin> origins = {};
  int support = 0;

  _MutableCandidateEvidence(this.key, this.firstSeen);
}

class AutopwnV2CandidateLedger {
  final Map<String, _MutableCandidateEvidence> _entries = {};
  int _nextSequence = 0;

  void addAll(Iterable<Uint8List> keys, AutopwnV2CandidateOrigin origin) {
    for (final key in keys) {
      if (key.length != 6) continue;
      final hex = bytesToHex(key);
      final entry = _entries.putIfAbsent(
        hex,
        () =>
            _MutableCandidateEvidence(Uint8List.fromList(key), _nextSequence++),
      );
      entry.origins.add(origin);
      entry.support++;
    }
  }

  List<AutopwnV2CandidateEvidence> get ranked {
    int priority(_MutableCandidateEvidence entry) {
      if (entry.origins.contains(AutopwnV2CandidateOrigin.selectedDictionary)) {
        return 0;
      }
      if (entry.origins.contains(AutopwnV2CandidateOrigin.defaultKey)) {
        return 1;
      }
      return 2;
    }

    final values = _entries.values.toList()
      ..sort((left, right) {
        final byOrigin = priority(left).compareTo(priority(right));
        if (byOrigin != 0) return byOrigin;
        final bySupport = right.support.compareTo(left.support);
        if (bySupport != 0) return bySupport;
        return left.firstSeen.compareTo(right.firstSeen);
      });
    return List.unmodifiable([
      for (final entry in values)
        AutopwnV2CandidateEvidence(
          key: entry.key,
          origins: entry.origins,
          support: entry.support,
        ),
    ]);
  }
}

List<List<Uint8List>> buildAutopwnV2CandidateWaves({
  required List<Dictionary> dictionaries,
  bool includeDefaults = true,
  int waveSize = 64,
}) {
  if (waveSize < 1) throw ArgumentError.value(waveSize, 'waveSize');
  final ledger = AutopwnV2CandidateLedger();
  for (final dictionary in dictionaries) {
    ledger.addAll(dictionary.keys, AutopwnV2CandidateOrigin.selectedDictionary);
  }
  if (includeDefaults) {
    ledger.addAll(gMifareClassicKeys, AutopwnV2CandidateOrigin.defaultKey);
    ledger.addAll(
      gMifareClassicBackdoorKeys,
      AutopwnV2CandidateOrigin.backdoorKey,
    );
  }
  final candidates = ledger.ranked.map((entry) => entry.key).toList();
  return List<List<Uint8List>>.unmodifiable([
    for (var offset = 0; offset < candidates.length; offset += waveSize)
      List<Uint8List>.unmodifiable(
        candidates.sublist(
          offset,
          (offset + waveSize).clamp(0, candidates.length),
        ),
      ),
  ]);
}

class AutopwnV2Progress {
  final AutopwnV2Phase phase;
  final String operation;
  final double? value;
  final Duration elapsed;
  final int verifiedSlots;
  final int totalSlots;

  const AutopwnV2Progress({
    required this.phase,
    required this.operation,
    required this.value,
    required this.elapsed,
    required this.verifiedSlots,
    required this.totalSlots,
  });
}

class AutopwnV2VerifiedKey {
  final int sector;
  final int keyType;
  final Uint8List key;

  AutopwnV2VerifiedKey({
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

class AutopwnV2Block {
  final int sector;
  final int block;
  final Uint8List? data;
  final bool syntheticKeys;

  const AutopwnV2Block({
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

class AutopwnV2AttackRecord {
  final AutopwnV2Target target;
  final AutopwnV2Attack attack;
  final AutopwnV2AttemptOutcome outcome;
  final Duration elapsed;

  const AutopwnV2AttackRecord({
    required this.target,
    required this.attack,
    required this.outcome,
    required this.elapsed,
  });

  Map<String, Object> toJson() => {
    'sector': target.sector,
    'keyType': target.keyType == 0 ? 'A' : 'B',
    'attack': attack.name,
    'outcome': outcome.name,
    'elapsedMs': elapsed.inMilliseconds,
  };
}

class AutopwnV2Options {
  final List<Dictionary> dictionaries;
  final bool includeDefaults;
  final bool exhaustiveEvidence;
  final bool createPartialDump;

  const AutopwnV2Options({
    this.dictionaries = const [],
    this.includeDefaults = true,
    this.exhaustiveEvidence = true,
    this.createPartialDump = true,
  });
}

class AutopwnV2Result {
  final bool cancelled;
  final bool complete;
  final AutopwnV2CardProfile? profile;
  final int verifiedKeySlots;
  final int totalKeySlots;
  final List<AutopwnV2VerifiedKey> verifiedKeys;
  final List<AutopwnV2Block> blocks;
  final List<AutopwnV2CandidateEvidence> candidateEvidence;
  final List<AutopwnV2AttackRecord> attacks;
  final Map<AutopwnV2Phase, Duration> timings;
  final String error;

  const AutopwnV2Result({
    required this.cancelled,
    required this.complete,
    required this.profile,
    required this.verifiedKeySlots,
    required this.totalKeySlots,
    required this.verifiedKeys,
    required this.blocks,
    required this.candidateEvidence,
    required this.attacks,
    required this.timings,
    required this.error,
  });

  List<Uint8List> get keys =>
      verifiedKeys.map((entry) => Uint8List.fromList(entry.key)).toList();

  Map<String, Object?> toJson() => {
    'format': 'chameleon-autopwn-v2',
    'version': 1,
    'cancelled': cancelled,
    'complete': complete,
    'profile': profile == null
        ? null
        : {
            'ntLevel': profile!.ntLevel.name,
            'hasBackdoor': profile!.hasBackdoor,
          },
    'verifiedKeySlots': verifiedKeySlots,
    'totalKeySlots': totalKeySlots,
    'verifiedKeys': verifiedKeys.map((entry) => entry.toJson()).toList(),
    'candidateEvidence': candidateEvidence
        .map((entry) => entry.toJson())
        .toList(),
    'attacks': attacks.map((entry) => entry.toJson()).toList(),
    'timingsMs': {
      for (final entry in timings.entries)
        entry.key.name: entry.value.inMilliseconds,
    },
    'error': error,
    'blocks': blocks.map((block) => block.toJson()).toList(),
  };
}

class AutopwnV2CardChanged implements Exception {
  @override
  String toString() =>
      'The card changed or left the antenna. Autopwn v2 discarded the mixed result.';
}

abstract interface class AutopwnV2RecoveryPort {
  int get sectorCount;
  bool get isCancelled;
  String get error;
  List<AutopwnV2Block> get dumpedBlocks;

  void cancel();
  Future<void> prepare({required bool exhaustiveEvidence});
  Future<int> reverifyKnownKeys();
  Future<AutopwnV2CardProfile> classify();
  List<AutopwnV2Target> unresolvedTargets();
  int get verifiedSlots;
  List<AutopwnV2VerifiedKey> get verifiedKeys;
  Future<bool> checkTarget(AutopwnV2Target target, List<Uint8List> candidates);
  Future<bool> recoverBackdoor();
  Future<bool> bootstrapDarkside();
  Future<AutopwnV2AttemptOutcome> recoverTarget(
    AutopwnV2Target target,
    AutopwnV2Attack attack,
  );
  Future<int> verifyRecoveredKeys();
  Future<List<AutopwnV2Block>> dump(
    void Function(int completed, int total) onProgress, {
    Future<bool> Function()? cardGuard,
  });
}

class AutopwnV2Runner {
  const AutopwnV2Runner();

  Future<AutopwnV2Result> run({
    required AutopwnV2RecoveryPort recovery,
    required AutopwnV2Options options,
    void Function(AutopwnV2Progress progress)? onProgress,
    Future<bool> Function()? cardGuard,
  }) async {
    final total = Stopwatch()..start();
    final timings = <AutopwnV2Phase, Duration>{};
    final attacks = <AutopwnV2AttackRecord>[];
    final ledger = AutopwnV2CandidateLedger();
    AutopwnV2CardProfile? profile;
    var blocks = <AutopwnV2Block>[];
    var note = '';

    void report(AutopwnV2Phase phase, String operation, [double? value]) {
      onProgress?.call(
        AutopwnV2Progress(
          phase: phase,
          operation: operation,
          value: value,
          elapsed: total.elapsed,
          verifiedSlots: recovery.verifiedSlots,
          totalSlots: recovery.sectorCount * 2,
        ),
      );
    }

    Future<void> ensureCard() async {
      if (cardGuard != null && !await cardGuard()) {
        throw AutopwnV2CardChanged();
      }
    }

    void stopIfCancelled() {
      if (recovery.isCancelled) throw MifareClassicRecoveryCancelled();
    }

    Future<T> timed<T>(
      AutopwnV2Phase phase,
      Future<T> Function() action,
    ) async {
      final watch = Stopwatch()..start();
      try {
        return await action();
      } finally {
        watch.stop();
        timings[phase] = (timings[phase] ?? Duration.zero) + watch.elapsed;
      }
    }

    try {
      report(
        AutopwnV2Phase.preflight,
        'Locking card identity and attack scope',
      );
      await ensureCard();
      await timed(
        AutopwnV2Phase.preflight,
        () => recovery.prepare(exhaustiveEvidence: options.exhaustiveEvidence),
      );
      stopIfCancelled();

      await timed(AutopwnV2Phase.seeds, () async {
        report(AutopwnV2Phase.seeds, 'Re-verifying recovered seed keys');
        await recovery.reverifyKnownKeys();
        stopIfCancelled();

        for (final dictionary in options.dictionaries) {
          ledger.addAll(
            dictionary.keys,
            AutopwnV2CandidateOrigin.selectedDictionary,
          );
        }
        if (options.includeDefaults) {
          ledger.addAll(
            gMifareClassicKeys,
            AutopwnV2CandidateOrigin.defaultKey,
          );
          ledger.addAll(
            gMifareClassicBackdoorKeys,
            AutopwnV2CandidateOrigin.backdoorKey,
          );
        }
        final ranked = ledger.ranked;
        const waveSize = 64;
        final waves = [
          for (var offset = 0; offset < ranked.length; offset += waveSize)
            ranked
                .sublist(offset, (offset + waveSize).clamp(0, ranked.length))
                .map((entry) => entry.key)
                .toList(),
        ];
        for (var waveIndex = 0; waveIndex < waves.length; waveIndex++) {
          final targets = recovery.unresolvedTargets();
          if (targets.isEmpty) break;
          for (
            var targetIndex = 0;
            targetIndex < targets.length;
            targetIndex++
          ) {
            stopIfCancelled();
            final target = targets[targetIndex];
            if (!recovery.unresolvedTargets().contains(target)) continue;
            await ensureCard();
            report(
              AutopwnV2Phase.seeds,
              'Candidate wave ${waveIndex + 1}/${waves.length}: ${target.label}',
              (waveIndex + (targetIndex + 1) / targets.length) /
                  (waves.isEmpty ? 1 : waves.length),
            );
            await recovery.checkTarget(target, waves[waveIndex]);
          }
        }
      });

      await ensureCard();
      final classified = await timed(AutopwnV2Phase.classify, () async {
        report(
          AutopwnV2Phase.classify,
          'Probing nonce generator and factory backdoor',
        );
        return recovery.classify();
      });
      profile = classified;
      stopIfCancelled();

      if (classified.hasBackdoor && recovery.unresolvedTargets().isNotEmpty) {
        await timed(AutopwnV2Phase.backdoor, () async {
          await ensureCard();
          report(
            AutopwnV2Phase.backdoor,
            'Recovering and verifying factory-backdoor candidates',
          );
          await recovery.recoverBackdoor();
          stopIfCancelled();
        });
      }

      if (recovery.verifiedSlots == 0 &&
          recovery.unresolvedTargets().isNotEmpty &&
          const {NTLevel.weak, NTLevel.unknown}.contains(classified.ntLevel)) {
        await timed(AutopwnV2Phase.bootstrap, () async {
          await ensureCard();
          report(
            AutopwnV2Phase.bootstrap,
            'Bootstrapping a verified key with Darkside',
          );
          await recovery.bootstrapDarkside();
          stopIfCancelled();
        });
      }

      if (recovery.verifiedSlots == 0 &&
          recovery.unresolvedTargets().isNotEmpty) {
        note = 'No verified bootstrap key is available for nested recovery.';
      } else {
        var staticCompatible = true;
        final attackPlan = switch (classified.ntLevel) {
          NTLevel.weak => const [
            AutopwnV2Attack.nested,
            AutopwnV2Attack.staticNested,
          ],
          NTLevel.static => const [AutopwnV2Attack.staticNested],
          NTLevel.hard => const [AutopwnV2Attack.hardnested],
          NTLevel.backdoor => const <AutopwnV2Attack>[],
          NTLevel.unknown => const [
            AutopwnV2Attack.nested,
            AutopwnV2Attack.staticNested,
            AutopwnV2Attack.hardnested,
          ],
        };
        for (final attack in attackPlan) {
          if (attack == AutopwnV2Attack.staticNested && !staticCompatible) {
            continue;
          }
          final targets = recovery.unresolvedTargets();
          for (var index = 0; index < targets.length; index++) {
            stopIfCancelled();
            final target = targets[index];
            if (!recovery.unresolvedTargets().contains(target)) continue;
            await ensureCard();
            final phase = switch (attack) {
              AutopwnV2Attack.nested => AutopwnV2Phase.nested,
              AutopwnV2Attack.staticNested => AutopwnV2Phase.staticNested,
              AutopwnV2Attack.hardnested => AutopwnV2Phase.hardnested,
            };
            report(
              phase,
              '${attack.name}: ${target.label}',
              targets.isEmpty ? 1 : index / targets.length,
            );
            final watch = Stopwatch()..start();
            final outcome = await timed(
              phase,
              () => recovery.recoverTarget(target, attack),
            );
            watch.stop();
            attacks.add(
              AutopwnV2AttackRecord(
                target: target,
                attack: attack,
                outcome: outcome,
                elapsed: watch.elapsed,
              ),
            );
            stopIfCancelled();
            if (outcome == AutopwnV2AttemptOutcome.incompatible &&
                attack == AutopwnV2Attack.staticNested) {
              staticCompatible = false;
              break;
            }
          }
        }
      }

      await ensureCard();
      await timed(AutopwnV2Phase.verify, () async {
        report(
          AutopwnV2Phase.verify,
          'Authenticating every recovered key on-card',
        );
        await recovery.verifyRecoveredKeys();
        stopIfCancelled();
      });
      await ensureCard();

      if (options.createPartialDump) {
        await timed(AutopwnV2Phase.dump, () async {
          report(AutopwnV2Phase.dump, 'Reading every accessible block', 0);
          blocks = await recovery.dump((completed, count) {
            report(
              AutopwnV2Phase.dump,
              'Reading lossless partial dump',
              count == 0 ? 1 : completed / count,
            );
          }, cardGuard: cardGuard);
          stopIfCancelled();
        });
        await ensureCard();
      }
    } on MifareClassicRecoveryCancelled {
      recovery.cancel();
      blocks = recovery.dumpedBlocks;
    }

    total.stop();
    final cancelled = recovery.isCancelled;
    final complete = !cancelled && recovery.unresolvedTargets().isEmpty;
    report(
      cancelled ? AutopwnV2Phase.cancelled : AutopwnV2Phase.complete,
      cancelled
          ? 'Stopped after the active device or solver operation'
          : complete
          ? 'Autopwn v2 completed and verified every key slot'
          : 'Autopwn v2 completed with unresolved key slots',
      1,
    );
    return AutopwnV2Result(
      cancelled: cancelled,
      complete: complete,
      profile: profile,
      verifiedKeySlots: recovery.verifiedSlots,
      totalKeySlots: recovery.sectorCount * 2,
      verifiedKeys: List.unmodifiable(recovery.verifiedKeys),
      blocks: List.unmodifiable(blocks),
      candidateEvidence: ledger.ranked,
      attacks: List.unmodifiable(attacks),
      timings: Map.unmodifiable(timings),
      error: complete
          ? ''
          : recovery.error.isNotEmpty
          ? recovery.error
          : note,
    );
  }
}

class MifareClassicAutopwnV2Port implements AutopwnV2RecoveryPort {
  final MifareClassicRecovery recovery;
  final NTLevel? hintedNtLevel;
  final bool? hintedBackdoor;
  final List<AutopwnV2Block> _dumpedBlocks = [];

  MifareClassicAutopwnV2Port(
    this.recovery, {
    this.hintedNtLevel,
    this.hintedBackdoor,
  });

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
  List<AutopwnV2Block> get dumpedBlocks => List.unmodifiable(_dumpedBlocks);

  @override
  void cancel() => recovery.cancel();

  @override
  Future<void> prepare({required bool exhaustiveEvidence}) async {
    recovery.clearActivityProgress();
    recovery.error = '';
    recovery.state = '';
    recovery.exhaustiveRecovery = exhaustiveEvidence;
    recovery.keyCheckProgress = null;
    recovery.hardnestedProgress = null;
    _dumpedBlocks.clear();
    for (var sector = 0; sector < sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        final index = keyType == 0 ? sector : sector + 40;
        if (recovery.checkMarks[index] != ChameleonKeyCheckmark.found ||
            recovery.validKeys[index].length != 6) {
          recovery.checkMarks[index] = ChameleonKeyCheckmark.none;
          recovery.validKeys[index] = Uint8List(0);
        }
      }
    }
    _recalculateComplete();
    recovery.update();
  }

  @override
  Future<int> reverifyKnownKeys() async {
    final seeds = verifiedKeys;
    for (final seed in seeds) {
      final index = seed.keyType == 0 ? seed.sector : seed.sector + 40;
      recovery.checkMarks[index] = ChameleonKeyCheckmark.none;
      recovery.validKeys[index] = Uint8List(0);
    }
    recovery.setActivityProgress(
      'Seed key verification',
      completed: 0,
      total: seeds.length,
    );
    for (var seedIndex = 0; seedIndex < seeds.length; seedIndex++) {
      final seed = seeds[seedIndex];
      if (recovery.isCancelled) throw MifareClassicRecoveryCancelled();
      if (await recovery.appState.communicator!.mf1Auth(
        mfClassicGetSectorTrailerBlockBySector(seed.sector),
        0x60 + seed.keyType,
        seed.key,
      )) {
        recovery.setKeyAsFound(seed.sector, seed.keyType, seed.key);
        await recovery.recheckKey(seed.key, seed.sector);
      }
      recovery.setActivityProgress(
        'Seed key verification',
        completed: seedIndex + 1,
        total: seeds.length,
      );
    }
    _recalculateComplete();
    recovery.update();
    return verifiedSlots;
  }

  @override
  Future<AutopwnV2CardProfile> classify() async {
    var ntLevel = hintedNtLevel ?? NTLevel.unknown;
    var hasBackdoor = hintedBackdoor ?? false;
    try {
      ntLevel = await recovery.appState.communicator!.getMf1NTLevel();
    } catch (_) {}
    try {
      hasBackdoor = await mfClassicHasBackdoor(recovery.appState.communicator!);
    } catch (_) {}
    return AutopwnV2CardProfile(ntLevel: ntLevel, hasBackdoor: hasBackdoor);
  }

  @override
  List<AutopwnV2Target> unresolvedTargets() => [
    for (var sector = 0; sector < sectorCount; sector++)
      for (var keyType = 0; keyType < 2; keyType++)
        if (recovery.getSectorState(sector, keyType) !=
            ChameleonKeyCheckmark.found)
          AutopwnV2Target(sector, keyType),
  ];

  @override
  int get verifiedSlots => sectorCount * 2 - unresolvedTargets().length;

  @override
  List<AutopwnV2VerifiedKey> get verifiedKeys => [
    for (var sector = 0; sector < sectorCount; sector++)
      for (var keyType = 0; keyType < 2; keyType++)
        if (recovery.getSectorState(sector, keyType) ==
                ChameleonKeyCheckmark.found &&
            recovery.getSectorKey(sector, keyType).length == 6)
          AutopwnV2VerifiedKey(
            sector: sector,
            keyType: keyType,
            key: recovery.getSectorKey(sector, keyType),
          ),
  ];

  @override
  Future<bool> checkTarget(
    AutopwnV2Target target,
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
  Future<bool> recoverBackdoor() async {
    final found = await recovery.recoverBackdoor();
    _recalculateComplete();
    return found;
  }

  @override
  Future<bool> bootstrapDarkside() async {
    final found = await recovery.recoverDarkside();
    _recalculateComplete();
    return found;
  }

  (Uint8List, int, int)? _knownReference() {
    for (var sector = 0; sector < sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        final key = recovery.getSectorKey(sector, keyType);
        if (recovery.getSectorState(sector, keyType) ==
                ChameleonKeyCheckmark.found &&
            key.length == 6) {
          return (key, sector, keyType);
        }
      }
    }
    return null;
  }

  @override
  Future<AutopwnV2AttemptOutcome> recoverTarget(
    AutopwnV2Target target,
    AutopwnV2Attack attack,
  ) async {
    if (!unresolvedTargets().contains(target)) {
      return AutopwnV2AttemptOutcome.found;
    }
    final reference = _knownReference();
    if (reference == null) return AutopwnV2AttemptOutcome.noKey;
    final (key, sector, keyType) = reference;
    final outcome = switch (attack) {
      AutopwnV2Attack.nested =>
        await recovery.recoverNestedSingle(
              key,
              sector,
              keyType,
              target.sector,
              target.keyType,
            )
            ? AutopwnV2AttemptOutcome.found
            : AutopwnV2AttemptOutcome.noKey,
      AutopwnV2Attack.staticNested => switch (await recovery
          .recoverStaticNestedSingleDetailed(
            key,
            sector,
            keyType,
            target.sector,
            target.keyType,
          )) {
        StaticNestedAttemptResult.found => AutopwnV2AttemptOutcome.found,
        StaticNestedAttemptResult.noKey => AutopwnV2AttemptOutcome.noKey,
        StaticNestedAttemptResult.incompatible =>
          AutopwnV2AttemptOutcome.incompatible,
      },
      AutopwnV2Attack.hardnested =>
        await recovery.recoverHardnestedSingle(
              key,
              sector,
              keyType,
              target.sector,
              target.keyType,
            )
            ? AutopwnV2AttemptOutcome.found
            : AutopwnV2AttemptOutcome.noKey,
    };
    _recalculateComplete();
    return outcome;
  }

  @override
  Future<int> verifyRecoveredKeys() async {
    final entries = verifiedKeys;
    recovery.setActivityProgress(
      'Recovered key verification',
      completed: 0,
      total: entries.length,
    );
    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      final entry = entries[entryIndex];
      if (recovery.isCancelled) throw MifareClassicRecoveryCancelled();
      final valid = await recovery.appState.communicator!.mf1Auth(
        mfClassicGetSectorTrailerBlockBySector(entry.sector),
        0x60 + entry.keyType,
        entry.key,
      );
      if (!valid) {
        final index = entry.keyType == 0 ? entry.sector : entry.sector + 40;
        recovery.checkMarks[index] = ChameleonKeyCheckmark.none;
        recovery.validKeys[index] = Uint8List(0);
      }
      recovery.setActivityProgress(
        'Recovered key verification',
        completed: entryIndex + 1,
        total: entries.length,
      );
    }
    _recalculateComplete();
    recovery.update();
    return verifiedSlots;
  }

  void _recalculateComplete() {
    recovery.allKeysExists = unresolvedTargets().isEmpty;
  }

  @override
  Future<List<AutopwnV2Block>> dump(
    void Function(int completed, int total) onProgress, {
    Future<bool> Function()? cardGuard,
  }) async {
    final communicator = recovery.appState.communicator!;
    final total = List.generate(sectorCount, (sector) => sector).fold<int>(
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

    for (var sector = 0; sector < sectorCount; sector++) {
      if (recovery.isCancelled) throw MifareClassicRecoveryCancelled();
      if (cardGuard != null && !await cardGuard()) {
        throw AutopwnV2CardChanged();
      }
      final firstBlock = mfClassicGetFirstBlockCountBySector(sector);
      final blockCount = mfClassicGetBlockCountBySector(sector);
      final trailer = mfClassicGetSectorTrailerBlockBySector(sector);
      final keyTypes = <int>[
        if (recovery.getSectorKey(sector, 0).length == 6) 0,
        if (recovery.getSectorKey(sector, 1).length == 6) 1,
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
        } catch (_) {}
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
              final value = await communicator.mf1ReadBlock(
                block,
                0x60 + keyType,
                recovery.getSectorKey(sector, keyType),
              );
              if (value.length == 16) {
                data = Uint8List.fromList(value);
                break;
              }
            } catch (_) {}
          }
        }

        var syntheticKeys = false;
        if (data != null && block == trailer) {
          final keyA = recovery.getSectorKey(sector, 0);
          final keyB = recovery.getSectorKey(sector, 1);
          if (keyA.length == 6) {
            data.setRange(0, 6, keyA);
            syntheticKeys = true;
          }
          if (keyB.length == 6) {
            data.setRange(10, 16, keyB);
            syntheticKeys = true;
          }
        }
        if (data != null) recovery.cardData[block] = Uint8List.fromList(data);
        _dumpedBlocks.add(
          AutopwnV2Block(
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
