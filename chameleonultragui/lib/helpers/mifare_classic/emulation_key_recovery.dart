import 'dart:async';
import 'dart:ui';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/reader_key_recovery.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/foundation.dart';

typedef Mf1EmulationSlotOperation =
    Future<void> Function(Future<void> Function() operation);

class Mf1EmulationKeyRecoveryController extends ChangeNotifier {
  Mf1EmulationKeyRecoveryController(
    this._preferences, {
    ReaderMfkey32Solver? solver,
    this.pollInterval = const Duration(seconds: 2),
    this.onKeysSaved,
  }) : _solver = solver ?? _defaultSolver,
       super();

  static const _maxEvidencePerTarget = 32;
  static const _maxEvidence = 2560;
  static const _dictionaryColor = Color(0xFFFF375F);

  final SharedPreferencesProvider _preferences;
  final ReaderMfkey32Solver _solver;
  final VoidCallback? onKeysSaved;
  final Duration pollInterval;
  final List<DetectionResult> _evidence = [];
  final Set<String> _evidenceIds = {};
  final Map<ReaderKeyTarget, ReaderKeyRecoveryResult> _results = {};
  final Map<ReaderKeyTarget, String> _appliedKeys = {};
  final Map<int, Uint8List> _trailerBackups = {};
  final Set<String> _savedKeys = {};
  final Set<String> _dictionaryNames = {};

  _Mf1EmulationRecoverySession? _session;
  Timer? _pollTimer;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  Future<void>? _pollOperation;
  int _deviceCursor = 0;
  int _capturedNonceCount = 0;
  int _sectorCount = 0;
  int _generation = 0;
  String _lastRecoveryFingerprint = '';
  String? _error;
  bool _active = false;
  bool _recovering = false;
  bool _stopping = false;
  bool _disposed = false;

  bool get active => _active;
  bool get isRecovering => _recovering;
  bool get isStopping => _stopping;
  bool get cleanupPending => _session != null && !_active && !_stopping;
  String? get error => _error;
  int get capturedNonceCount => _capturedNonceCount;
  int get sectorCount => _sectorCount;
  int get targetCount => groupReaderKeyRecords(_evidence).length;
  int get recoveredKeyCount =>
      _results.values.where((result) => result.key != null).length;
  int get verifiedKeyCount => _results.values
      .where((result) => result.key != null && result.verifiedByReader)
      .length;
  int get recoveredSectorCount => _results.values
      .where((result) => result.key != null)
      .map((result) => result.target.sector)
      .toSet()
      .length;

  List<ReaderKeyRecoveryResult> get recoveredResults {
    final output =
        _results.values.where((result) => result.key != null).toList()
          ..sort((left, right) {
            final uid = left.target.uid.compareTo(right.target.uid);
            if (uid != 0) return uid;
            final sector = left.target.sector.compareTo(right.target.sector);
            if (sector != 0) return sector;
            return left.target.keyB == right.target.keyB
                ? 0
                : left.target.keyB
                ? 1
                : -1;
          });
    return List.unmodifiable(output);
  }

  List<String> get dictionaryNames {
    final output = _dictionaryNames.toList()..sort();
    return List.unmodifiable(output);
  }

  bool owns(ChameleonCommunicator communicator) =>
      identical(_session?.communicator, communicator);

  void reset() {
    if (_session != null) {
      throw StateError('Cannot reset an active HF emulation recovery session');
    }
    _clearSessionState();
    _notify();
  }

  void abandon(ChameleonCommunicator communicator) {
    if (!owns(communicator)) return;
    if (_active ||
        _stopping ||
        _startOperation != null ||
        _stopOperation != null) {
      throw StateError('Cannot abandon an active recovery operation');
    }
    _session = null;
    _clearSessionState();
    _error = 'Recovery cleanup was abandoned after the connection changed.';
    _notify();
  }

  Future<void> start({
    required ChameleonCommunicator communicator,
    required int slot,
    required TagType tagType,
    required Mf1EmulationSlotOperation runSlotOperation,
  }) {
    if (_startOperation != null || _stopOperation != null) {
      throw StateError('An HF emulation recovery operation is in progress');
    }
    late final Future<void> operation;
    operation =
        _start(
          communicator: communicator,
          slot: slot,
          tagType: tagType,
          runSlotOperation: runSlotOperation,
        ).whenComplete(() {
          if (identical(_startOperation, operation)) {
            _startOperation = null;
            _notify();
          }
        });
    _startOperation = operation;
    return operation;
  }

  Future<void> _start({
    required ChameleonCommunicator communicator,
    required int slot,
    required TagType tagType,
    required Mf1EmulationSlotOperation runSlotOperation,
  }) async {
    if (_disposed) throw StateError('Recovery controller is disposed');
    if (_session != null) {
      throw StateError('An HF emulation recovery session is already active');
    }
    if (!isMifareClassic(tagType)) {
      throw ArgumentError.value(tagType, 'tagType', 'must be MIFARE Classic');
    }

    final generation = ++_generation;
    final session = _Mf1EmulationRecoverySession(
      generation: generation,
      communicator: communicator,
      slot: slot,
      sectorCount: mfClassicGetSectorCount(
        chameleonTagTypeGetMfClassicType(tagType),
      ),
      blockCount: mfClassicGetBlockCount(
        chameleonTagTypeGetMfClassicType(tagType),
      ),
      runSlotOperation: runSlotOperation,
      reselectSupported:
          communicator.supportsCommandSync(
            ChameleonCommand.mf1ReaderKeysReselect,
          ) !=
          false,
    );
    _clearSessionState();
    _session = session;
    _sectorCount = session.sectorCount;
    _error = null;
    _notify();

    try {
      await communicator.setMf1DetectionStatus(true);
      session.detectionEnabled = true;
      if (!_isCurrent(session) || _stopping) return;
      if (communicator.supportsCommandSync(
            ChameleonCommand.mf1SetReaderKeysAnim,
          ) !=
          false) {
        try {
          await communicator.setMf1ReaderKeysAnim(true);
          session.animationEnabled = true;
        } catch (_) {
          // Capture remains fully functional on firmware without the animation.
        }
      }
      if (!_isCurrent(session) || _stopping) return;
      _active = true;
      _pollTimer = Timer.periodic(
        pollInterval,
        (_) => unawaited(_pollFromTimer()),
      );
      _notify();
    } catch (error, stackTrace) {
      Object? cleanupError;
      try {
        await _disableCapture(session);
      } catch (failure) {
        cleanupError = failure;
      }
      if (_isCurrent(session)) {
        _active = false;
        if (cleanupError == null) {
          _session = null;
        } else {
          _error = cleanupError.toString();
        }
        _notify();
      }
      Error.throwWithStackTrace(cleanupError ?? error, stackTrace);
    }
  }

  Future<void> pollNow() {
    final session = _session;
    if (!_active || session == null || _stopping) return Future.value();
    final existing = _pollOperation;
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = _poll(session).whenComplete(() {
      if (identical(_pollOperation, operation)) _pollOperation = null;
    });
    _pollOperation = operation;
    return operation;
  }

  Future<void> stop({ChameleonCommunicator? communicator}) {
    final existing = _stopOperation;
    if (existing != null) return existing;
    final session = _session;
    if (session == null ||
        (communicator != null &&
            !identical(session.communicator, communicator))) {
      return Future.value();
    }
    late final Future<void> operation;
    operation = _stop(session).whenComplete(() {
      if (identical(_stopOperation, operation)) _stopOperation = null;
    });
    _stopOperation = operation;
    return operation;
  }

  Future<void> _stop(_Mf1EmulationRecoverySession session) async {
    _stopping = true;
    _active = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _notify();

    Object? firstError;
    final starting = _startOperation;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        // Start performs its own rollback; stop still verifies all cleanup.
      }
    }
    if (!_isCurrent(session)) {
      _stopping = false;
      _notify();
      return;
    }
    final inFlight = _pollOperation;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (error) {
        firstError = error;
      }
    }
    var finalizationComplete = true;
    if (_isCurrent(session)) {
      try {
        await _syncEvidence(session);
      } catch (error) {
        firstError ??= error;
      }
      try {
        await _disableCapture(session);
      } catch (error) {
        firstError ??= error;
      }
      try {
        await _syncEvidence(session);
        await _recover(session, applyKeys: false);
      } catch (error) {
        finalizationComplete = false;
        firstError ??= error;
      }
      try {
        await _restoreTrailers(session);
      } catch (error) {
        firstError ??= error;
      }
    }

    if (_isCurrent(session)) {
      final cleanupComplete =
          !session.animationEnabled &&
          !session.detectionEnabled &&
          _trailerBackups.isEmpty;
      if (cleanupComplete && finalizationComplete) _session = null;
      _stopping = false;
      if (firstError != null) _error = firstError.toString();
      _notify();
    }
    if (firstError != null) throw firstError;
  }

  Future<void> _pollFromTimer() async {
    try {
      await pollNow();
    } catch (error) {
      if (_disposed) return;
      _error = error.toString();
      _notify();
    }
  }

  Future<void> _poll(_Mf1EmulationRecoverySession session) async {
    if (!_isCurrent(session) || !_active) return;
    try {
      await _syncEvidence(session);
      if (!_isCurrent(session) || !_active) return;
      if (hasRecoverableReaderKeyEvidence(_evidence) &&
          readerKeyEvidenceFingerprint(_evidence) != _lastRecoveryFingerprint) {
        await _recover(session);
      }
      if (!_isCurrent(session) || !_active) return;
      final deviceCount = await session.communicator.getMf1DetectionCount();
      if (deviceCount >= 1000) {
        await session.communicator.setMf1DetectionStatus(false);
        session.detectionEnabled = false;
        await _syncEvidence(session);
        if (hasRecoverableReaderKeyEvidence(_evidence) &&
            readerKeyEvidenceFingerprint(_evidence) !=
                _lastRecoveryFingerprint) {
          await _recover(session);
        }
      }
      if (_isCurrent(session) && _active && !session.detectionEnabled) {
        await session.communicator.setMf1DetectionStatus(true);
        session.detectionEnabled = true;
        _deviceCursor = 0;
      }
      if (_isCurrent(session)) {
        _error = null;
        _notify();
      }
    } catch (error) {
      if (_isCurrent(session)) {
        _error = error.toString();
        _notify();
      }
      rethrow;
    }
  }

  Future<int> _syncEvidence(_Mf1EmulationRecoverySession session) async {
    final communicator = session.communicator;
    final deviceCount = await communicator.getMf1DetectionCount();
    if (!_isCurrent(session)) return 0;
    if (deviceCount < _deviceCursor) _deviceCursor = 0;
    if (deviceCount == _deviceCursor) return 0;

    final startIndex = _deviceCursor;
    final records = await communicator.getMf1DetectionRecords(
      deviceCount,
      startIndex: startIndex,
    );
    if (!_isCurrent(session)) return 0;
    final expected = deviceCount - startIndex;
    if (records.length != expected) {
      throw FormatException(
        'Incomplete MF1 detection range: ${records.length}/$expected',
      );
    }
    _deviceCursor = deviceCount;
    _capturedNonceCount += records.length;

    var added = 0;
    for (final record in records) {
      final identity = readerKeyTranscriptIdentity(record);
      if (!_evidenceIds.add(identity)) continue;
      final target = ReaderKeyTarget(
        uid: record.uid,
        sector: mfClassicGetSectorByBlock(record.block),
        keyB: record.type == 0x61,
      );
      while (_evidence
              .where(
                (existing) =>
                    existing.uid == target.uid &&
                    mfClassicGetSectorByBlock(existing.block) ==
                        target.sector &&
                    (existing.type == 0x61) == target.keyB,
              )
              .length >=
          _maxEvidencePerTarget) {
        final index = _evidence.indexWhere(
          (existing) =>
              existing.uid == target.uid &&
              mfClassicGetSectorByBlock(existing.block) == target.sector &&
              (existing.type == 0x61) == target.keyB,
        );
        _evidenceIds.remove(readerKeyTranscriptIdentity(_evidence[index]));
        _evidence.removeAt(index);
      }
      if (_evidence.length >= _maxEvidence) {
        _evidenceIds.remove(readerKeyTranscriptIdentity(_evidence.first));
        _evidence.removeAt(0);
      }
      _evidence.add(record);
      added++;
    }
    if (added > 0) _notify();
    return added;
  }

  Future<void> _recover(
    _Mf1EmulationRecoverySession session, {
    bool applyKeys = true,
  }) async {
    if (!_isCurrent(session) || !hasRecoverableReaderKeyEvidence(_evidence)) {
      return;
    }
    final fingerprint = readerKeyEvidenceFingerprint(_evidence);
    if (fingerprint == _lastRecoveryFingerprint) return;

    _recovering = true;
    _notify();
    try {
      final results = await recoverReaderKeys(
        detections: List<DetectionResult>.from(_evidence),
        solver: _solver,
        isCancelled: () => !_isCurrent(session),
      );
      if (!_isCurrent(session)) return;
      final solverFailure = results.where(
        (result) => result.failure == ReaderKeyRecoveryFailure.solverError,
      );
      if (solverFailure.isNotEmpty) {
        throw StateError(
          solverFailure.first.error ?? 'MFKey32 recovery failed',
        );
      }
      final newlyRecovered = <ReaderKeyRecoveryResult>[];
      for (final result in results) {
        final previous = _results[result.target];
        if (result.key != null) {
          if (previous?.key == null ||
              bytesToHex(previous!.key!) == bytesToHex(result.key!)) {
            _results[result.target] = result;
            final applied = _appliedKeys[result.target];
            if (applied != bytesToHex(result.key!)) newlyRecovered.add(result);
          }
        } else if (previous == null) {
          _results[result.target] = result;
        }
      }
      await _persistRecoveredKeys(session);
      if (applyKeys && !_stopping && newlyRecovered.isNotEmpty) {
        await _applyRecoveredKeys(session, newlyRecovered);
      }
      if (_isCurrent(session)) {
        _lastRecoveryFingerprint = fingerprint;
        _error = null;
      }
    } finally {
      if (_isCurrent(session)) {
        _recovering = false;
        _notify();
      }
    }
  }

  Future<void> _persistRecoveredKeys(
    _Mf1EmulationRecoverySession session,
  ) async {
    final byUid = <int, List<Uint8List>>{};
    for (final result in _results.values) {
      final key = result.key;
      if (key == null) continue;
      final identity = '${result.target.uid}:${bytesToHex(key)}';
      if (_savedKeys.contains(identity)) continue;
      byUid.putIfAbsent(result.target.uid, () => []).add(key);
    }
    if (byUid.isEmpty) return;

    final saved = <String>[];
    final dictionaryNames = <String>[];
    for (final entry in byUid.entries) {
      final uid = entry.key.toRadixString(16).padLeft(8, '0').toUpperCase();
      final name = 'hf-emulation-${uid.toLowerCase()}';
      final dictionary = await _preferences.mergeDictionaryKeys(
        dictionaryId: name,
        name: name,
        keys: entry.value,
        keyLength: 12,
        color: _dictionaryColor,
      );
      dictionaryNames.add(dictionary.name);
      for (final key in entry.value) {
        saved.add('${entry.key}:${bytesToHex(key)}');
      }
    }
    if (!_isCurrent(session)) return;
    _savedKeys.addAll(saved);
    _dictionaryNames.addAll(dictionaryNames);
    onKeysSaved?.call();
  }

  Future<void> _applyRecoveredKeys(
    _Mf1EmulationRecoverySession session,
    List<ReaderKeyRecoveryResult> results,
  ) async {
    var changed = false;
    await session.runSlotOperation(() async {
      if (!_isCurrent(session)) return;
      final activeSlot = await session.communicator.getActiveSlot();
      if (activeSlot != session.slot) {
        throw StateError('The active HF slot changed during key recovery');
      }
      for (final result in results) {
        final key = result.key;
        if (key == null ||
            result.target.sector < 0 ||
            result.target.sector >= session.sectorCount) {
          continue;
        }
        final trailerBlock = readerKeySectorTrailerBlock(result.target.sector);
        if (trailerBlock >= session.blockCount) continue;
        final trailer = await session.communicator.mf1GetEmulatorBlock(
          trailerBlock,
          1,
        );
        if (trailer.length != 16) {
          throw const FormatException('Invalid MIFARE Classic trailer');
        }
        _trailerBackups.putIfAbsent(
          trailerBlock,
          () => Uint8List.fromList(trailer),
        );
        final patched = applyReaderKeyToTrailer(
          trailer: trailer,
          key: key,
          keyB: result.target.keyB,
        );
        await session.communicator.setMf1BlockData(trailerBlock, patched);
        _appliedKeys[result.target] = bytesToHex(key);
        changed = true;
      }
    });
    if (!changed || !_isCurrent(session) || !session.reselectSupported) return;
    try {
      await session.communicator.reselectMf1ReaderKeys();
    } catch (error) {
      if (session.communicator.supportsCommandSync(
            ChameleonCommand.mf1ReaderKeysReselect,
          ) !=
          true) {
        session.reselectSupported = false;
      } else {
        rethrow;
      }
    }
  }

  Future<void> _restoreTrailers(_Mf1EmulationRecoverySession session) async {
    if (_trailerBackups.isEmpty) return;
    await session.runSlotOperation(() async {
      final activeSlot = await session.communicator.getActiveSlot();
      if (activeSlot != session.slot) {
        await session.communicator.activateSlot(session.slot);
      }
      final entries = _trailerBackups.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      for (final entry in entries) {
        await session.communicator.setMf1BlockData(
          entry.key,
          Uint8List.fromList(entry.value),
        );
        _trailerBackups.remove(entry.key);
      }
    });
    if (_trailerBackups.isEmpty) _appliedKeys.clear();
  }

  Future<void> _disableCapture(_Mf1EmulationRecoverySession session) async {
    Object? firstError;
    if (session.animationEnabled) {
      try {
        await session.communicator.setMf1ReaderKeysAnim(false);
        session.animationEnabled = false;
      } catch (error) {
        firstError = error;
      }
    }
    if (session.detectionEnabled) {
      try {
        await session.communicator.setMf1DetectionStatus(false);
        session.detectionEnabled = false;
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }

  bool _isCurrent(_Mf1EmulationRecoverySession session) =>
      !_disposed &&
      identical(_session, session) &&
      session.generation == _generation;

  void _clearSessionState() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollOperation = null;
    _deviceCursor = 0;
    _capturedNonceCount = 0;
    _sectorCount = 0;
    _lastRecoveryFingerprint = '';
    _error = null;
    _active = false;
    _recovering = false;
    _stopping = false;
    _evidence.clear();
    _evidenceIds.clear();
    _results.clear();
    _appliedKeys.clear();
    _trailerBackups.clear();
    _savedKeys.clear();
    _dictionaryNames.clear();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }
}

class _Mf1EmulationRecoverySession {
  _Mf1EmulationRecoverySession({
    required this.generation,
    required this.communicator,
    required this.slot,
    required this.sectorCount,
    required this.blockCount,
    required this.runSlotOperation,
    required this.reselectSupported,
  });

  final int generation;
  final ChameleonCommunicator communicator;
  final int slot;
  final int sectorCount;
  final int blockCount;
  final Mf1EmulationSlotOperation runSlotOperation;
  bool reselectSupported;
  bool detectionEnabled = false;
  bool animationEnabled = false;
}

Future<int?> _defaultSolver(recovery.Mfkey32Dart request) async {
  final result = await recovery.mfkey32(request);
  return result.isEmpty ? null : result.first;
}
