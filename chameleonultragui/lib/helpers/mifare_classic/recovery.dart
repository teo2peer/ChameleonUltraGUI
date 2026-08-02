import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/candidate_priority.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

extension PartitionList<E> on List<E> {
  List<List<E>> partition(int size) {
    assert(size > 0);
    final out = <List<E>>[];
    for (var i = 0; i < length; i += size) {
      final end = i + size < length ? i + size : length;
      out.add(sublist(i, end));
    }
    return out;
  }
}

enum ChameleonKeyCheckmark { none, found, checking, disabled }

enum AutopwnPhase {
  scan,
  dictionary,
  backdoor,
  darkside,
  nested,
  staticNested,
  hardnested,
  dump,
}

enum AutopwnPhaseStatus { pending, active, completed, skipped, failed }

enum StaticNestedAttemptResult { found, noKey, incompatible }

class AutopwnPhaseState {
  AutopwnPhaseStatus status = AutopwnPhaseStatus.pending;
  String detail = '';
  double progress = 0;
  DateTime? startedAt;
  DateTime? endedAt;

  Duration elapsed(DateTime now) {
    if (startedAt == null) return Duration.zero;
    return (endedAt ?? now).difference(startedAt!);
  }
}

class AutopwnRunProgress {
  AutopwnRunProgress({required this.exhaustive})
    : startedAt = DateTime.now(),
      phases = {
        for (final phase in AutopwnPhase.values) phase: AutopwnPhaseState(),
      };

  final bool exhaustive;
  final DateTime startedAt;
  final Map<AutopwnPhase, AutopwnPhaseState> phases;
  DateTime? endedAt;

  AutopwnPhaseState phase(AutopwnPhase phase) => phases[phase]!;

  void start(AutopwnPhase phase, String detail, {double progress = 0}) {
    final value = this.phase(phase);
    value.status = AutopwnPhaseStatus.active;
    value.detail = detail;
    value.progress = progress.clamp(0, 1);
    value.startedAt ??= DateTime.now();
    value.endedAt = null;
  }

  void update(AutopwnPhase phase, String detail, {double? progress}) {
    final value = this.phase(phase);
    if (value.status == AutopwnPhaseStatus.pending) {
      start(phase, detail, progress: progress ?? 0);
      return;
    }
    value.detail = detail;
    if (progress != null) {
      value.progress = progress.clamp(value.progress, 1);
    }
  }

  void complete(AutopwnPhase phase, String detail) {
    final value = this.phase(phase);
    value.status = AutopwnPhaseStatus.completed;
    value.detail = detail;
    value.progress = 1;
    value.startedAt ??= DateTime.now();
    value.endedAt = DateTime.now();
  }

  void skip(AutopwnPhase phase, String detail) {
    final value = this.phase(phase);
    if (value.status != AutopwnPhaseStatus.pending) return;
    value.status = AutopwnPhaseStatus.skipped;
    value.detail = detail;
    value.progress = 1;
    value.endedAt = DateTime.now();
  }

  void defer(AutopwnPhase phase, String detail) {
    final value = this.phase(phase);
    value.status = AutopwnPhaseStatus.pending;
    value.detail = detail;
    value.progress = 0;
    value.startedAt = null;
    value.endedAt = null;
  }

  void fail(AutopwnPhase phase, String detail) {
    final value = this.phase(phase);
    value.status = AutopwnPhaseStatus.failed;
    value.detail = detail;
    value.startedAt ??= DateTime.now();
    value.endedAt = DateTime.now();
  }

  void finish() {
    final now = DateTime.now();
    for (final phase in phases.values) {
      if (phase.status == AutopwnPhaseStatus.pending) {
        phase.status = AutopwnPhaseStatus.skipped;
        phase.detail = phase.detail.isEmpty ? 'Not reached' : phase.detail;
        phase.progress = 1;
        phase.endedAt = now;
      } else if (phase.status == AutopwnPhaseStatus.active) {
        phase.status = AutopwnPhaseStatus.failed;
        phase.detail = phase.detail.isEmpty
            ? 'Stopped before completion'
            : 'Stopped before completion: ${phase.detail}';
        phase.startedAt ??= now;
        phase.endedAt = now;
      }
    }
    endedAt = now;
  }

  void failCurrent(String detail) {
    for (final phase in AutopwnPhase.values) {
      if (this.phase(phase).status == AutopwnPhaseStatus.active) {
        fail(phase, detail);
        return;
      }
    }
    for (final phase in AutopwnPhase.values) {
      if (this.phase(phase).status == AutopwnPhaseStatus.pending) {
        fail(phase, detail);
        return;
      }
    }
  }

  double get overallProgress {
    final total = phases.values.fold<double>(0, (sum, phase) {
      return sum +
          switch (phase.status) {
            AutopwnPhaseStatus.completed || AutopwnPhaseStatus.skipped => 1,
            _ => phase.progress,
          };
    });
    return total / phases.length;
  }

  Duration elapsed(DateTime now) => (endedAt ?? now).difference(startedAt);
}

class MifareClassicRecoveryCancelled implements Exception {}

class MifareClassicRecoveryActivity {
  const MifareClassicRecoveryActivity({
    required this.label,
    required this.completed,
    required this.total,
    this.startedAt,
    this.unit = 'items',
  });

  final String label;
  final int completed;
  final int total;
  final DateTime? startedAt;
  final String unit;

  double get progress => total == 0 ? 0 : (completed / total).clamp(0, 1);

  double? itemsPerSecond(DateTime now) {
    final started = startedAt;
    if (started == null || completed == 0) return null;
    final elapsed = now.difference(started);
    if (elapsed <= Duration.zero) return null;
    return completed / elapsed.inMicroseconds * Duration.microsecondsPerSecond;
  }

  Duration? estimatedRemaining(DateTime now) {
    final rate = itemsPerSecond(now);
    if (rate == null || rate <= 0 || completed >= total) return null;
    return Duration(
      microseconds:
          ((total - completed) / rate * Duration.microsecondsPerSecond).round(),
    );
  }
}

class MifareClassicRecovery {
  late ChameleonGUIState appState;
  late AppLocalizations localizations;
  String error;
  String state;
  bool allKeysExists;
  List<Dictionary> dictionaries;
  Dictionary? selectedDictionary;
  List<ChameleonKeyCheckmark> checkMarks;
  List<Uint8List> validKeys;
  List<Uint8List> cardData;
  double dumpProgress;
  double? hardnestedProgress;
  double? keyCheckProgress;
  MifareClassicRecoveryActivity? activityProgress;
  DateTime? _activityStartedAt;
  String? cardUid;
  CardData? cardIdentity;
  final Map<String, Set<int>> _failedCandidateSlots = {};
  void Function() update;
  MifareClassicType mifareClassicType;
  bool isMifareClassicEV1;
  bool exhaustiveRecovery = false;
  AutopwnRunProgress? autopwnProgress;
  bool _cancelled = false;

  MifareClassicRecovery({
    required this.appState,
    required this.update,
    required this.localizations,
    this.error = '',
    this.state = '',
    this.allKeysExists = false,
    this.dictionaries = const [],
    this.dumpProgress = 0,
    this.selectedDictionary,
    this.mifareClassicType = MifareClassicType.none,
    this.isMifareClassicEV1 = false,
    this.cardUid,
    this.cardIdentity,
    List<ChameleonKeyCheckmark>? checkMarks,
    List<Uint8List>? validKeys,
    List<Uint8List>? cardData,
  }) : checkMarks =
           checkMarks ?? List.generate(80, (_) => ChameleonKeyCheckmark.none),
       validKeys = validKeys ?? List.generate(80, (_) => Uint8List(0)),
       cardData = cardData ?? List.generate(256, (_) => Uint8List(0)) {
    initializeEV1();
  }

  void cancel() {
    _cancelled = true;
  }

  bool get isCancelled => _cancelled;

  void _throwIfCancelled() {
    if (_cancelled) throw MifareClassicRecoveryCancelled();
  }

  void _startPhase(AutopwnPhase phase, String detail, {double progress = 0}) {
    autopwnProgress?.start(phase, detail, progress: progress);
    update();
  }

  void _updatePhase(AutopwnPhase phase, String detail, {double? progress}) {
    autopwnProgress?.update(phase, detail, progress: progress);
    update();
  }

  void _completePhase(AutopwnPhase phase, String detail) {
    autopwnProgress?.complete(phase, detail);
    update();
  }

  void _completeActivePhase(AutopwnPhase phase, String detail) {
    final progress = autopwnProgress;
    if (progress?.phase(phase).status != AutopwnPhaseStatus.active) return;
    progress!.complete(phase, detail);
    update();
  }

  void _skipPendingPhase(AutopwnPhase phase, String detail) {
    autopwnProgress?.skip(phase, detail);
    update();
  }

  void _deferPhase(AutopwnPhase phase, String detail) {
    autopwnProgress?.defer(phase, detail);
    update();
  }

  void _updateActivityProgress(
    String label, {
    required int completed,
    required int total,
  }) {
    if (completed == 0 ||
        activityProgress?.label != label ||
        activityProgress?.total != total) {
      _activityStartedAt = DateTime.now();
    }
    activityProgress = MifareClassicRecoveryActivity(
      label: label,
      completed: completed,
      total: total,
      startedAt: _activityStartedAt,
      unit: switch (label) {
        'Key candidates' || 'Reused key checks' => 'keys',
        'Card blocks' => 'blocks',
        'Nested nonces' ||
        'Static Nested nonces' ||
        'Hardnested nonce coverage' => 'nonces',
        _ => 'items',
      },
    );
    update();
  }

  void setActivityProgress(
    String label, {
    required int completed,
    required int total,
  }) {
    _updateActivityProgress(label, completed: completed, total: total);
  }

  void clearActivityProgress() {
    activityProgress = null;
    _activityStartedAt = null;
    update();
  }

  String _nonceCaptureFingerprint(
    String attack, {
    required int knownBlock,
    required int knownKeyType,
    required int targetBlock,
    required int targetKeyType,
    required NTDistance distance,
    required NestedNonces nonces,
  }) =>
      '$attack|$knownBlock|$knownKeyType|$targetBlock|$targetKeyType|'
      '${distance.uid}|${distance.distance}|'
      '${nonces.nonces.map((nonce) => '${nonce.nt}:${nonce.ntEnc}:${nonce.parity}').join(',')}';

  bool _hasStoredNonceCapture(String fingerprint) {
    final uid = cardUid;
    return uid != null &&
        appState.sharedPreferencesProvider.hasMifareClassicNonceSample(
          uid,
          fingerprint,
        );
  }

  Future<void> _storeNonceCapture(String fingerprint) async {
    final uid = cardUid;
    if (uid == null) return;
    await appState.sharedPreferencesProvider.recordMifareClassicNonceSample(
      uid,
      fingerprint,
    );
  }

  List<Uint8List> _withoutRememberedFailedKeys(List<Uint8List> keys) {
    final uid = cardUid;
    if (uid == null) return keys;
    return [
      for (final key in keys)
        if (!appState.sharedPreferencesProvider.hasMifareClassicFailedKey(
          uid,
          bytesToHex(key),
        ))
          key,
    ];
  }

  Future<void> _rememberFailedKeyChecks(
    Iterable<Uint8List> keys,
    int keyType,
    int sector,
  ) async {
    final uid = cardUid;
    final preferences = appState.sharedPreferencesProvider;
    if (uid == null || !preferences.getMifareClassicNonceHistoryEnabled()) {
      return;
    }
    final slotCount =
        mfClassicGetSectorCount(mifareClassicType, isEV1: isMifareClassicEV1) *
        2;
    if (slotCount == 0) return;
    final slot = sector * 2 + keyType;
    for (final key in keys) {
      if (key.length != 6) continue;
      final failedSlots = _failedCandidateSlots.putIfAbsent(
        bytesToHex(key),
        () => <int>{},
      );
      if (!failedSlots.add(slot) || failedSlots.length != slotCount) continue;
      await preferences.recordMifareClassicFailedKey(uid, bytesToHex(key));
    }
  }

  // Reorder candidates so defaults and keys already verified on another sector
  // are tried first.
  List<Uint8List> _prioritiseCandidates(List<Uint8List> keys) {
    final likely = <String>{...gMifareClassicKeys.map(bytesToHex)};
    for (final k in validKeys) {
      if (k.isNotEmpty) likely.add(bytesToHex(k));
    }
    return prioritiseCandidates(keys, likely, minLength: 0);
  }

  Uint8List _maskForTargets(List<(int, int)> targets) {
    final mask = Uint8List.fromList(List.filled(10, 0xff));
    for (final (sector, keyType) in targets) {
      final slot = sector * 2 + keyType;
      mask[slot ~/ 8] &= ~(1 << (7 - slot % 8));
    }
    return mask;
  }

  Future<void> _verifyCardIdentity() async {
    final card = await appState.communicator!.scan14443aTag();
    _throwIfCancelled();
    if (card == null) {
      throw StateError('The card changed during MIFARE Classic recovery');
    }
    final expected = cardIdentity;
    if (expected == null) {
      final expectedUid = cardUid;
      if (expectedUid != null && bytesToHex(card.uid) != expectedUid) {
        throw StateError('The card changed during MIFARE Classic recovery');
      }
      cardUid ??= bytesToHex(card.uid);
      cardIdentity = CardData(
        uid: Uint8List.fromList(card.uid),
        sak: card.sak,
        atqa: Uint8List.fromList(card.atqa),
        ats: Uint8List.fromList(card.ats),
      );
      return;
    }
    if (bytesToHex(card.uid) != bytesToHex(expected.uid) ||
        card.sak != expected.sak ||
        bytesToHex(card.atqa) != bytesToHex(expected.atqa) ||
        bytesToHex(card.ats) != bytesToHex(expected.ats)) {
      throw StateError('The card changed during MIFARE Classic recovery');
    }
  }

  Future<int?> _checkKeysAcrossTargets(
    List<Uint8List> keys,
    List<(int, int)> targets, {
    String activityLabel = 'Key candidates',
  }) async {
    final communicator = appState.communicator!;
    if (targets.isEmpty || keys.isEmpty) return 0;
    if (communicator.supportsCommandSync(
          ChameleonCommand.mf1CheckKeysOfSectors,
        ) !=
        true) {
      return null;
    }

    keys = _prioritiseCandidates(keys);
    final isBle = appState.connector!.connectionType == ConnectionType.ble;
    final keyChunkSize = isBle ? 8 : 12;
    final attemptBudget = isBle ? 16 : 48;
    final totalAttempts = targets.length * keys.length;
    var completedAttempts = 0;
    var foundCount = 0;
    _updateActivityProgress(activityLabel, completed: 0, total: totalAttempts);
    await _verifyCardIdentity();

    for (final keyChunk in keys.partition(keyChunkSize)) {
      _throwIfCancelled();
      final unresolved = [
        for (final target in targets)
          if (getSectorState(target.$1, target.$2) ==
              ChameleonKeyCheckmark.none)
            target,
      ];
      if (unresolved.isEmpty) break;
      final targetChunkSize = (attemptBudget ~/ (keyChunk.length + 2))
          .clamp(1, unresolved.length)
          .toInt();
      for (final targetChunk in unresolved.partition(targetChunkSize)) {
        _throwIfCancelled();
        for (final (sector, keyType) in targetChunk) {
          setCheckingSector(sector, keyType);
        }
        final result = await communicator.mf1CheckKeysOfSectors(
          _maskForTargets(targetChunk),
          keyChunk,
        );
        _throwIfCancelled();
        if (result == null) {
          for (final (sector, keyType) in targetChunk) {
            setMissingSector(sector, keyType);
          }
          return null;
        }
        await _verifyCardIdentity();

        final requestedSlots = {
          for (final (sector, keyType) in targetChunk) sector * 2 + keyType,
        };
        final verified = <(int, int, Uint8List)>[];
        for (final entry in result.entries) {
          if (!requestedSlots.contains(entry.key) || entry.value.length != 6) {
            continue;
          }
          final sector = entry.key ~/ 2;
          final keyType = entry.key % 2;
          final trailer = mfClassicGetSectorTrailerBlockBySector(sector);
          if (await communicator.mf1Auth(
            trailer,
            0x60 + keyType,
            entry.value,
          )) {
            _throwIfCancelled();
            verified.add((sector, keyType, entry.value));
          }
        }
        if (verified.isNotEmpty) await _verifyCardIdentity();
        for (final (sector, keyType, key) in verified) {
          setKeyAsFound(sector, keyType, key);
          foundCount++;
        }
        for (final (sector, keyType) in targetChunk) {
          setMissingSector(sector, keyType);
        }
        completedAttempts += targetChunk.length * keyChunk.length;
        _updateActivityProgress(
          activityLabel,
          completed: completedAttempts.clamp(0, totalAttempts).toInt(),
          total: totalAttempts,
        );
      }
    }
    _updateActivityProgress(
      activityLabel,
      completed: totalAttempts,
      total: totalAttempts,
    );
    return foundCount;
  }

  Future<bool> checkKeysOnSector(
    List<Uint8List> keys,
    int keyType,
    int sector,
  ) async {
    _throwIfCancelled();
    keys = _prioritiseCandidates(keys);
    keys = _withoutRememberedFailedKeys(keys);
    state = localizations.checking_keys(keys.length);
    Uint8List? key;
    keyCheckProgress = null;
    // Keep each firmware auth batch short. Large batches can exceed the host
    // response timeout on some cards/read distances and make autopwn appear
    // stuck at "checking keys N" while firmware is still busy.
    int chunkSize = appState.connector!.connectionType == ConnectionType.ble
        ? 8
        : 12;

    if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
        getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
      _updateActivityProgress(
        'Key candidates',
        completed: 0,
        total: keys.length,
      );
      setCheckingSector(sector, keyType);
      int totalChunks = keys.partition(chunkSize).length;

      var chunkIndex = 0;
      var checkedCandidates = 0;
      for (var chunk in keys.partition(chunkSize)) {
        _throwIfCancelled();
        keyCheckProgress = totalChunks <= 1 ? null : chunkIndex / totalChunks;
        update();
        key = await appState.communicator!.mf1AuthMultipleKeys(
          mfClassicGetSectorTrailerBlockBySector(sector),
          0x60 + keyType,
          chunk,
        );
        _throwIfCancelled();
        chunkIndex++;
        checkedCandidates += chunk.length;
        _updateActivityProgress(
          'Key candidates',
          completed: checkedCandidates,
          total: keys.length,
        );
        if (key != null) {
          setKeyAsFound(sector, keyType, key);
          keyCheckProgress = null;
          if (keyType == 0) {
            await _tryReadableKeyB(sector, key);
          }
          await recheckKey(key, sector);
          return true;
        } else {
          await _rememberFailedKeyChecks(chunk, keyType, sector);
          if (totalChunks > 1) {
            keyCheckProgress = chunkIndex / totalChunks;
            update();
          }
        }
      }

      if (key == null) {
        setMissingSector(sector, keyType);
      }
    }

    setMissingSector(sector, keyType);
    keyCheckProgress = null;
    return false;
  }

  Future<bool> _tryReadableKeyB(int sector, Uint8List keyA) async {
    _throwIfCancelled();
    if (getSectorState(sector, 1) == ChameleonKeyCheckmark.found ||
        getSectorState(sector, 1) == ChameleonKeyCheckmark.disabled) {
      return false;
    }

    final trailerBlock = mfClassicGetSectorTrailerBlockBySector(sector);
    final block = await appState.communicator!.mf1ReadBlock(
      trailerBlock,
      0x60,
      keyA,
    );
    _throwIfCancelled();
    if (block.length != 16) {
      return false;
    }

    final keyB = block.sublist(10);
    if (bytesToHex(keyB) == bytesToHex(Uint8List(6))) {
      return false;
    }

    // Some access conditions expose bytes 10..15 as data, not as a usable Key B.
    // Confirm on-card before trusting or propagating it.
    if (!await appState.communicator!.mf1Auth(trailerBlock, 0x61, keyB)) {
      return false;
    }
    _throwIfCancelled();

    setKeyAsFound(sector, 1, keyB);
    await recheckKey(keyB, sector);
    return true;
  }

  Future<void> initialize() async {
    _throwIfCancelled();
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }
    _throwIfCancelled();

    var mifare = await appState.communicator!.detectMf1Support();
    _throwIfCancelled();

    if (mifare) {
      mifareClassicType = await mfClassicGetType(appState.communicator!);
    } else {
      appState.log!.e("Not Mifare Classic tag!");
    }

    isMifareClassicEV1 = await appState.communicator!.mf1Auth(
      0x45,
      0x61,
      gMifareClassicKeys[3],
    );
    _throwIfCancelled();
    initializeEV1();
  }

  Future<void> recheckKey(Uint8List key, int startingSector) async {
    _throwIfCancelled();
    // Scan ALL sectors (not just from startingSector): keys are frequently
    // reused across sectors, and a key found late is often the missing key of
    // an earlier, still-unresolved sector. Trying it there is one cheap auth
    // that can avoid an expensive nested/darkside attack. Only sectors still in
    // the `none` state are probed, so resolved sectors are skipped.
    final targets = <(int, int)>[
      for (
        var sector = 0;
        sector <
            mfClassicGetSectorCount(
              mifareClassicType,
              isEV1: isMifareClassicEV1,
            );
        sector++
      )
        for (var keyType = 0; keyType < 2; keyType++)
          if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none)
            (sector, keyType),
    ];
    if (targets.isEmpty) return;
    final bulkResult = await _checkKeysAcrossTargets(
      [key],
      targets,
      activityLabel: 'Reused key checks',
    );
    if (bulkResult != null) return;
    _updateActivityProgress(
      'Reused key checks',
      completed: 0,
      total: targets.length,
    );
    var checkedTargets = 0;
    for (final (sector, keyType) in targets) {
      _throwIfCancelled();
      state = localizations.checking_keys(1);
      appState.log!.d(
        "Checking found key ${bytesToHex(key)} on sector $sector, key type $keyType",
      );
      setCheckingSector(sector, keyType);

      if (await appState.communicator!.mf1Auth(
        mfClassicGetSectorTrailerBlockBySector(sector),
        0x60 + keyType,
        key,
      )) {
        _throwIfCancelled();
        setKeyAsFound(sector, keyType, key);
      } else {
        _throwIfCancelled();
        setMissingSector(sector, keyType);
      }

      checkedTargets++;
      _updateActivityProgress(
        'Reused key checks',
        completed: checkedTargets,
        total: targets.length,
      );
    }
  }

  void initializeEV1() {
    if (isMifareClassicEV1) {
      setKeyAsFound(16, 0, gMifareClassicKeys[4]); // MFC EV1 SIGNATURE 16 A
      setKeyAsFound(16, 1, gMifareClassicKeys[5]); // MFC EV1 SIGNATURE 16 B
      setKeyAsFound(17, 0, gMifareClassicKeys[6]); // MFC EV1 SIGNATURE 17 A
      setKeyAsFound(17, 1, gMifareClassicKeys[3]); // MFC EV1 SIGNATURE 17 B
    }
  }

  Future<void> checkKeys({bool skipDefaultDictionary = false}) async {
    _throwIfCancelled();
    _startPhase(
      AutopwnPhase.dictionary,
      exhaustiveRecovery
          ? "Checking selected keys before defaults"
          : "Checking dictionary and default keys",
    );
    initializeEV1();

    final seen = <String>{};
    final dictionaryKeys = <Uint8List>[];
    for (final k in selectedDictionary!.keys) {
      if (seen.add(bytesToHex(k))) dictionaryKeys.add(k);
    }

    final defaultAndKnownKeys = <Uint8List>[];
    if (!skipDefaultDictionary) {
      for (final k in gMifareClassicKeys) {
        if (seen.add(bytesToHex(k))) defaultAndKnownKeys.add(k);
      }
    }
    for (final k in validKeys) {
      if (k.isNotEmpty && seen.add(bytesToHex(k))) {
        defaultAndKnownKeys.add(k);
      }
    }

    final passes = exhaustiveRecovery
        ? [if (dictionaryKeys.isNotEmpty) dictionaryKeys, defaultAndKnownKeys]
        : [
            [...dictionaryKeys, ...defaultAndKnownKeys],
          ];

    final sectorCount = mfClassicGetSectorCount(
      mifareClassicType,
      isEV1: isMifareClassicEV1,
    );

    final totalChecks = passes.length * sectorCount * 2;
    var completedChecks = 0;
    for (var pass = 0; pass < passes.length; pass++) {
      final keyList = passes[pass];
      final targets = <(int, int)>[
        for (var sector = 0; sector < sectorCount; sector++)
          for (var keyType = 0; keyType < 2; keyType++)
            if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none)
              (sector, keyType),
      ];
      final bulkResult = await _checkKeysAcrossTargets(keyList, targets);
      if (bulkResult != null) {
        completedChecks += sectorCount * 2;
        _updatePhase(
          AutopwnPhase.dictionary,
          "Pass ${pass + 1}/${passes.length}: bounded multi-sector key scan",
          progress: totalChecks == 0 ? 1 : completedChecks / totalChecks,
        );
        continue;
      }
      for (var sector = 0; sector < sectorCount; sector++) {
        _throwIfCancelled();
        for (var keyType = 0; keyType < 2; keyType++) {
          _throwIfCancelled();
          _updatePhase(
            AutopwnPhase.dictionary,
            "Pass ${pass + 1}/${passes.length}: sector ${sector + 1}/$sectorCount key ${keyType == 0 ? 'A' : 'B'}",
            progress: totalChecks == 0 ? 1 : completedChecks / totalChecks,
          );
          await checkKeysOnSector(keyList, keyType, sector);
          completedChecks++;
        }
      }
    }

    // Key check part competed, checking found keys
    allKeysExists = true;
    for (var sector = 0; sector < sectorCount; sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        _throwIfCancelled();
        if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
          allKeysExists = false;
        }
      }
    }

    state = "";
    _completePhase(
      AutopwnPhase.dictionary,
      allKeysExists
          ? "All keys found in key passes"
          : "Key passes completed; recovery is required",
    );
    update();
  }

  // Standalone Darkside: recover sector 0 key B from a card with no known key
  // (weak-PRNG cards). Returns true if a key was found.
  Future<bool> recoverDarkside() async {
    _throwIfCancelled();
    state = localizations.checking_or_running_darkside;
    update();
    DarksideResult darkside;
    try {
      setCheckingSector(0, 1);
      darkside = await appState.communicator!.checkMf1Darkside();
      _throwIfCancelled();
    } catch (e) {
      if (e is MifareClassicRecoveryCancelled) rethrow;
      setMissingSector(0, 1);
      state = "";
      update();
      return false;
    }
    if (darkside != DarksideResult.vulnerable) {
      setMissingSector(0, 1);
      error = localizations.recovery_error_no_keys_darkside;
      state = "";
      update();
      return false;
    }
    var data = await appState.communicator!.getMf1Darkside(
      0x03,
      0x61,
      true,
      15,
    );
    _throwIfCancelled();
    var ds = DarksideDart(uid: data.uid, items: []);
    update();
    for (var tries = 0; tries < 5; tries++) {
      _throwIfCancelled();
      ds.items.add(
        DarksideItemDart(
          nt1: data.nt1,
          ks1: data.ks1,
          par: data.par,
          nr: data.nr,
          ar: data.ar,
        ),
      );
      var keys = await recovery.darkside(ds);
      _throwIfCancelled();
      if (keys.isNotEmpty &&
          await checkKeysOnSector(mfClassicConvertKeys(keys), 1, 0)) {
        state = "";
        update();
        return true;
      }
      data = await appState.communicator!.getMf1Darkside(0x03, 0x61, false, 15);
      _throwIfCancelled();
    }
    setMissingSector(0, 1);
    error = localizations.recovery_error_no_keys_darkside;
    state = "";
    update();
    return false;
  }

  Future<(bool, NTDistance?)> _recoverWeakNestedKey(
    int knownBlock,
    int knownKeyType,
    Uint8List knownKey,
    int targetBlock,
    int targetKeyType, {
    int attempts = 5,
    NTDistance? initialDistance,
    bool rankAcrossCaptures = false,
    String targetLabel = "target key",
    required Future<bool> Function(List<int> candidates) verifyCandidates,
  }) async {
    final evidence = <List<int>>[];
    final evidenceFingerprints = <String>[];
    final attemptedCandidates = <int>{};
    var distance = initialDistance;
    NTDistance? evidenceDistance;
    final totalNonces = attempts * 2;
    var collectedNonces = 0;
    _updateActivityProgress(
      'Nested nonces',
      completed: collectedNonces,
      total: totalNonces,
    );

    for (var attempt = 0; attempt < attempts; attempt++) {
      _throwIfCancelled();
      if (distance == null) {
        _updatePhase(
          AutopwnPhase.nested,
          "Nested: measuring distance for $targetLabel",
        );
        distance = await appState.communicator!.getMf1NTDistance(
          knownBlock,
          knownKeyType,
          knownKey,
        );
        _throwIfCancelled();
      }

      _updatePhase(
        AutopwnPhase.nested,
        "Nested: capture ${attempt + 1}/$attempts for $targetLabel",
      );
      final nonces = await appState.communicator!.getMf1NestedNonces(
        knownBlock,
        knownKeyType,
        knownKey,
        targetBlock,
        targetKeyType,
        level: NTLevel.weak,
      );
      _throwIfCancelled();
      collectedNonces += nonces.nonces.length;
      if (collectedNonces > totalNonces) collectedNonces = totalNonces;
      _updateActivityProgress(
        'Nested nonces',
        completed: collectedNonces,
        total: totalNonces,
      );
      if (nonces.nonces.length < 2) {
        distance = null;
        continue;
      }

      final fingerprint = _nonceCaptureFingerprint(
        'weak',
        knownBlock: knownBlock,
        knownKeyType: knownKeyType,
        targetBlock: targetBlock,
        targetKeyType: targetKeyType,
        distance: distance,
        nonces: nonces,
      );
      if (_hasStoredNonceCapture(fingerprint)) {
        _updatePhase(
          AutopwnPhase.nested,
          'Nested: skipping a stored nonce capture for $targetLabel',
        );
        distance = null;
        continue;
      }

      state = localizations.recovering_key("Nested");
      _updatePhase(
        AutopwnPhase.nested,
        "Nested: solving capture for $targetLabel",
      );
      update();
      final candidates = await recovery.nested(
        NestedDart(
          uid: distance.uid,
          distance: distance.distance,
          nt0: nonces.nonces[0].nt,
          nt0Enc: nonces.nonces[0].ntEnc,
          par0: nonces.nonces[0].parity,
          nt1: nonces.nonces[1].nt,
          nt1Enc: nonces.nonces[1].ntEnc,
          par1: nonces.nonces[1].parity,
        ),
      );
      _throwIfCancelled();

      if (candidates.isEmpty) {
        appState.log!.w("Nested sample ${attempt + 1} produced no candidates");
        distance = null;
        continue;
      }
      evidence.add(candidates);
      evidenceFingerprints.add(fingerprint);
      evidenceDistance = distance;
      if (rankAcrossCaptures) {
        appState.log!.d(
          "Nested sample ${attempt + 1}: collected ${candidates.length} candidates",
        );
        continue;
      }

      appState.log!.d(
        "Nested sample ${attempt + 1}: produced ${candidates.length} candidates",
      );
      final verificationCandidates = candidates
          .where((candidate) => !attemptedCandidates.contains(candidate))
          .toList();
      attemptedCandidates.addAll(verificationCandidates);
      if (verificationCandidates.isEmpty) {
        distance = null;
        continue;
      }
      _updatePhase(
        AutopwnPhase.nested,
        "Nested: checking ${verificationCandidates.length}/${candidates.length} candidates for $targetLabel",
      );

      final found = await verifyCandidates(verificationCandidates);
      await _storeNonceCapture(fingerprint);
      _throwIfCancelled();
      if (found) {
        _throwIfCancelled();
        return (true, distance);
      }
      _throwIfCancelled();
      distance = null;
    }

    if (rankAcrossCaptures && evidence.isNotEmpty) {
      final ranked = rankCandidatesBySupport(evidence);
      appState.log!.d(
        "Nested exhaustive ranking: checking ${ranked.length} unique candidates from ${evidence.length} captures",
      );
      _updatePhase(
        AutopwnPhase.nested,
        "Nested: checking ${ranked.length} ranked candidates for $targetLabel",
      );
      final found = await verifyCandidates(ranked);
      for (final fingerprint in evidenceFingerprints) {
        await _storeNonceCapture(fingerprint);
      }
      _throwIfCancelled();
      if (found) {
        _throwIfCancelled();
        return (true, evidenceDistance);
      }
      _throwIfCancelled();
    } else if (evidence.length >= 2) {
      final consensus = rankCandidateConsensus(
        evidence.map((candidates) => candidates.toSet()),
      );
      final verificationCandidates = consensus.candidates
          .where((candidate) => !attemptedCandidates.contains(candidate))
          .toList();
      if (verificationCandidates.isNotEmpty) {
        _updatePhase(
          AutopwnPhase.nested,
          "Nested: checking ${verificationCandidates.length} consensus candidates for $targetLabel",
        );
        if (await verifyCandidates(verificationCandidates)) {
          _throwIfCancelled();
          return (true, evidenceDistance);
        }
        _throwIfCancelled();
      }
    }

    appState.log!.w("Nested produced no valid key after $attempts captures");
    return (false, null);
  }

  Future<StaticNestedAttemptResult> _recoverStaticNestedKey(
    int knownBlock,
    int knownKeyType,
    Uint8List knownKey,
    int targetBlock,
    int targetKeyType, {
    NTDistance? initialDistance,
    String targetLabel = "target key",
    required Future<bool> Function(List<int> candidates) verifyCandidates,
  }) async {
    _updateActivityProgress('Static Nested nonces', completed: 0, total: 2);
    _updatePhase(
      AutopwnPhase.staticNested,
      "Static Nested: collecting nonces for $targetLabel",
    );
    final distance =
        initialDistance ??
        await appState.communicator!.getMf1NTDistance(
          knownBlock,
          knownKeyType,
          knownKey,
        );
    _throwIfCancelled();
    final nonces = await appState.communicator!.getMf1NestedNonces(
      knownBlock,
      knownKeyType,
      knownKey,
      targetBlock,
      targetKeyType,
      level: NTLevel.static,
    );
    _throwIfCancelled();
    _updateActivityProgress(
      'Static Nested nonces',
      completed: nonces.nonces.length > 2 ? 2 : nonces.nonces.length,
      total: 2,
    );
    if (nonces.nonces.length < 2) {
      return StaticNestedAttemptResult.noKey;
    }
    if (!const {0x01200145, 0x009080A2}.contains(nonces.nonces[0].nt)) {
      return StaticNestedAttemptResult.incompatible;
    }

    final fingerprint = _nonceCaptureFingerprint(
      'static',
      knownBlock: knownBlock,
      knownKeyType: knownKeyType,
      targetBlock: targetBlock,
      targetKeyType: targetKeyType,
      distance: distance,
      nonces: nonces,
    );
    if (_hasStoredNonceCapture(fingerprint)) {
      _updatePhase(
        AutopwnPhase.staticNested,
        'Static Nested: skipping a stored nonce capture for $targetLabel',
      );
      return StaticNestedAttemptResult.noKey;
    }

    state = localizations.recovering_key("Static Nested");
    _updatePhase(
      AutopwnPhase.staticNested,
      "Static Nested: solving candidates for $targetLabel",
    );
    update();
    final candidates = await recovery.staticNested(
      StaticNestedDart(
        uid: distance.uid,
        keyType: targetKeyType,
        nt0: nonces.nonces[0].nt,
        nt0Enc: nonces.nonces[0].ntEnc,
        nt1: nonces.nonces[1].nt,
        nt1Enc: nonces.nonces[1].ntEnc,
      ),
    );
    _throwIfCancelled();
    _updatePhase(
      AutopwnPhase.staticNested,
      "Static Nested: checking ${candidates.length} candidates for $targetLabel",
    );
    if (candidates.isEmpty) {
      return StaticNestedAttemptResult.noKey;
    }
    final found = await verifyCandidates(candidates);
    await _storeNonceCapture(fingerprint);
    _throwIfCancelled();
    return found
        ? StaticNestedAttemptResult.found
        : StaticNestedAttemptResult.noKey;
  }

  // Standalone weak-PRNG Nested: recover a target sector/keyType key from a
  // known key. Returns true if a key was found.
  Future<bool> recoverNestedSingle(
    Uint8List knownKey,
    int knownSector,
    int knownKeyType,
    int targetSector,
    int targetKeyType,
  ) async {
    _throwIfCancelled();
    int knownBlock = mfClassicGetSectorTrailerBlockBySector(knownSector);
    int targetBlock = mfClassicGetSectorTrailerBlockBySector(targetSector);
    state = localizations.collecting_nonces("Nested");
    setCheckingSector(targetSector, targetKeyType);
    update();
    try {
      final result = await _recoverWeakNestedKey(
        knownBlock,
        0x60 + knownKeyType,
        knownKey,
        targetBlock,
        0x60 + targetKeyType,
        rankAcrossCaptures: exhaustiveRecovery,
        targetLabel:
            "sector ${targetSector + 1} key ${targetKeyType == 0 ? 'A' : 'B'}",
        verifyCandidates: (keys) => checkKeysOnSector(
          mfClassicConvertKeys(keys),
          targetKeyType,
          targetSector,
        ),
      );
      if (result.$1) {
        state = "";
        update();
        return true;
      }
    } catch (e) {
      if (e is MifareClassicRecoveryCancelled) rethrow;
      error = e.toString();
    }
    setMissingSector(targetSector, targetKeyType);
    state = "";
    update();
    return false;
  }

  // Standalone Static-Nested: recover a target key from a known key on a
  // static-nonce card. Returns true if a key was found.
  Future<bool> recoverStaticNestedSingle(
    Uint8List knownKey,
    int knownSector,
    int knownKeyType,
    int targetSector,
    int targetKeyType,
  ) async =>
      await recoverStaticNestedSingleDetailed(
        knownKey,
        knownSector,
        knownKeyType,
        targetSector,
        targetKeyType,
      ) ==
      StaticNestedAttemptResult.found;

  Future<StaticNestedAttemptResult> recoverStaticNestedSingleDetailed(
    Uint8List knownKey,
    int knownSector,
    int knownKeyType,
    int targetSector,
    int targetKeyType,
  ) async {
    _throwIfCancelled();
    int knownBlock = mfClassicGetSectorTrailerBlockBySector(knownSector);
    int targetBlock = mfClassicGetSectorTrailerBlockBySector(targetSector);
    state = localizations.collecting_nonces("Static Nested");
    setCheckingSector(targetSector, targetKeyType);
    update();
    try {
      final result = await _recoverStaticNestedKey(
        knownBlock,
        0x60 + knownKeyType,
        knownKey,
        targetBlock,
        0x60 + targetKeyType,
        verifyCandidates: (keys) => checkKeysOnSector(
          mfClassicConvertKeys(keys),
          targetKeyType,
          targetSector,
        ),
      );
      if (result == StaticNestedAttemptResult.found) {
        state = "";
        update();
        return result;
      }
      if (result == StaticNestedAttemptResult.incompatible) {
        state = "";
        setMissingSector(targetSector, targetKeyType);
        update();
        return result;
      }
    } catch (e) {
      if (e is MifareClassicRecoveryCancelled) rethrow;
      error = e.toString();
    }
    setMissingSector(targetSector, targetKeyType);
    state = "";
    update();
    return StaticNestedAttemptResult.noKey;
  }

  // Standalone Hardnested: recover a target key from a known key on a
  // hard-PRNG card (e.g. EV1). Returns true if a key was found.
  Future<bool> recoverHardnestedSingle(
    Uint8List knownKey,
    int knownSector,
    int knownKeyType,
    int targetSector,
    int targetKeyType,
  ) async {
    _throwIfCancelled();
    int knownBlock = mfClassicGetSectorTrailerBlockBySector(knownSector);
    int targetBlock = mfClassicGetSectorTrailerBlockBySector(targetSector);
    state = localizations.collecting_nonces("Hard Nested");
    setCheckingSector(targetSector, targetKeyType);
    hardnestedProgress = 0;
    update();
    try {
      NTDistance distance = await appState.communicator!.getMf1NTDistance(
        knownBlock,
        0x60 + knownKeyType,
        knownKey,
      );
      _throwIfCancelled();
      var result = await collectHardnestedNonces(
        knownBlock,
        0x60 + knownKeyType,
        knownKey,
        targetBlock,
        0x60 + targetKeyType,
      );
      _throwIfCancelled();
      if (result is String) {
        error = result;
        setMissingSector(targetSector, targetKeyType);
        hardnestedProgress = null;
        state = "";
        update();
        return false;
      }
      NestedNonces nonces = result as NestedNonces;
      var nested = HardNestedDart(nonces: nonces.getHardNested(distance.uid));
      var keys = await recovery.hardNested(nested);
      _throwIfCancelled();
      hardnestedProgress = null;
      if (keys.isNotEmpty &&
          await checkKeysOnSector(
            mfClassicConvertKeys(keys),
            targetKeyType,
            targetSector,
          )) {
        state = "";
        update();
        return true;
      }
    } catch (e) {
      if (e is MifareClassicRecoveryCancelled) rethrow;
      error = e.toString();
    }
    hardnestedProgress = null;
    setMissingSector(targetSector, targetKeyType);
    state = "";
    update();
    return false;
  }

  // Standalone Static-Encrypted Nested (Fudan FM11RF08S backdoor, eprint
  // 2024/1275). Reuses the FFI staticEncryptedNested + StaticEncryptedKeysFilter
  // like recoverKeys(), but adds the Proxmark3 staticnested orchestration
  // speedups: cross-sector key-reuse prioritisation, default-key prioritisation
  // and the nt(A)==nt(B) => keyA==keyB shortcut. Ordering-only: every candidate
  // is still confirmed on-card by checkKeysOnSector, so it can only be faster,
  // never wrong. Returns true if any key was found.
  Future<bool> recoverBackdoor({
    (int, NestedNonces, NestedNonces, Uint8List)? acquiredBackdoorInfo,
  }) async {
    _throwIfCancelled();
    error = ""; // clear any stale error from a previous run
    final keyKnownAtEntry = validKeys.map((k) => k.isNotEmpty).toList();
    state = localizations.checking_card_info;
    update();
    final sectors = mfClassicGetSectorCount(
      mifareClassicType,
      isEV1: isMifareClassicEV1,
    );
    var backdoorInfo = acquiredBackdoorInfo;
    if (backdoorInfo == null) {
      if (!await mfClassicHasBackdoor(appState.communicator!)) {
        _throwIfCancelled();
        error = localizations.no_backdoor_support;
        state = "";
        update();
        return false;
      }
      backdoorInfo = await appState.communicator!
          .getMf1StaticEncryptedNestedAcquire(sectorCount: sectors);
      _throwIfCancelled();
    }
    if (backdoorInfo == null) {
      error = localizations.no_backdoor_support;
      state = "";
      update();
      return false;
    }

    // ---- Phase 1: collect filtered A/B candidate lists for every sector ----
    final candA = <int, List<Uint8List>>{};
    final candB = <int, List<Uint8List>>{};
    final rawA =
        <int, List<int>>{}; // unfiltered A candidates for findMatchingKeys
    final sameNt = <int, bool>{};
    for (var sector = 0; sector < sectors; sector++) {
      _throwIfCancelled();
      _updatePhase(
        AutopwnPhase.backdoor,
        "Backdoor: deriving candidates for sector ${sector + 1}/$sectors",
        progress: sectors == 0 ? 0.5 : 0.5 * sector / sectors,
      );
      // Phase 1 is a collect-all pass: show ONLY global progress so we don't
      // light up every block as "checking" at once (blocks keep their state;
      // phase 3 animates each block as it is confirmed).
      state =
          "${localizations.collecting_nonces("Backdoor")} ${sector + 1}/$sectors";
      keyCheckProgress = sectors == 0 ? null : sector / sectors;
      update();

      // Skip sectors already resolved (e.g. by the dictionary pass), and guard
      // against an acquire that returned fewer nonces than sectors (would throw
      // a RangeError on nonces[sector]).
      final aDone =
          getSectorState(sector, 0) == ChameleonKeyCheckmark.found ||
          getSectorState(sector, 0) == ChameleonKeyCheckmark.disabled;
      final bDone =
          getSectorState(sector, 1) == ChameleonKeyCheckmark.found ||
          getSectorState(sector, 1) == ChameleonKeyCheckmark.disabled;
      if ((aDone && bDone) ||
          sector >= backdoorInfo.$2.nonces.length ||
          sector >= backdoorInfo.$3.nonces.length) {
        candA[sector] = [];
        candB[sector] = [];
        rawA[sector] = [];
        sameNt[sector] = false;
        continue;
      }

      final aN = backdoorInfo.$2.nonces[sector];
      final bN = backdoorInfo.$3.nonces[sector];
      sameNt[sector] = aN.nt == bN.nt;
      try {
        final possibleAKeys = await recovery.staticEncryptedNested(
          StaticEncryptedNestedDart(
            uid: backdoorInfo.$1,
            nt: aN.nt,
            ntEnc: aN.ntEnc,
            ntParEnc: aN.parity,
          ),
        );
        _throwIfCancelled();
        final possibleBKeys = await recovery.staticEncryptedNested(
          StaticEncryptedNestedDart(
            uid: backdoorInfo.$1,
            nt: bN.nt,
            ntEnc: bN.ntEnc,
            ntParEnc: bN.parity,
          ),
        );
        _throwIfCancelled();
        rawA[sector] = possibleAKeys;
        final filtered = await StaticEncryptedKeysFilterAsync.filterKeys(
          possibleAKeys,
          possibleBKeys,
          aN.nt,
          bN.nt,
        );
        candA[sector] = mfClassicConvertKeys(filtered.$1.reversed.toList());
        candB[sector] = mfClassicConvertKeys(filtered.$2.reversed.toList());
      } catch (e) {
        if (e is MifareClassicRecoveryCancelled) rethrow;
        // Non-fatal: skip this sector, keep going (don't surface as error).
        candA[sector] = [];
        candB[sector] = [];
        rawA[sector] = [];
      }
    }
    keyCheckProgress = null;

    // ---- Phase 2: build priority set (cross-sector duplicates + defaults) ---
    final counts = <String, int>{};
    void tally(List<Uint8List> l) {
      for (final k in l) {
        final h = bytesToHex(k);
        counts[h] = (counts[h] ?? 0) + 1;
      }
    }

    for (var s = 0; s < sectors; s++) {
      _throwIfCancelled();
      tally(candA[s]!);
      tally(candB[s]!);
    }
    final defaultSet = gMifareClassicKeys.map(bytesToHex).toSet();
    List<Uint8List> prioritise(List<Uint8List> list) =>
        prioritiseByFrequency(list, counts, defaultSet);

    // ---- Phase 3: confirm keys on card, priority candidates first ----------
    for (var sector = 0; sector < sectors; sector++) {
      _throwIfCancelled();
      _updatePhase(
        AutopwnPhase.backdoor,
        "Backdoor: checking candidates for sector ${sector + 1}/$sectors",
        progress: sectors == 0 ? 1 : 0.5 + 0.5 * sector / sectors,
      );
      if (sector >= backdoorInfo.$2.nonces.length ||
          sector >= backdoorInfo.$3.nonces.length) {
        continue; // no nonces collected for this sector (guarded in phase 1)
      }
      final aN = backdoorInfo.$2.nonces[sector];
      final bN = backdoorInfo.$3.nonces[sector];
      try {
        // Key B
        if (getSectorState(sector, 1) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, 1) != ChameleonKeyCheckmark.disabled) {
          await checkKeysOnSector(prioritise(candB[sector]!), 1, sector);
          _throwIfCancelled();
        }
        // nt(A)==nt(B) => same key: reuse the recovered B key for A
        if (sameNt[sector]! &&
            getSectorState(sector, 1) == ChameleonKeyCheckmark.found &&
            getSectorState(sector, 0) != ChameleonKeyCheckmark.found) {
          await checkKeysOnSector([getSectorKey(sector, 1)], 0, sector);
          _throwIfCancelled();
        }
        // Key A (direct candidates, then derived from the recovered B key)
        if (getSectorState(sector, 0) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, 0) != ChameleonKeyCheckmark.disabled) {
          final aFound = await checkKeysOnSector(
            prioritise(candA[sector]!),
            0,
            sector,
          );
          _throwIfCancelled();
          if (!aFound &&
              getSectorState(sector, 1) == ChameleonKeyCheckmark.found) {
            final matching =
                await StaticEncryptedKeysFilterAsync.findMatchingKeys(
                  bN.nt,
                  bytesToU64(
                    Uint8List.fromList([0, 0, ...validKeys[sector + 40]]),
                  ),
                  aN.nt,
                  rawA[sector]!,
                );
            _throwIfCancelled();
            await checkKeysOnSector(mfClassicConvertKeys(matching), 0, sector);
          }
        }
      } catch (e) {
        if (e is MifareClassicRecoveryCancelled) rethrow;
        // Non-fatal: this sector failed to confirm; continue with the rest.
      }
      setMissingSector(sector, 0);
      setMissingSector(sector, 1);
    }
    state = "";
    _completeActivePhase(
      AutopwnPhase.backdoor,
      "Backdoor candidate recovery completed",
    );
    update();
    // Success = a key recovered THIS call (ignore pre-seeded EV1 keys).
    for (var idx = 0; idx < validKeys.length; idx++) {
      if (validKeys[idx].isNotEmpty && !keyKnownAtEntry[idx]) return true;
    }
    return false;
  }

  Future<void> recoverKeys() async {
    _throwIfCancelled();
    state = localizations.checking_card_info;
    update();

    error = "";
    bool hasKey = false;
    _startPhase(AutopwnPhase.backdoor, "Probing factory backdoor support");
    bool hasBackdoor = await mfClassicHasBackdoor(appState.communicator!);
    _throwIfCancelled();
    (int, NestedNonces, NestedNonces, Uint8List)? backdoorInfo;
    if (hasBackdoor) {
      backdoorInfo = await appState.communicator!
          .getMf1StaticEncryptedNestedAcquire(
            sectorCount: mfClassicGetSectorCount(
              mifareClassicType,
              isEV1: isMifareClassicEV1,
            ),
          );
      _throwIfCancelled();
      hasBackdoor = backdoorInfo != null;
    }
    if (hasBackdoor) {
      _deferPhase(
        AutopwnPhase.backdoor,
        "Factory backdoor detected and nonce data acquired",
      );
    } else {
      _completePhase(AutopwnPhase.backdoor, "Factory backdoor not detected");
    }

    DarksideResult darkside = DarksideResult.fixed;
    for (
      var sector = 0;
      sector <
              mfClassicGetSectorCount(
                mifareClassicType,
                isEV1: isMifareClassicEV1,
              ) &&
          !hasKey;
      sector++
    ) {
      _throwIfCancelled();
      for (var keyType = 0; keyType < 2; keyType++) {
        _throwIfCancelled();
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.found) {
          hasKey = true;
          break;
        }
      }
    }

    update();

    bool isStaticEncrypted = false;

    if (hasBackdoor) {
      isStaticEncrypted = await mfClassicIsStaticEncrypted(
        appState.communicator!,
        0,
        4,
        backdoorInfo!.$4,
      );
      _throwIfCancelled();
    }

    NTLevel prng = await appState.communicator!.getMf1NTLevel();
    _throwIfCancelled();
    update();

    if (!hasKey && !isStaticEncrypted && prng != NTLevel.static) {
      _startPhase(AutopwnPhase.darkside, "Checking Darkside vulnerability");
      state = localizations.checking_or_running_darkside;
      update();

      try {
        setCheckingSector(0, 1);
        darkside = await appState.communicator!.checkMf1Darkside();
        _throwIfCancelled();
      } catch (e) {
        if (e is MifareClassicRecoveryCancelled) rethrow;
        setMissingSector(0, 1);
      }

      if (darkside == DarksideResult.vulnerable) {
        // recover with darkside
        var data = await appState.communicator!.getMf1Darkside(
          0x03,
          0x61,
          true,
          15,
        );
        _throwIfCancelled();
        var darkside = DarksideDart(uid: data.uid, items: []);
        bool found = false;
        update();

        for (var tries = 0; tries < 5 && !found; tries++) {
          _throwIfCancelled();
          _updatePhase(
            AutopwnPhase.darkside,
            "Darkside capture ${tries + 1}/5",
            progress: tries / 5,
          );
          darkside.items.add(
            DarksideItemDart(
              nt1: data.nt1,
              ks1: data.ks1,
              par: data.par,
              nr: data.nr,
              ar: data.ar,
            ),
          );

          var keys = await recovery.darkside(darkside);
          _throwIfCancelled();
          if (keys.isNotEmpty) {
            appState.log!.d("Darkside: Found keys: $keys. Checking them...");

            if (await checkKeysOnSector(mfClassicConvertKeys(keys), 1, 0)) {
              found = true;
              hasKey = true;

              break;
            }
          } else {
            appState.log!.d("Can't find keys, retrying...");
            data = await appState.communicator!.getMf1Darkside(
              0x03,
              0x61,
              false,
              15,
            );
            _throwIfCancelled();
          }
        }

        if (!found) {
          setMissingSector(0, 1);
        }
      }
      _completePhase(
        AutopwnPhase.darkside,
        hasKey ? "Initial key recovered" : "Darkside completed without a key",
      );
    } else {
      _skipPendingPhase(
        AutopwnPhase.darkside,
        hasKey ? "A verified key is already available" : "Not applicable",
      );
    }

    update();

    if (!hasKey && hasBackdoor && prng == NTLevel.weak && !isStaticEncrypted) {
      _startPhase(
        AutopwnPhase.nested,
        "Recovering an initial key through backdoor auth",
      );
      state = localizations.backdoor_recovery_of_non_static_encrypted;
      setCheckingSector(0, 0);
      final result = await _recoverWeakNestedKey(
        0,
        0x64,
        backdoorInfo!.$4,
        0,
        0x60,
        rankAcrossCaptures: exhaustiveRecovery,
        targetLabel: "sector 1 key A",
        verifyCandidates: (keys) =>
            checkKeysOnSector(mfClassicConvertKeys(keys), 0, 0),
      );
      if (!result.$1) setMissingSector(0, 0);
    }

    Uint8List validKey = Uint8List(0);
    int validKeyBlock = 0;
    int validKeyType = -1;

    knownKeySearch:
    for (
      var sector = 0;
      sector <
          mfClassicGetSectorCount(mifareClassicType, isEV1: isMifareClassicEV1);
      sector++
    ) {
      _throwIfCancelled();
      for (var keyType = 0; keyType < 2; keyType++) {
        _throwIfCancelled();
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.found) {
          validKey = getSectorKey(sector, keyType);
          validKeyBlock = mfClassicGetSectorTrailerBlockBySector(sector);
          validKeyType = keyType;
          if (!isStaticEncrypted) {
            isStaticEncrypted = await mfClassicIsStaticEncrypted(
              appState.communicator!,
              validKeyBlock,
              validKeyType,
              validKey,
            );
            _throwIfCancelled();
          }
          break knownKeySearch;
        }
      }
    }

    if ((isStaticEncrypted || (validKeyType == -1 && hasBackdoor)) &&
        backdoorInfo != null) {
      prng = NTLevel.backdoor;
    }

    if (prng != NTLevel.backdoor && hasBackdoor) {
      _completePhase(
        AutopwnPhase.backdoor,
        "Factory backdoor detected but not required",
      );
    }

    if (validKeyType == -1 && prng != NTLevel.backdoor) {
      error = localizations.recovery_error_no_keys_darkside;
      state = "";
      _completeActivePhase(
        AutopwnPhase.nested,
        "Nested completed without an initial key",
      );
      _skipPendingPhase(AutopwnPhase.nested, "No verified key is available");
      _skipPendingPhase(
        AutopwnPhase.staticNested,
        "No verified key is available",
      );
      _skipPendingPhase(
        AutopwnPhase.hardnested,
        "No verified key is available",
      );
      return;
    }

    int tries = [NTLevel.backdoor, NTLevel.static].contains(prng) ? 1 : 5;

    // RF08S backdoor: delegate to the optimized standalone recovery — it collects
    // every sector's candidates (global progress bar, no all-blocks flash),
    // prioritises cross-sector duplicate + default keys, and confirms each block
    // per-sector (animation). The per-sector loop below is skipped for this case.
    if (prng == NTLevel.backdoor) {
      _startPhase(
        AutopwnPhase.backdoor,
        "Recovering RF08S candidates through the factory backdoor",
      );
      await recoverBackdoor(acquiredBackdoorInfo: backdoorInfo);
      _throwIfCancelled();
      _completePhase(
        AutopwnPhase.backdoor,
        "Backdoor candidate recovery completed",
      );
      _skipPendingPhase(AutopwnPhase.nested, "Weak Nested not required");
      _skipPendingPhase(
        AutopwnPhase.staticNested,
        "Static Nested fallback not required",
      );
      _skipPendingPhase(AutopwnPhase.hardnested, "Hardnested not required");
    } else if (prng == NTLevel.weak) {
      _startPhase(
        AutopwnPhase.nested,
        exhaustiveRecovery
            ? "Collecting and ranking Nested candidates"
            : "Recovering missing keys with Nested",
      );
      _skipPendingPhase(AutopwnPhase.hardnested, "Card PRNG is not hard");
    } else if (prng == NTLevel.static) {
      _startPhase(
        AutopwnPhase.staticNested,
        "Recovering keys with Static Nested",
      );
      _skipPendingPhase(AutopwnPhase.nested, "Card uses static nonces");
      _skipPendingPhase(AutopwnPhase.hardnested, "Card PRNG is not hard");
    } else if (prng == NTLevel.hard) {
      _startPhase(AutopwnPhase.hardnested, "Recovering keys with Hardnested");
      _skipPendingPhase(AutopwnPhase.nested, "Card PRNG is hard");
      _skipPendingPhase(
        AutopwnPhase.staticNested,
        "Card does not use static nonces",
      );
    }

    // The NT distance is a card-level PRNG property tied to the reference
    // key/block, not the target sector — measure it once and reuse it across
    // sectors instead of re-measuring for every sector (weak/hard nested). If a
    // sector later fails, it is reset so the next sector re-measures (drift).
    NTDistance? cardDistance;
    if (prng != NTLevel.backdoor && validKeyType != -1) {
      try {
        cardDistance = await appState.communicator!.getMf1NTDistance(
          validKeyBlock,
          0x60 + validKeyType,
          validKey,
        );
        _throwIfCancelled();
      } catch (e) {
        if (e is MifareClassicRecoveryCancelled) rethrow;
      }
    }

    final sectorCount = mfClassicGetSectorCount(
      mifareClassicType,
      isEV1: isMifareClassicEV1,
    );
    final pendingTargets = [
      for (var sector = 0; sector < sectorCount; sector++)
        for (var keyType = 0; keyType < 2; keyType++)
          if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none)
            (sector, keyType),
    ];
    var processedTargets = 0;

    for (
      var sector = 0;
      prng != NTLevel.backdoor && sector < sectorCount;
      sector++
    ) {
      _throwIfCancelled();
      for (var keyType = 0; keyType < 2; keyType++) {
        _throwIfCancelled();
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none) {
          final targetLabel =
              "sector ${sector + 1}/$sectorCount key ${keyType == 0 ? 'A' : 'B'}";
          final targetProgress = pendingTargets.isEmpty
              ? 1.0
              : processedTargets / pendingTargets.length;
          if (prng == NTLevel.weak) {
            _updatePhase(
              AutopwnPhase.nested,
              "Nested: $targetLabel",
              progress: targetProgress,
            );
          } else if (prng == NTLevel.static) {
            _updatePhase(
              AutopwnPhase.staticNested,
              "Static Nested: $targetLabel",
              progress: targetProgress,
            );
          } else if (prng == NTLevel.hard) {
            _updatePhase(
              AutopwnPhase.hardnested,
              "Hardnested: $targetLabel",
              progress: targetProgress,
            );
          }
          String attackType;

          switch (prng) {
            case NTLevel.static:
              attackType = "Static Nested";
            case NTLevel.weak:
              attackType = "Nested";
            case NTLevel.hard:
              attackType = "Hard Nested";
            case NTLevel.backdoor:
              attackType = localizations.has_backdoor_support;
            case NTLevel.unknown:
              attackType = "";
          }

          state = localizations.collecting_nonces(attackType);
          setCheckingSector(sector, keyType);

          NTDistance? distance = cardDistance;
          NestedNonces? nonces;

          // Reuse the once-measured distance; only re-measure if we don't have
          // one (first measure failed, or a prior sector reset it for drift).
          if (prng != NTLevel.backdoor && distance == null) {
            distance = await appState.communicator!.getMf1NTDistance(
              validKeyBlock,
              0x60 + validKeyType,
              validKey,
            );
            _throwIfCancelled();
            cardDistance = distance;
          }

          bool found = false;
          if (prng == NTLevel.weak) {
            final result = await _recoverWeakNestedKey(
              validKeyBlock,
              0x60 + validKeyType,
              validKey,
              mfClassicGetSectorTrailerBlockBySector(sector),
              0x60 + keyType,
              attempts: tries,
              initialDistance: distance,
              rankAcrossCaptures: exhaustiveRecovery,
              targetLabel: targetLabel,
              verifyCandidates: (keys) => checkKeysOnSector(
                mfClassicConvertKeys(keys),
                keyType,
                sector,
              ),
            );
            cardDistance = result.$2;
            found = result.$1;
            if (!found) {
              cardDistance = null;
              setMissingSector(sector, keyType);
            }
            processedTargets++;
            _updatePhase(
              AutopwnPhase.nested,
              "Nested processed $processedTargets/${pendingTargets.length} targets",
              progress: pendingTargets.isEmpty
                  ? 1
                  : processedTargets / pendingTargets.length,
            );
            continue;
          }

          for (var i = 0; i < tries && !found; i++) {
            _throwIfCancelled();
            List<int> keys = [];
            String? nonceFingerprint;

            if (prng == NTLevel.hard) {
              hardnestedProgress = 0;
              update();

              var result = await collectHardnestedNonces(
                validKeyBlock,
                0x60 + validKeyType,
                validKey,
                mfClassicGetSectorTrailerBlockBySector(sector),
                0x60 + keyType,
              );
              _throwIfCancelled();

              if (result is String) {
                setMissingSector(sector, keyType);
                error = result;
                hardnestedProgress = null;
                state = "";
                autopwnProgress?.fail(AutopwnPhase.hardnested, result);
                update();
                return;
              } else {
                nonces = result as NestedNonces;
              }
            } else if (prng != NTLevel.backdoor) {
              _updateActivityProgress(
                'Static Nested nonces',
                completed: 0,
                total: 2,
              );
              nonces = await appState.communicator!.getMf1NestedNonces(
                validKeyBlock,
                0x60 + validKeyType,
                validKey,
                mfClassicGetSectorTrailerBlockBySector(sector),
                0x60 + keyType,
                level: prng,
              );
              _throwIfCancelled();
              _updateActivityProgress(
                'Static Nested nonces',
                completed: nonces.nonces.length > 2 ? 2 : nonces.nonces.length,
                total: 2,
              );
            }

            state = localizations.recovering_key(attackType);
            update();

            if (prng == NTLevel.static) {
              if (nonces!.nonces.length < 2) continue;
              nonceFingerprint = _nonceCaptureFingerprint(
                'static',
                knownBlock: validKeyBlock,
                knownKeyType: 0x60 + validKeyType,
                targetBlock: mfClassicGetSectorTrailerBlockBySector(sector),
                targetKeyType: 0x60 + keyType,
                distance: distance!,
                nonces: nonces,
              );
              if (_hasStoredNonceCapture(nonceFingerprint)) {
                _updatePhase(
                  AutopwnPhase.staticNested,
                  'Static Nested: skipping a stored nonce capture for $targetLabel',
                );
                continue;
              }
              var nested = StaticNestedDart(
                uid: distance.uid,
                keyType: 0x60 + keyType,
                nt0: nonces.nonces[0].nt,
                nt0Enc: nonces.nonces[0].ntEnc,
                nt1: nonces.nonces[1].nt,
                nt1Enc: nonces.nonces[1].ntEnc,
              );

              keys = await recovery.staticNested(nested);
              _throwIfCancelled();
            } else if (prng == NTLevel.hard) {
              var nested = HardNestedDart(
                nonces: nonces!.getHardNested(distance!.uid),
              );
              keys = await recovery.hardNested(nested);
              _throwIfCancelled();
            } else if (prng == NTLevel.backdoor) {
              setCheckingSector(sector, 1);

              var possibleAKeys = await recovery.staticEncryptedNested(
                StaticEncryptedNestedDart(
                  uid: backdoorInfo!.$1,
                  nt: backdoorInfo.$2.nonces[sector].nt,
                  ntEnc: backdoorInfo.$2.nonces[sector].ntEnc,
                  ntParEnc: backdoorInfo.$2.nonces[sector].parity,
                ),
              );
              _throwIfCancelled();

              var possibleBKeys = await recovery.staticEncryptedNested(
                StaticEncryptedNestedDart(
                  uid: backdoorInfo.$1,
                  nt: backdoorInfo.$3.nonces[sector].nt,
                  ntEnc: backdoorInfo.$3.nonces[sector].ntEnc,
                  ntParEnc: backdoorInfo.$3.nonces[sector].parity,
                ),
              );
              _throwIfCancelled();

              var filtered = await StaticEncryptedKeysFilterAsync.filterKeys(
                possibleAKeys,
                possibleBKeys,
                backdoorInfo.$2.nonces[sector].nt,
                backdoorInfo.$3.nonces[sector].nt,
              );
              _throwIfCancelled();

              if (checkMarks[sector + 40] != ChameleonKeyCheckmark.found &&
                  checkMarks[sector + 40] != ChameleonKeyCheckmark.disabled &&
                  await checkKeysOnSector(
                    mfClassicConvertKeys(filtered.$2.reversed.toList()),
                    1,
                    sector,
                  )) {
                _throwIfCancelled();
                checkMarks[sector + 40] = ChameleonKeyCheckmark.found;
              }

              if (checkMarks[sector] == ChameleonKeyCheckmark.found ||
                  checkMarks[sector] == ChameleonKeyCheckmark.disabled) {
                found = true;
                break;
              } else if (await checkKeysOnSector(
                mfClassicConvertKeys(
                  await StaticEncryptedKeysFilterAsync.findMatchingKeys(
                    backdoorInfo.$3.nonces[sector].nt,
                    bytesToU64(
                      Uint8List.fromList([0, 0, ...validKeys[sector + 40]]),
                    ),
                    backdoorInfo.$2.nonces[sector].nt,
                    possibleAKeys,
                  ),
                ),
                0,
                sector,
              )) {
                _throwIfCancelled();
                found = true;
                break;
              } else if (await checkKeysOnSector(
                mfClassicConvertKeys(filtered.$1.reversed.toList()),
                0,
                sector,
              )) {
                _throwIfCancelled();
                found = true;
                break;
              }

              setMissingSector(sector, 0);
              setMissingSector(sector, 1);
            }

            if (keys.isNotEmpty) {
              appState.log!.d(
                "Checking ${keys.length} recovered key candidates...",
              );

              final verified = await checkKeysOnSector(
                mfClassicConvertKeys(keys),
                keyType,
                sector,
              );
              if (nonceFingerprint != null) {
                await _storeNonceCapture(nonceFingerprint);
                _throwIfCancelled();
              }
              if (verified) {
                _throwIfCancelled();
                found = true;

                break;
              }
            } else {
              appState.log!.e("Can't find keys, retrying...");
            }
          }
          if (prng == NTLevel.static || prng == NTLevel.hard) {
            processedTargets++;
            final phase = prng == NTLevel.static
                ? AutopwnPhase.staticNested
                : AutopwnPhase.hardnested;
            _updatePhase(
              phase,
              "$attackType processed $processedTargets/${pendingTargets.length} targets",
              progress: pendingTargets.isEmpty
                  ? 1
                  : processedTargets / pendingTargets.length,
            );
          }
        }
      }
    }

    if (prng == NTLevel.weak) {
      _completeActivePhase(
        AutopwnPhase.nested,
        "Nested pass completed for all pending targets",
      );
    } else if (prng == NTLevel.static) {
      _completeActivePhase(
        AutopwnPhase.staticNested,
        "Static Nested pass completed",
      );
    } else if (prng == NTLevel.hard) {
      _completeActivePhase(
        AutopwnPhase.hardnested,
        "Hardnested pass completed",
      );
    }

    // A card can be misclassified as weak when its static nonce probe was
    // inconclusive. Complete the weak pass first, then try Static Nested only
    // for unresolved targets. The native solver rejects non-static nonce
    // signatures, so this fallback cannot mark a key without on-card auth.
    if (prng == NTLevel.weak && validKeyType != -1) {
      final staticTargets = [
        for (var sector = 0; sector < sectorCount; sector++)
          for (var keyType = 0; keyType < 2; keyType++)
            if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none)
              (sector, keyType),
      ];
      if (staticTargets.isEmpty) {
        _skipPendingPhase(
          AutopwnPhase.staticNested,
          "Nested resolved all target keys",
        );
      } else {
        _startPhase(
          AutopwnPhase.staticNested,
          "Running Static Nested fallback on unresolved targets",
        );
        try {
          cardDistance ??= await appState.communicator!.getMf1NTDistance(
            validKeyBlock,
            0x60 + validKeyType,
            validKey,
          );
          _throwIfCancelled();
          var processedStaticTargets = 0;
          for (final target in staticTargets) {
            _throwIfCancelled();
            final (sector, keyType) = target;
            final targetLabel =
                "sector ${sector + 1}/$sectorCount key ${keyType == 0 ? 'A' : 'B'}";
            _updatePhase(
              AutopwnPhase.staticNested,
              "Static Nested fallback: $targetLabel",
              progress: processedStaticTargets / staticTargets.length,
            );
            state = localizations.collecting_nonces("Static Nested");
            setCheckingSector(sector, keyType);
            final result = await _recoverStaticNestedKey(
              validKeyBlock,
              0x60 + validKeyType,
              validKey,
              mfClassicGetSectorTrailerBlockBySector(sector),
              0x60 + keyType,
              initialDistance: cardDistance,
              targetLabel: targetLabel,
              verifyCandidates: (keys) => checkKeysOnSector(
                mfClassicConvertKeys(keys),
                keyType,
                sector,
              ),
            );
            if (result != StaticNestedAttemptResult.found) {
              setMissingSector(sector, keyType);
            }
            processedStaticTargets++;
            if (result == StaticNestedAttemptResult.incompatible) {
              _completeActivePhase(
                AutopwnPhase.staticNested,
                "Static Nested fallback is incompatible with this card",
              );
              break;
            }
          }
          _completeActivePhase(
            AutopwnPhase.staticNested,
            "Static Nested fallback processed ${staticTargets.length} targets",
          );
        } catch (exception) {
          if (exception is MifareClassicRecoveryCancelled) rethrow;
          appState.log!.w("Static Nested fallback unavailable: $exception");
          for (final (sector, keyType) in staticTargets) {
            setMissingSector(sector, keyType);
          }
          autopwnProgress?.fail(
            AutopwnPhase.staticNested,
            "Static Nested fallback unavailable: $exception",
          );
          update();
        }
      }
    }

    _skipPendingPhase(AutopwnPhase.nested, "Nested was not applicable");
    _skipPendingPhase(
      AutopwnPhase.staticNested,
      "Static Nested was not applicable",
    );
    _skipPendingPhase(AutopwnPhase.hardnested, "Hardnested was not applicable");

    state = "";
    allKeysExists = true;
    for (
      var sector = 0;
      sector <
          mfClassicGetSectorCount(mifareClassicType, isEV1: isMifareClassicEV1);
      sector++
    ) {
      _throwIfCancelled();
      for (var keyType = 0; keyType < 2; keyType++) {
        _throwIfCancelled();
        if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
          allKeysExists = false;
        }
      }
    }
    update();
  }

  // Read every block of [sector], preferring a single authenticate-once
  // MF1_READ_BLOCKS (2018) for the whole sector and falling back to per-block
  // reads for anything it doesn't return. Returns one Uint8List per block
  // (empty means unreadable). Never throws.
  Future<List<Uint8List>> _readSectorBlocks(
    int sector,
    int firstBlock,
    int blocks,
  ) async {
    _throwIfCancelled();
    // Try the batched read with whichever key we have (keyA preferred).
    final primaryType = getSectorKey(sector, 0).isNotEmpty
        ? 0
        : (getSectorKey(sector, 1).isNotEmpty ? 1 : -1);
    List<Uint8List> batch = const [];
    if (primaryType != -1) {
      try {
        batch = await appState.communicator!.mf1ReadBlocks(
          firstBlock,
          blocks,
          0x60 + primaryType,
          getSectorKey(sector, primaryType),
        );
        _throwIfCancelled();
      } catch (e) {
        if (e is MifareClassicRecoveryCancelled) rethrow;
        batch = const [];
      }
    }

    final out = <Uint8List>[];
    for (var b = 0; b < blocks; b++) {
      _throwIfCancelled();
      if (b < batch.length && batch[b].length == 16) {
        out.add(Uint8List.fromList(batch[b]));
        continue;
      }
      // Per-block fallback (block the batch didn't return): keyA then keyB.
      Uint8List blockData = Uint8List(0);
      for (var keyType = 0; keyType < 2; keyType++) {
        _throwIfCancelled();
        final key = getSectorKey(sector, keyType);
        if (key.isEmpty) continue;
        final d = await appState.communicator!.mf1ReadBlock(
          firstBlock + b,
          0x60 + keyType,
          key,
        );
        _throwIfCancelled();
        if (d.length == 16) {
          blockData = d;
          break;
        }
      }
      out.add(blockData);
    }
    return out;
  }

  Future<void> dumpData() async {
    _throwIfCancelled();
    _startPhase(AutopwnPhase.dump, "Reading card blocks");
    cardData = List.generate(256, (_) => Uint8List(0));
    dumpProgress = 0;

    final sectorCount = mfClassicGetSectorCount(
      mifareClassicType,
      isEV1: isMifareClassicEV1,
    );
    final totalBlocks = mfClassicGetBlockCount(
      mifareClassicType,
      isEV1: isMifareClassicEV1,
    );

    for (var sector = 0; sector < sectorCount; sector++) {
      _throwIfCancelled();
      final firstBlock = mfClassicGetFirstBlockCountBySector(sector);
      final blocks = mfClassicGetBlockCountBySector(sector);
      final trailer = mfClassicGetSectorTrailerBlockBySector(sector);

      final sectorBlocks = await _readSectorBlocks(sector, firstBlock, blocks);
      _throwIfCancelled();

      for (var b = 0; b < blocks; b++) {
        _throwIfCancelled();
        final absBlock = firstBlock + b;
        // Empty means unreadable -> store zeros (matches the old behaviour).
        Uint8List blockData = sectorBlocks[b].length == 16
            ? sectorBlocks[b]
            : Uint8List(16);

        if (absBlock == trailer) {
          // Fill in the known keys (they read back as zeros from the card).
          if (getSectorKey(sector, 0).isNotEmpty) {
            blockData.setRange(0, 6, getSectorKey(sector, 0));
          }
          if (getSectorKey(sector, 1).isNotEmpty) {
            blockData.setRange(10, 16, getSectorKey(sector, 1));
          }
        }

        cardData[absBlock] = blockData;
        dumpProgress = totalBlocks == 0 ? 1.0 : (absBlock + 1) / totalBlocks;
        _updatePhase(
          AutopwnPhase.dump,
          "Reading block ${absBlock + 1}/$totalBlocks",
          progress: dumpProgress,
        );
        update();
      }
    }
    _completePhase(AutopwnPhase.dump, "Card data read complete");
  }

  Future<dynamic> collectHardnestedNonces(
    int block,
    int keyType,
    Uint8List knownKey,
    int targetBlock,
    int targetKeyType,
  ) async {
    _throwIfCancelled();
    NestedNonces nonces = NestedNonces(nonces: []);
    _updateActivityProgress(
      'Hardnested nonce coverage',
      completed: 0,
      total: 256,
    );
    while (true) {
      _throwIfCancelled();
      var collectedNonces = await appState.communicator!.getMf1NestedNonces(
        block,
        keyType,
        knownKey,
        targetBlock,
        targetKeyType,
        level: NTLevel.hard,
      );
      _throwIfCancelled();
      nonces.nonces.addAll(collectedNonces.nonces);
      List info = nonces.getNoncesInfo();
      appState.log!.d(
        "Collected ${nonces.nonces.length} nonces, sum ${info[0]}, num ${info[1]}",
      );

      if (nonces.nonces.isEmpty) {
        return localizations.recovery_old_firmware;
      }

      hardnestedProgress = info[1] / 256;
      _updateActivityProgress(
        'Hardnested nonce coverage',
        completed: info[1] as int,
        total: 256,
      );
      state = localizations.hardnested_collecting_nonces(
        (hardnestedProgress! * 256).toInt().toString(),
      );
      _updatePhase(
        AutopwnPhase.hardnested,
        "Hardnested nonce coverage ${(hardnestedProgress! * 100).toStringAsFixed(0)}%",
        progress: hardnestedProgress,
      );
      update();
      if (info[1] == 256) {
        if ([
          0,
          32,
          56,
          64,
          80,
          96,
          104,
          112,
          120,
          128,
          136,
          144,
          152,
          160,
          176,
          192,
          200,
          224,
          256,
        ].contains(info[0])) {
          break;
        }

        appState.log!.e("Got wrong sum, trying to collect nonces again...");
        nonces.nonces = [];
        _updateActivityProgress(
          'Hardnested nonce coverage',
          completed: 0,
          total: 256,
        );
      }
    }

    hardnestedProgress = null;
    return nonces;
  }

  void setKeyAsFound(int sector, int keyType, Uint8List key) {
    checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.found;
    validKeys[sector + (keyType * 40)] = key;
    update();
  }

  void setCheckingSector(int sector, int keyType) {
    if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none) {
      checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.checking;
    }
    update();
  }

  void setMissingSector(int sector, int keyType) {
    if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.checking) {
      checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.none;
      update();
    }
  }

  Uint8List getSectorKey(int sector, int keyType) {
    return validKeys[sector + (keyType * 40)];
  }

  ChameleonKeyCheckmark getSectorState(int sector, int keyType) {
    return checkMarks[sector + (keyType * 40)];
  }
}
