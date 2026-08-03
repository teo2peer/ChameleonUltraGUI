import 'dart:async';
import 'dart:ui';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/helpers/hf_capture_controller.dart';
import 'package:chameleonultragui/helpers/hf_sniff.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/reader_key_recovery.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/foundation.dart';

typedef HfCaptureMfkey32Solver =
    Future<int?> Function(recovery.Mfkey32Dart request);
typedef HfCaptureMfkey64Solver =
    Future<int?> Function(recovery.Mfkey64Dart request);

class HfCaptureMifareEvidence {
  const HfCaptureMifareEvidence({
    required this.detection,
    required this.authSequence,
    this.at,
  });

  final DetectionResult detection;
  final int authSequence;
  final int? at;

  ReaderKeyTarget get target => ReaderKeyTarget(
    uid: detection.uid,
    sector: mfClassicGetSectorByBlock(detection.block),
    keyB: detection.type == 0x61,
  );

  String get uidHex => _u32Hex(detection.uid);
  String get ntHex => _u32Hex(detection.nt);
  String get nrHex => _u32Hex(detection.nr);
  String get arHex => _u32Hex(detection.ar);
  String? get atHex => at == null ? null : _u32Hex(at!);

  String get identity =>
      '${readerKeyTranscriptIdentity(detection)}:${at ?? -1}';
}

class HfCaptureRecoveredKey {
  const HfCaptureRecoveredKey({
    required this.target,
    required this.key,
    required this.method,
    this.saved = false,
  });

  final ReaderKeyTarget target;
  final Uint8List key;
  final String method;
  final bool saved;

  String get keyHex => _hex(key);

  HfCaptureRecoveredKey copyWith({bool? saved}) => HfCaptureRecoveredKey(
    target: target,
    key: Uint8List.fromList(key),
    method: method,
    saved: saved ?? this.saved,
  );
}

class HfCaptureMifareParser {
  HfCaptureMifareParser({this.expectedUid});

  final int? expectedUid;
  int? _lastSequence;
  int? _selectedUid;
  _PendingAuthentication? _pending;

  List<HfCaptureMifareEvidence> addRecords(Iterable<HfCaptureRecord> records) {
    final output = <HfCaptureMifareEvidence>[];
    for (final record in records) {
      final previousSequence = _lastSequence;
      if (previousSequence != null &&
          hfCaptureSequenceDistance(previousSequence, record.sequence) != 1) {
        _closePending(output);
        _selectedUid = null;
      }
      _lastSequence = record.sequence;

      if (record.type == HfCaptureRecordType.field) {
        _closePending(output);
        _selectedUid = null;
        continue;
      }
      if (record.hasRfError) {
        _closePending(output);
        continue;
      }

      final frame = record.toSniffFrame();
      if (frame != null) _consumeFrame(frame, record.sequence, output);
    }
    return output;
  }

  List<HfCaptureMifareEvidence> flush() {
    final output = <HfCaptureMifareEvidence>[];
    _closePending(output);
    return output;
  }

  void _consumeFrame(
    HfSniffFrame frame,
    int sequence,
    List<HfCaptureMifareEvidence> output,
  ) {
    final pending = _pending;
    if (pending != null) {
      if (pending.nt == null &&
          frame.isCardToReader &&
          frame.bitLength == 32 &&
          frame.data.length == 4) {
        pending.nt = _bytesToInt(frame.data);
        return;
      }
      if (pending.nt != null &&
          pending.nr == null &&
          frame.isReaderToCard &&
          frame.bitLength == 64 &&
          frame.data.length == 8) {
        pending.nr = _bytesToInt(frame.data.sublist(0, 4));
        pending.ar = _bytesToInt(frame.data.sublist(4, 8));
        return;
      }
      if (pending.nr != null) {
        if (frame.isCardToReader &&
            frame.bitLength == 32 &&
            frame.data.length == 4) {
          output.add(pending.toEvidence(at: _bytesToInt(frame.data)));
          _pending = null;
          return;
        }
        _closePending(output);
      } else {
        _pending = null;
      }
    }

    final data = frame.data;
    if (frame.isReaderToCard &&
        data.length >= 2 &&
        (data[0] == 0x93 || data[0] == 0x95 || data[0] == 0x97) &&
        data[1] == 0x70) {
      _selectedUid = null;
      final validLength =
          (frame.bitLength == 56 && data.length == 7) ||
          (frame.bitLength == 72 && data.length == 9);
      if (!validLength || (data[2] ^ data[3] ^ data[4] ^ data[5]) != data[6]) {
        return;
      }
      if (data[2] != 0x88) {
        _selectedUid = _bytesToInt(data.sublist(2, 6));
      }
      return;
    }

    if (!frame.isReaderToCard ||
        (frame.bitLength != 16 && frame.bitLength != 32) ||
        data.length < 2 ||
        (data[0] != 0x60 && data[0] != 0x61)) {
      return;
    }

    final uid = _selectedUid ?? expectedUid;
    if (uid == null || (expectedUid != null && uid != expectedUid)) return;
    _pending = _PendingAuthentication(
      uid: uid,
      block: data[1],
      type: data[0],
      authSequence: sequence,
    );
  }

  void _closePending(List<HfCaptureMifareEvidence> output) {
    final pending = _pending;
    if (pending != null && pending.nr != null) {
      output.add(pending.toEvidence());
    }
    _pending = null;
  }
}

class _PendingAuthentication {
  _PendingAuthentication({
    required this.uid,
    required this.block,
    required this.type,
    required this.authSequence,
  });

  final int uid;
  final int block;
  final int type;
  final int authSequence;
  int? nt;
  int? nr;
  int? ar;

  HfCaptureMifareEvidence toEvidence({int? at}) => HfCaptureMifareEvidence(
    detection: DetectionResult(
      block: block,
      type: type,
      isNested: false,
      uid: uid,
      nt: nt!,
      nr: nr!,
      ar: ar!,
    ),
    authSequence: authSequence,
    at: at,
  );
}

Future<List<HfCaptureRecoveredKey>> recoverHfCaptureMifareKeys({
  required Iterable<HfCaptureMifareEvidence> evidence,
  required HfCaptureMfkey32Solver mfkey32Solver,
  required HfCaptureMfkey64Solver mfkey64Solver,
  Map<ReaderKeyTarget, HfCaptureRecoveredKey> knownKeys = const {},
}) async {
  final snapshot = List<HfCaptureMifareEvidence>.from(evidence);
  final grouped = <ReaderKeyTarget, List<HfCaptureMifareEvidence>>{};
  for (final item in snapshot) {
    grouped.putIfAbsent(item.target, () => []).add(item);
  }
  final recovered = <ReaderKeyTarget, HfCaptureRecoveredKey>{};

  for (final entry in grouped.entries) {
    if (knownKeys.containsKey(entry.key)) continue;
    for (final item in entry.value.where((candidate) => candidate.at != null)) {
      final raw = await mfkey64Solver(
        recovery.Mfkey64Dart(
          uid: item.detection.uid,
          nt: item.detection.nt,
          nrEnc: item.detection.nr,
          arEnc: item.detection.ar,
          atEnc: item.at!,
        ),
      );
      final key = _mfkeyBytes(raw);
      if (key == null) continue;
      recovered[entry.key] = HfCaptureRecoveredKey(
        target: entry.key,
        key: key,
        method: 'MFKey64',
      );
      break;
    }
  }

  final detections = snapshot.map((item) => item.detection).toList();
  final needsMfkey32 = grouped.keys.any(
    (target) =>
        !knownKeys.containsKey(target) && !recovered.containsKey(target),
  );
  if (needsMfkey32 && hasRecoverableReaderKeyEvidence(detections)) {
    final mfkey32Results = await recoverReaderKeys(
      detections: detections,
      solver: mfkey32Solver,
    );
    final busyResult = mfkey32Results.where(
      (result) =>
          result.failure == ReaderKeyRecoveryFailure.solverError &&
          (result.error?.contains('Another recovery operation') ?? false),
    );
    if (busyResult.isNotEmpty) {
      throw StateError(busyResult.first.error!);
    }
    for (final result in mfkey32Results) {
      if (result.key == null ||
          knownKeys.containsKey(result.target) ||
          recovered.containsKey(result.target)) {
        continue;
      }
      recovered[result.target] = HfCaptureRecoveredKey(
        target: result.target,
        key: Uint8List.fromList(result.key!),
        method: 'MFKey32',
      );
    }
  }

  final output = recovered.values.toList()..sort(_compareRecoveredKeys);
  return List.unmodifiable(output);
}

class HfCaptureMifareRecoveryController extends ChangeNotifier {
  HfCaptureMifareRecoveryController(
    this._preferences,
    this._captureController, {
    this._onKeysSaved,
    HfCaptureMfkey32Solver? mfkey32Solver,
    HfCaptureMfkey64Solver? mfkey64Solver,
    Stream<HfCaptureRecordBatch>? recordBatches,
  }) : _mfkey32Solver = mfkey32Solver ?? _defaultMfkey32Solver,
       _mfkey64Solver = mfkey64Solver ?? _defaultMfkey64Solver,
       _usesInjectedBatches = recordBatches != null {
    _captureController.addListener(_captureStateChanged);
    _batchSubscription =
        (recordBatches ?? _captureController.persistedRecordBatches).listen(
          _acceptBatch,
          onError: (Object error, StackTrace stackTrace) {
            _error = error.toString();
            _notify();
          },
        );
  }

  static const _maxEvidencePerTarget = 32;
  static const _maxEvidence = 2048;
  static const _dictionaryColor = Color(0xFF1565C0);

  final SharedPreferencesProvider _preferences;
  final HfCaptureController _captureController;
  final VoidCallback? _onKeysSaved;
  final HfCaptureMfkey32Solver _mfkey32Solver;
  final HfCaptureMfkey64Solver _mfkey64Solver;
  final bool _usesInjectedBatches;
  late final StreamSubscription<HfCaptureRecordBatch> _batchSubscription;

  HfCaptureMifareParser _parser = HfCaptureMifareParser();
  final List<HfCaptureMifareEvidence> _evidence = [];
  final Set<String> _evidenceIds = {};
  final Map<ReaderKeyTarget, HfCaptureRecoveredKey> _recovered = {};
  final Map<int, String> _dictionaryNames = {};
  String? _sessionIdentity;
  int? _preparedExpectedUid;
  String _lastRecoveryFingerprint = '';
  String? _error;
  bool _recovering = false;
  bool _recoveryPending = false;
  bool _disposed = false;
  int _lastBatchPageIndex = -1;
  int _solverRetryCount = 0;
  int _saveRetryCount = 0;
  Timer? _recoveryTimer;
  Timer? _flushTimer;

  List<HfCaptureMifareEvidence> get evidence => List.unmodifiable(_evidence);

  List<HfCaptureRecoveredKey> get recoveredKeys {
    final output = _recovered.values.toList()..sort(_compareRecoveredKeys);
    return List.unmodifiable(output);
  }

  List<String> get dictionaryNames {
    final output = _dictionaryNames.values.toSet().toList()..sort();
    return List.unmodifiable(output);
  }

  bool get isRecovering => _recovering;
  String? get error => _error;
  int get targetCount =>
      groupReaderKeyRecords(_evidence.map((item) => item.detection)).length;
  int get savedKeyCount => _recovered.values
      .where((result) => result.saved)
      .map((result) => result.keyHex)
      .toSet()
      .length;

  void prepareForCapture({CardData? expectedCard}) {
    _preparedExpectedUid = expectedCard == null
        ? null
        : _cardCryptoUid(expectedCard.uid);
  }

  void retry() {
    if (_disposed || (!_hasRecoverableEvidence && _recovered.isEmpty)) return;
    _solverRetryCount = 0;
    _saveRetryCount = 0;
    _lastRecoveryFingerprint = '';
    _error = null;
    _scheduleRecovery(Duration.zero);
    _notify();
  }

  void _captureStateChanged() {
    if (!_captureController.isConnected) {
      if (_sessionIdentity != null) _clearSession();
      return;
    }
    final metadata = _captureController.metadata;
    if (metadata == null) {
      if (_sessionIdentity != null) _clearSession();
      return;
    }
    final identity = _metadataIdentity(metadata);
    if (_sessionIdentity != identity) _beginSession(identity);
    if (!metadata.isRunning && metadata.storedRecords == 0) {
      _flushTimer?.cancel();
      _flushTimer = Timer(Duration.zero, () {
        if (_disposed || _captureController.isRunning) return;
        _ingest(_parser.flush());
      });
    }
  }

  void _acceptBatch(HfCaptureRecordBatch batch) {
    if (_disposed) return;
    if (!_usesInjectedBatches &&
        (!_captureController.isConnected ||
            batch.connectionGeneration !=
                _captureController.connectionGeneration)) {
      return;
    }
    if (_sessionIdentity != batch.sessionIdentity) {
      _beginSession(batch.sessionIdentity);
    }
    if (batch.pageIndex <= _lastBatchPageIndex) return;
    _lastBatchPageIndex = batch.pageIndex;
    try {
      _ingest(_parser.addRecords(batch.records));
    } catch (error) {
      _error = error.toString();
      _notify();
    }
  }

  void _beginSession(String identity) {
    _recoveryTimer?.cancel();
    _flushTimer?.cancel();
    _sessionIdentity = identity;
    _parser = HfCaptureMifareParser(expectedUid: _preparedExpectedUid);
    _preparedExpectedUid = null;
    _evidence.clear();
    _evidenceIds.clear();
    _recovered.clear();
    _dictionaryNames.clear();
    _lastRecoveryFingerprint = '';
    _error = null;
    _recoveryPending = false;
    _lastBatchPageIndex = -1;
    _solverRetryCount = 0;
    _saveRetryCount = 0;
    _notify();
  }

  void _clearSession() {
    _recoveryTimer?.cancel();
    _flushTimer?.cancel();
    _sessionIdentity = null;
    _preparedExpectedUid = null;
    _parser = HfCaptureMifareParser();
    _evidence.clear();
    _evidenceIds.clear();
    _recovered.clear();
    _dictionaryNames.clear();
    _lastRecoveryFingerprint = '';
    _error = null;
    _recoveryPending = false;
    _lastBatchPageIndex = -1;
    _solverRetryCount = 0;
    _saveRetryCount = 0;
    _notify();
  }

  void _ingest(Iterable<HfCaptureMifareEvidence> incoming) {
    var changed = false;
    for (final item in incoming) {
      if (_evidenceIds.contains(item.identity)) continue;
      while (_evidence
              .where((existing) => existing.target == item.target)
              .length >=
          _maxEvidencePerTarget) {
        final index = _evidence.indexWhere(
          (existing) => existing.target == item.target,
        );
        _evidenceIds.remove(_evidence[index].identity);
        _evidence.removeAt(index);
      }
      if (_evidence.length >= _maxEvidence) {
        _evidenceIds.remove(_evidence.first.identity);
        _evidence.removeAt(0);
      }
      _evidence.add(item);
      _evidenceIds.add(item.identity);
      changed = true;
    }
    if (!changed) return;
    _solverRetryCount = 0;
    _saveRetryCount = 0;
    _notify();
    if (_hasRecoverableEvidence) _scheduleRecovery();
  }

  bool get _hasRecoverableEvidence =>
      _evidence.any((item) => item.at != null) ||
      hasRecoverableReaderKeyEvidence(_evidence.map((item) => item.detection));

  void _scheduleRecovery([Duration delay = const Duration(milliseconds: 200)]) {
    if (_disposed) return;
    _recoveryPending = true;
    if (_recovering) return;
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(delay, () => unawaited(_drainRecovery()));
  }

  Future<void> _drainRecovery() async {
    if (_disposed || _recovering) return;
    _recoveryTimer = null;
    _recovering = true;
    _error = null;
    _notify();
    try {
      while (_recoveryPending && !_disposed) {
        _recoveryPending = false;
        final sessionIdentity = _sessionIdentity;
        if (sessionIdentity == null) continue;
        final fingerprint = _evidence.map((item) => item.identity).join('|');
        if (fingerprint != _lastRecoveryFingerprint) {
          try {
            final recovered = await recoverHfCaptureMifareKeys(
              evidence: _evidence,
              knownKeys: _recovered,
              mfkey32Solver: _mfkey32Solver,
              mfkey64Solver: _mfkey64Solver,
            );
            if (_disposed || sessionIdentity != _sessionIdentity) continue;
            for (final result in recovered) {
              _recovered[result.target] = result;
            }
            _lastRecoveryFingerprint = fingerprint;
            _solverRetryCount = 0;
          } catch (error) {
            if (_isRecoveryWorkerBusy(error)) {
              _scheduleDelayedRecovery(const Duration(seconds: 1));
            } else {
              _error = error.toString();
              if (++_solverRetryCount <= 3) {
                _scheduleDelayedRecovery(const Duration(seconds: 2));
              } else {
                _lastRecoveryFingerprint = fingerprint;
              }
            }
            continue;
          }
        }

        if (_recovered.values.any((result) => !result.saved)) {
          try {
            await _persistRecoveredKeys(sessionIdentity);
            _saveRetryCount = 0;
          } catch (error) {
            _error = error.toString();
            if (++_saveRetryCount <= 3) {
              _scheduleDelayedRecovery(const Duration(seconds: 2));
            }
          }
        }
        _notify();
      }
    } finally {
      _recovering = false;
      _notify();
    }
  }

  void _scheduleDelayedRecovery(Duration delay) {
    if (_disposed) return;
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(delay, () {
      if (_disposed) return;
      _recoveryPending = true;
      unawaited(_drainRecovery());
    });
  }

  Future<void> _persistRecoveredKeys(String sessionIdentity) async {
    final snapshot = Map<ReaderKeyTarget, HfCaptureRecoveredKey>.from(
      _recovered,
    );
    final unsaved = snapshot.values.where((result) => !result.saved).toList();
    if (unsaved.isEmpty) return;
    final byUid = <int, List<HfCaptureRecoveredKey>>{};
    final persistedNames = <int, String>{};
    for (final result in snapshot.values) {
      byUid.putIfAbsent(result.target.uid, () => []).add(result);
    }

    for (final entry in byUid.entries) {
      final uidHex = _u32Hex(entry.key);
      final name = 'hf-capture-${uidHex.toLowerCase()}';
      final dictionary = await _preferences.mergeDictionaryKeys(
        dictionaryId: name,
        name: name,
        keys: entry.value.map((result) => result.key),
        keyLength: 12,
        color: _dictionaryColor,
      );
      persistedNames[entry.key] = dictionary.name;
    }

    if (_disposed || sessionIdentity != _sessionIdentity) return;
    _dictionaryNames.addAll(persistedNames);
    for (final entry in snapshot.entries) {
      final current = _recovered[entry.key];
      if (current != null && current.keyHex == entry.value.keyHex) {
        _recovered[entry.key] = current.copyWith(saved: true);
      }
    }
    _onKeysSaved?.call();
  }

  bool _isRecoveryWorkerBusy(Object error) => error.toString().contains(
    'Another recovery operation is already in progress',
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _recoveryTimer?.cancel();
    _flushTimer?.cancel();
    _captureController.removeListener(_captureStateChanged);
    unawaited(_batchSubscription.cancel());
    super.dispose();
  }
}

Future<int?> _defaultMfkey32Solver(recovery.Mfkey32Dart request) async {
  final result = await recovery.mfkey32(request);
  return result.isEmpty ? null : result.first;
}

Future<int?> _defaultMfkey64Solver(recovery.Mfkey64Dart request) async {
  final result = await recovery.mfkey64(request);
  return result.isEmpty ? null : result.first;
}

Uint8List? _mfkeyBytes(int? raw) {
  if (raw == null || raw == mfkey32NoKey) return null;
  final value = raw & 0xFFFFFFFFFFFF;
  return Uint8List.fromList([
    for (var shift = 40; shift >= 0; shift -= 8) (value >> shift) & 0xFF,
  ]);
}

int _cardCryptoUid(Uint8List uid) {
  if (uid.length < 4) throw const FormatException('Invalid MIFARE Classic UID');
  return _bytesToInt(uid.sublist(uid.length - 4));
}

String _metadataIdentity(HfCaptureMetadata metadata) =>
    '${metadata.bootId}:${metadata.sessionId}:${metadata.startToken}';

int _bytesToInt(List<int> bytes) {
  var value = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
  }
  return value;
}

String _hex(Uint8List bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

String _u32Hex(int value) =>
    value.toRadixString(16).padLeft(8, '0').toUpperCase();

int _compareRecoveredKeys(
  HfCaptureRecoveredKey left,
  HfCaptureRecoveredKey right,
) {
  final uid = left.target.uid.compareTo(right.target.uid);
  if (uid != 0) return uid;
  final sector = left.target.sector.compareTo(right.target.sector);
  if (sector != 0) return sector;
  return left.target.keyB == right.target.keyB
      ? 0
      : left.target.keyB
      ? 1
      : -1;
}
