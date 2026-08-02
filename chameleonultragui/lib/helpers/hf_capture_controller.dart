import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef HfCaptureDirectoryProvider = Future<Directory> Function();

class _IncompleteCapture {
  const _IncompleteCapture({
    required this.session,
    required this.sessionId,
    required this.bootId,
    required this.startToken,
    required this.mode,
    required this.startedAt,
    required this.reason,
    required this.pendingManifest,
  });

  final Directory session;
  final int? sessionId;
  final int? bootId;
  final int startToken;
  final int mode;
  final DateTime startedAt;
  final String reason;
  final bool pendingManifest;
}

class HfCaptureController extends ChangeNotifier {
  HfCaptureController(
    this._preferences, {
    HfCaptureDirectoryProvider? directoryProvider,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  static const _activeManifestVersion = 2;
  static const _pendingManifestVersion = 2;
  static const _sessionSummaryName = 'summary.json';
  static const _recentRecordLimit = 300;
  static final _pageNamePattern = RegExp(
    r'^(\d{10})-(\d{10})-(\d{10})-([0-9a-f]{8})\.hfcap$',
  );

  final SharedPreferencesProvider _preferences;
  final HfCaptureDirectoryProvider _directoryProvider;

  ChameleonCommunicator? _communicator;
  StreamSubscription<ChameleonMessage>? _eventSubscription;
  Timer? _pollTimer;
  Completer<void>? _drainCompleter;
  Completer<void>? _operationCompleter;
  Directory? _rootDirectory;
  Directory? _sessionDirectory;
  int? _lastPersistedSequence;
  int? _lastPersistedDeliveryToken;
  int _sequenceGapEvidence = 0;
  int _nextPageIndex = 0;
  int _connectionGeneration = 0;
  bool _disposed = false;
  bool _busy = false;
  bool _needsFinalize = false;
  bool _sessionFinalized = false;
  bool _resumeBlocked = false;
  bool? _supported;
  int _persistedBytes = 0;
  DateTime? _startedAt;
  String? _deviceId;
  String? _error;
  HfCaptureMetadata? _metadata;
  _IncompleteCapture? _incompleteCapture;
  CardData? _lastReaderCard;
  final List<HfCaptureRecord> _recentRecords = [];

  bool get isBusy => _busy;
  bool? get isSupported => _supported;
  bool get isConnected => _communicator != null;
  bool get hasSession => _metadata != null;
  bool get isRunning => _metadata?.isRunning ?? false;
  bool get needsDrain => (_metadata?.storedRecords ?? 0) > 0;
  bool get needsFinalize => _needsFinalize;
  bool get canStart =>
      !_resumeBlocked && !isRunning && !needsDrain && !needsFinalize;
  int get persistedBytes => _persistedBytes;
  DateTime? get startedAt => _startedAt;
  String? get error => _error;
  String? get captureDirectory => _sessionDirectory?.path;
  HfCaptureMetadata? get metadata => _metadata;
  CardData? get lastReaderCard => _lastReaderCard;
  List<HfCaptureRecord> get recentRecords => List.unmodifiable(_recentRecords);

  Future<void> attach(ChameleonCommunicator communicator) async {
    if (_disposed) return;
    final generation = ++_connectionGeneration;
    await _eventSubscription?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    _communicator = communicator;
    try {
      await _waitForOperation();
      if (!_connectionMatches(communicator, generation)) return;
      await _waitForDrain();
      if (!_connectionMatches(communicator, generation)) return;
      _pollTimer?.cancel();
      _pollTimer = null;
      _supported = communicator.supportsCommandSync(
        ChameleonCommand.hfCaptureStart,
      );
      _resetSessionState();
      _deviceId = null;
      _eventSubscription = communicator.unsolicitedMessages.listen(
        _onUnsolicitedMessage,
        onError: (Object error, StackTrace stackTrace) => _setError(error),
      );
      await _prepareStorage();
      if (_supported != false) {
        final deviceId = _normalizeDeviceId(
          await communicator.getDeviceChipID(),
        );
        if (!_connectionMatches(communicator, generation)) return;
        _deviceId = deviceId;
        await _resumeActiveSession(communicator, generation);
      }
      _notify();
    } catch (error) {
      if (_connectionMatches(communicator, generation)) {
        _connectionGeneration++;
        _communicator = null;
        _pollTimer?.cancel();
        _pollTimer = null;
        await _eventSubscription?.cancel();
        _eventSubscription = null;
        _supported = null;
        _deviceId = null;
        _resetSessionState();
        _error = 'Unable to attach HF capture state: $error';
        _notify();
      }
      rethrow;
    }
  }

  void detach(ChameleonCommunicator communicator) {
    if (!identical(_communicator, communicator)) return;
    _connectionGeneration++;
    _communicator = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    _notify();
  }

  Future<void> start(HfCaptureMode mode) async {
    final communicator = _requireCommunicator();
    final generation = _connectionGeneration;
    if (_busy) return;
    if (!canStart) {
      throw StateError(
        _resumeBlocked
            ? 'The previous HF capture cannot be resumed safely'
            : 'The previous HF capture must stop and drain first',
      );
    }
    _beginOperation();
    _error = null;
    _notify();
    Directory? session;
    HfCaptureMetadata? started;
    try {
      await _waitForDrain();
      if (!_connectionMatches(communicator, generation)) {
        throw StateError('HF capture connection changed before START');
      }
      if (!canStart) {
        throw StateError(
          'The previous HF capture is no longer ready for START',
        );
      }
      if (_metadata != null) await _finishSession();
      final root = await _prepareStorage();
      final timestamp = DateTime.now().toUtc();
      final startToken = _newStartToken();
      session = await _prepareNewSessionStorage(root, timestamp);
      await _writePendingManifest(
        session,
        timestamp,
        mode,
        startToken,
        communicator.connectionType?.name,
      );
      try {
        started = await communicator.hfCaptureStart(
          mode,
          startToken: startToken,
        );
      } catch (error) {
        if (!_isUncertainStartError(error) ||
            !_connectionMatches(communicator, generation)) {
          if (_isUncertainStartError(error)) _resumeBlocked = true;
          rethrow;
        }
        try {
          final recovered = await communicator.hfCaptureStatus(
            0,
            startToken: startToken,
          );
          if (recovered.mode != mode || recovered.startToken != startToken) {
            throw const FormatException(
              'Recovered HF capture mode does not match START',
            );
          }
          started = recovered;
        } catch (recoveryError) {
          final startWasNotProcessed =
              recoveryError is ChameleonCommandException &&
              recoveryError.status == 0x75;
          if (startWasNotProcessed) throw error;
          _resumeBlocked = true;
          throw StateError(
            'HF capture START is uncertain: $error; recovery failed: $recoveryError',
          );
        }
      }
      _sessionDirectory = session;
      _metadata = started;
      _sessionFinalized = false;
      _startedAt = timestamp;
      _lastPersistedSequence = null;
      _lastPersistedDeliveryToken = null;
      _sequenceGapEvidence = 0;
      _nextPageIndex = 0;
      _persistedBytes = 0;
      _resumeBlocked = false;
      _recentRecords.clear();
      _lastReaderCard = null;
      await _writeActiveManifest();
      try {
        await _clearPendingManifest();
      } catch (_) {}
      if (!_connectionMatches(communicator, generation)) {
        throw StateError('HF capture connection changed during START');
      }
      if (started.isRunning || started.storedRecords > 0) {
        _schedulePoll(Duration.zero);
      } else {
        await _finishSession();
      }
    } catch (error) {
      Object? cleanupError;
      if (started == null &&
          !_resumeBlocked &&
          session != null &&
          await session.exists()) {
        try {
          await _clearPendingManifest();
          await session.delete(recursive: true);
        } catch (failure) {
          cleanupError = failure;
        }
      } else if (started != null &&
          _connectionMatches(communicator, generation)) {
        try {
          _metadata = await communicator.hfCaptureStop(started.sessionId);
          await _drain(maxPages: 4096);
        } catch (failure) {
          cleanupError = failure;
          _resumeBlocked = true;
        }
      } else if (started != null) {
        _resumeBlocked = true;
      }
      final reported = cleanupError == null
          ? error
          : StateError(
              'HF capture START failed: $error; cleanup also failed: $cleanupError',
            );
      _setError(reported);
      if (cleanupError != null) throw reported;
      rethrow;
    } finally {
      _endOperation();
      if (isRunning || needsDrain) {
        _schedulePoll(const Duration(milliseconds: 500));
      }
      _notify();
    }
  }

  bool _isUncertainStartError(Object error) =>
      error is! ChameleonCommandException &&
      error is! ChameleonUnsupportedCommandException;

  Future<void> stop() async {
    final communicator = _requireCommunicator();
    final generation = _connectionGeneration;
    final sessionId = _metadata?.sessionId;
    if (sessionId == null || _busy) return;
    _beginOperation();
    _pollTimer?.cancel();
    _pollTimer = null;
    _error = null;
    _notify();
    try {
      await _waitForDrain();
      final stopped = await communicator.hfCaptureStop(sessionId);
      if (!_connectionMatches(communicator, generation)) {
        throw StateError('HF capture connection changed during STOP');
      }
      _metadata = stopped;
      await _drain(maxPages: 4096);
      if ((_metadata?.storedRecords ?? 0) != 0) {
        throw StateError('HF capture did not drain all retained records');
      }
      await _finishSession();
    } catch (error) {
      _setError(error);
      rethrow;
    } finally {
      _endOperation();
      if (isRunning || needsDrain) {
        _schedulePoll(const Duration(milliseconds: 500));
      }
      _notify();
    }
  }

  Future<void> retryDrain() async {
    if (_busy) return;
    if (isRunning || (!needsDrain && !needsFinalize)) {
      throw StateError(
        'Retry requires a stopped capture with unread data or pending finalization',
      );
    }
    if (needsDrain) _requireCommunicator();
    _beginOperation();
    _error = null;
    _notify();
    try {
      await _waitForDrain();
      final incompleteCapture = _incompleteCapture;
      if (incompleteCapture != null) {
        await _archiveIncompleteCapture(incompleteCapture);
        return;
      }
      if (needsDrain) await _drain(maxPages: 4096);
      if ((_metadata?.storedRecords ?? 0) != 0) {
        throw StateError('HF capture still has unread records');
      }
      await _finishSession();
    } catch (error) {
      _setError(error);
      rethrow;
    } finally {
      _endOperation();
      _notify();
    }
  }

  Future<void> probeReader() async {
    final communicator = _requireCommunicator();
    final generation = _connectionGeneration;
    if (_metadata?.mode != HfCaptureMode.reader || !isRunning) {
      throw StateError('Reader probing requires an active reader-mode capture');
    }
    if (_busy) return;
    _beginOperation();
    _pollTimer?.cancel();
    _pollTimer = null;
    _error = null;
    _notify();
    try {
      await _waitForDrain();
      _lastReaderCard = await communicator.scan14443aTag();
      if (!_connectionMatches(communicator, generation)) return;
      await _drain();
    } catch (error) {
      _setError(error);
      rethrow;
    } finally {
      _endOperation();
      _schedulePoll(const Duration(milliseconds: 500));
      _notify();
    }
  }

  void clearError() {
    _error = null;
    _notify();
  }

  Future<Directory> _prepareStorage() async {
    final existing = _rootDirectory;
    if (existing != null) {
      await _removeExpiredSessions(existing);
      return existing;
    }
    final documents = await _directoryProvider();
    final root = Directory(path.join(documents.path, 'hf-captures'));
    await root.create(recursive: true);
    _rootDirectory = root;
    await _removeExpiredSessions(root);
    return root;
  }

  Future<void> applyRetention() async {
    final root = await _prepareStorage();
    await _removeExpiredSessions(root);
  }

  Future<Directory> _prepareNewSessionStorage(
    Directory root,
    DateTime timestamp,
  ) async {
    final deviceId = _deviceId!;
    final deviceSuffix = deviceId.length <= 16
        ? deviceId
        : deviceId.substring(0, 16);
    final baseName =
        'session-${timestamp.toIso8601String().replaceAll(':', '-')}'
        '-$deviceSuffix';
    var suffix = 0;
    late Directory session;
    do {
      session = Directory(
        path.join(root.path, suffix == 0 ? baseName : '$baseName-$suffix'),
      );
      suffix++;
    } while (await session.exists());

    try {
      final pages = Directory(path.join(session.path, 'pages'));
      await pages.create(recursive: true);
      final pageProbe = File(path.join(pages.path, '.write-test'));
      await pageProbe.writeAsBytes([hfCaptureProtocolVersion], flush: true);
      await pageProbe.delete();
      final manifestProbe = File(
        path.join(
          root.path,
          '.${path.basename(_activeManifestFile().path)}.tmp',
        ),
      );
      await manifestProbe.writeAsString('{}', flush: true);
      await manifestProbe.delete();
      return session;
    } catch (_) {
      if (await session.exists()) await session.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _removeExpiredSessions(Directory root) async {
    final cutoff = DateTime.now().subtract(
      Duration(days: _preferences.getHfCaptureRetentionDays()),
    );
    final activeNames = <String>{};
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File ||
          !RegExp(
            r'^(active|pending)-[0-9a-f]+\.json$',
          ).hasMatch(path.basename(entity.path))) {
        continue;
      }
      try {
        final value = jsonDecode(await entity.readAsString());
        if (value is Map && value['directory'] is String) {
          activeNames.add(value['directory'] as String);
        }
      } catch (_) {}
    }
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          activeNames.contains(path.basename(entity.path))) {
        continue;
      }
      final completedAt = await _sessionCompletedAt(entity);
      if (completedAt != null && completedAt.isBefore(cutoff)) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<DateTime?> _sessionCompletedAt(Directory session) async {
    final manifest = File(path.join(session.path, _sessionSummaryName));
    if (!await manifest.exists()) return null;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is Map<String, dynamic> && decoded['endedAt'] is String) {
        return DateTime.tryParse(decoded['endedAt'] as String);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _resumeActiveSession(
    ChameleonCommunicator communicator,
    int generation,
  ) async {
    final root = _rootDirectory!;
    final activeFile = _activeManifestFile();
    if (!await activeFile.exists()) {
      if (await _pendingManifestFile().exists()) {
        await _resumePendingSession(communicator, generation);
      }
      return;
    }

    late int sessionId;
    late int bootId;
    late int startToken;
    late int mode;
    late String directoryName;
    late DateTime startedAt;
    try {
      final decoded = jsonDecode(await activeFile.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 8 ||
          decoded['version'] != _activeManifestVersion ||
          decoded['deviceId'] != _deviceId ||
          decoded['sessionId'] is! int ||
          decoded['bootId'] is! int ||
          decoded['startToken'] is! int ||
          decoded['mode'] is! int ||
          decoded['directory'] is! String ||
          decoded['startedAt'] is! String) {
        throw const FormatException('Invalid active HF capture manifest');
      }
      sessionId = decoded['sessionId'] as int;
      bootId = decoded['bootId'] as int;
      startToken = decoded['startToken'] as int;
      mode = decoded['mode'] as int;
      directoryName = decoded['directory'] as String;
      final parsedStartedAt = DateTime.tryParse(decoded['startedAt'] as String);
      if (sessionId <= 0 ||
          bootId <= 0 ||
          startToken <= 0 ||
          startToken > 0xFFFFFFFF ||
          mode < 0 ||
          mode >= HfCaptureMode.values.length ||
          path.basename(directoryName) != directoryName ||
          parsedStartedAt == null) {
        throw const FormatException('Invalid active HF capture manifest');
      }
      startedAt = parsedStartedAt;
    } catch (error) {
      _resumeBlocked = true;
      _setError('Unable to read the previous HF capture manifest: $error');
      return;
    }

    final session = Directory(path.join(root.path, directoryName));
    if (!await session.exists()) {
      _resumeBlocked = true;
      _setError('The previous HF capture session directory is missing');
      return;
    }

    late HfCaptureMetadata metadata;
    try {
      metadata = await communicator.hfCaptureStatus(
        sessionId,
        startToken: startToken,
      );
    } catch (error) {
      final sessionIsGone =
          error is ChameleonUnsupportedCommandException ||
          (error is ChameleonCommandException && error.status == 0x75);
      if (sessionIsGone) {
        final incomplete = _IncompleteCapture(
          session: session,
          sessionId: sessionId,
          bootId: bootId,
          startToken: startToken,
          mode: mode,
          startedAt: startedAt,
          reason: 'device-session-unavailable',
          pendingManifest: false,
        );
        try {
          await _archiveIncompleteCapture(incomplete);
        } catch (archiveError) {
          _incompleteCapture = incomplete;
          _needsFinalize = true;
          _resumeBlocked = true;
          _setError(
            'Unable to archive the incomplete HF capture: $archiveError',
          );
          return;
        }
      } else {
        _resumeBlocked = true;
      }
      _setError('Unable to resume the previous HF capture: $error');
      return;
    }
    if (!_connectionMatches(communicator, generation)) return;
    if (metadata.bootId != bootId ||
        metadata.startToken != startToken ||
        metadata.mode.value != mode) {
      final incomplete = _IncompleteCapture(
        session: session,
        sessionId: sessionId,
        bootId: bootId,
        startToken: startToken,
        mode: mode,
        startedAt: startedAt,
        reason: 'device-session-identity-changed',
        pendingManifest: false,
      );
      try {
        await _archiveIncompleteCapture(incomplete);
      } catch (archiveError) {
        _incompleteCapture = incomplete;
        _needsFinalize = true;
        _resumeBlocked = true;
        _setError('Unable to archive the incomplete HF capture: $archiveError');
        return;
      }
      _setError('The retained HF capture no longer matches this device boot');
      return;
    }

    try {
      final persisted = await _readPersistedCheckpoint(
        session,
        sessionId: sessionId,
        bootId: bootId,
        startToken: startToken,
        mode: HfCaptureMode.values[mode],
      );
      if (!_connectionMatches(communicator, generation)) return;
      _sessionDirectory = session;
      _lastPersistedSequence = persisted.$1;
      _lastPersistedDeliveryToken = persisted.$2;
      _persistedBytes = persisted.$3;
      _nextPageIndex = persisted.$4;
      _sequenceGapEvidence = persisted.$5;
      _metadata = metadata;
      _sessionFinalized = false;
      _startedAt = startedAt.toLocal();
      _resumeBlocked = false;
      _error = null;
      if (metadata.isRunning) {
        _schedulePoll(Duration.zero);
      } else {
        await _drain(maxPages: 4096);
        if ((_metadata?.storedRecords ?? 0) != 0) {
          throw StateError('Stopped HF capture still has unread records');
        }
        await _finishSession();
      }
    } catch (error) {
      if (_needsFinalize) {
        _setError('Unable to finalize the recovered HF capture: $error');
        return;
      }
      _resetSessionState();
      _sessionDirectory = session;
      _resumeBlocked = true;
      if (metadata.isRunning && _connectionMatches(communicator, generation)) {
        try {
          await communicator.hfCaptureStop(sessionId);
        } catch (_) {}
      }
      _setError(
        'Unable to validate the previous HF capture before ACK: $error',
      );
    }
  }

  Future<void> _resumePendingSession(
    ChameleonCommunicator communicator,
    int generation,
  ) async {
    final pendingFile = _pendingManifestFile();
    late int mode;
    late int startToken;
    late String transport;
    late String directoryName;
    late DateTime startedAt;
    try {
      final decoded = jsonDecode(await pendingFile.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 7 ||
          decoded['version'] != _pendingManifestVersion ||
          decoded['deviceId'] != _deviceId ||
          decoded['startToken'] is! int ||
          decoded['transport'] is! String ||
          decoded['mode'] is! int ||
          decoded['directory'] is! String ||
          decoded['startedAt'] is! String) {
        throw const FormatException('Invalid pending HF capture manifest');
      }
      mode = decoded['mode'] as int;
      startToken = decoded['startToken'] as int;
      transport = decoded['transport'] as String;
      directoryName = decoded['directory'] as String;
      final parsedStartedAt = DateTime.tryParse(decoded['startedAt'] as String);
      if (mode < 0 ||
          mode >= HfCaptureMode.values.length ||
          startToken <= 0 ||
          startToken > 0xFFFFFFFF ||
          !const {'usb', 'ble'}.contains(transport) ||
          path.basename(directoryName) != directoryName ||
          parsedStartedAt == null) {
        throw const FormatException('Invalid pending HF capture manifest');
      }
      startedAt = parsedStartedAt;
    } catch (error) {
      _resumeBlocked = true;
      _setError('Unable to read uncertain HF capture state: $error');
      return;
    }

    final session = Directory(path.join(_rootDirectory!.path, directoryName));
    if (!await session.exists()) {
      _resumeBlocked = true;
      _setError('The uncertain HF capture session directory is missing');
      return;
    }
    if (communicator.connectionType?.name != transport) {
      _resumeBlocked = true;
      _setError(
        'Uncertain HF capture must reconnect over $transport before recovery',
      );
      return;
    }

    late HfCaptureMetadata metadata;
    try {
      metadata = await communicator.hfCaptureStatus(0, startToken: startToken);
    } catch (error) {
      final sessionIsGone =
          error is ChameleonCommandException && error.status == 0x75;
      if (sessionIsGone) {
        final incomplete = _IncompleteCapture(
          session: session,
          sessionId: null,
          bootId: null,
          startToken: startToken,
          mode: mode,
          startedAt: startedAt,
          reason: 'uncertain-start-not-processed',
          pendingManifest: true,
        );
        try {
          await _archiveIncompleteCapture(incomplete);
        } catch (archiveError) {
          _incompleteCapture = incomplete;
          _needsFinalize = true;
          _resumeBlocked = true;
          _setError(
            'Unable to archive the uncertain HF capture: $archiveError',
          );
          return;
        }
      } else {
        _resumeBlocked = true;
      }
      _setError('Unable to recover uncertain HF capture state: $error');
      return;
    }
    if (!_connectionMatches(communicator, generation)) return;
    if (metadata.mode.value != mode || metadata.startToken != startToken) {
      _resumeBlocked = true;
      _setError('Recovered HF capture mode does not match pending START');
      return;
    }

    try {
      final persisted = await _readPersistedCheckpoint(
        session,
        sessionId: metadata.sessionId,
        bootId: metadata.bootId,
        startToken: startToken,
        mode: metadata.mode,
      );
      if (!_connectionMatches(communicator, generation)) return;
      _sessionDirectory = session;
      _lastPersistedSequence = persisted.$1;
      _lastPersistedDeliveryToken = persisted.$2;
      _persistedBytes = persisted.$3;
      _nextPageIndex = persisted.$4;
      _sequenceGapEvidence = persisted.$5;
      _metadata = metadata;
      _sessionFinalized = false;
      _startedAt = startedAt.toLocal();
      _resumeBlocked = false;
      _error = null;
      await _writeActiveManifest();
      try {
        await _clearPendingManifest();
      } catch (_) {}
      if (metadata.isRunning) {
        _schedulePoll(Duration.zero);
      } else {
        await _drain(maxPages: 4096);
        if ((_metadata?.storedRecords ?? 0) != 0) {
          throw StateError('Stopped HF capture still has unread records');
        }
        await _finishSession();
      }
    } catch (error) {
      if (_needsFinalize) {
        _setError('Unable to finalize the recovered HF capture: $error');
        return;
      }
      _resetSessionState();
      _sessionDirectory = session;
      _resumeBlocked = true;
      if (metadata.isRunning && _connectionMatches(communicator, generation)) {
        try {
          await communicator.hfCaptureStop(metadata.sessionId);
        } catch (_) {}
      }
      _setError('Unable to validate recovered HF capture before ACK: $error');
    }
  }

  Future<(int?, int?, int, int, int)> _readPersistedCheckpoint(
    Directory session, {
    required int sessionId,
    required int bootId,
    required int startToken,
    required HfCaptureMode mode,
  }) async {
    final pages = Directory(path.join(session.path, 'pages'));
    if (!await pages.exists()) {
      throw const FormatException('HF capture pages directory is missing');
    }
    final entries = <({int index, int first, int last, int crc, File file})>[];
    await for (final entity in pages.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      if (name.endsWith('.hfcap.tmp')) {
        await entity.delete();
        continue;
      }
      if (!name.endsWith('.hfcap')) continue;
      final match = _pageNamePattern.firstMatch(name);
      if (match == null) {
        throw const FormatException('Invalid HF capture page filename');
      }
      entries.add((
        index: int.parse(match.group(1)!),
        first: int.parse(match.group(2)!),
        last: int.parse(match.group(3)!),
        crc: int.parse(match.group(4)!, radix: 16),
        file: entity,
      ));
    }
    entries.sort((left, right) => left.index.compareTo(right.index));

    int? previousSequence;
    int? lastDeliveryToken;
    var missingRecords = 0;
    var persistedBytes = 0;
    for (
      var expectedIndex = 0;
      expectedIndex < entries.length;
      expectedIndex++
    ) {
      final entry = entries[expectedIndex];
      if (entry.index != expectedIndex) {
        throw const FormatException('Missing HF capture persisted page');
      }
      final bytes = await entry.file.readAsBytes();
      if (hfCaptureCrc32(bytes) != entry.crc) {
        throw const FormatException('Persisted HF capture page CRC mismatch');
      }
      final page = HfCapturePage.decode(bytes);
      if (page.records.isEmpty ||
          page.metadata.sessionId != sessionId ||
          page.metadata.bootId != bootId ||
          page.metadata.startToken != startToken ||
          page.metadata.mode != mode ||
          page.firstSequence != entry.first ||
          page.lastSequence != entry.last) {
        throw const FormatException('Persisted HF capture page mismatch');
      }
      for (final record in page.records) {
        if (previousSequence == null) {
          missingRecords = _addGapEvidence(missingRecords, record.sequence);
        } else {
          final distance = hfCaptureSequenceDistance(
            previousSequence,
            record.sequence,
          );
          if (distance == 0 || distance > 0x7FFFFFFF) {
            throw const FormatException('Invalid persisted page order');
          }
          missingRecords = _addGapEvidence(missingRecords, distance - 1);
        }
        previousSequence = record.sequence;
      }
      if (missingRecords > page.metadata.droppedRecords) {
        throw const FormatException('Unexplained persisted sequence gap');
      }
      persistedBytes += bytes.length;
      lastDeliveryToken = page.deliveryToken;
    }
    return (
      previousSequence,
      lastDeliveryToken,
      persistedBytes,
      entries.length,
      missingRecords,
    );
  }

  void _onUnsolicitedMessage(ChameleonMessage message) {
    if (message.command != ChameleonCommand.hfCaptureEvent.value ||
        message.status != chameleonStatusSuccess) {
      return;
    }
    try {
      if (message.data.length != hfCaptureMetadataSize) {
        throw const FormatException('Invalid HF capture event payload');
      }
      final event = HfCaptureMetadata.decode(message.data);
      final metadata = _metadata;
      if (metadata == null ||
          event.sessionId != metadata.sessionId ||
          event.bootId != metadata.bootId ||
          event.startToken != metadata.startToken ||
          event.mode != metadata.mode ||
          event.state != metadata.state ||
          _needsFinalize ||
          _sessionFinalized ||
          _incompleteCapture != null) {
        return;
      }
      _metadata = event;
      _notify();
      _requestDrain();
    } catch (error) {
      _setError(error);
    }
  }

  void _requestDrain() {
    if (_disposed || _busy || _communicator == null || _metadata == null) {
      return;
    }
    unawaited(
      _drain().catchError((Object error, StackTrace stackTrace) {
        _setError(error);
      }),
    );
  }

  Future<void> _drain({int maxPages = 16}) async {
    if (_drainCompleter != null) {
      await _drainCompleter!.future;
      return;
    }
    final completer = Completer<void>();
    _drainCompleter = completer;
    ChameleonCommunicator? communicator;
    int? sessionId;
    final generation = _connectionGeneration;
    try {
      communicator = _requireCommunicator();
      final session = _sessionDirectory;
      final currentMetadata = _metadata;
      if (session == null || currentMetadata == null) return;
      sessionId = currentMetadata.sessionId;
      final bootId = currentMetadata.bootId;
      final startToken = currentMetadata.startToken;
      final mode = currentMetadata.mode;
      for (var pageNumber = 0; pageNumber < maxPages; pageNumber++) {
        if (!_connectionMatches(communicator, generation)) return;
        final page = await communicator.hfCaptureGet(
          sessionId,
          acknowledgeSequence: _lastPersistedSequence,
          acknowledgeDeliveryToken: _lastPersistedDeliveryToken,
        );
        if (!_connectionMatches(communicator, generation)) return;
        if (page.metadata.sessionId != sessionId ||
            page.metadata.bootId != bootId ||
            page.metadata.startToken != startToken ||
            page.metadata.mode != mode) {
          throw const FormatException('HF capture page session mismatch');
        }
        if (page.records.isEmpty) {
          _metadata = page.metadata;
          if (page.metadata.state == HfCaptureState.stopped &&
              page.metadata.storedRecords == 0) {
            await _finishSession();
          }
          break;
        }
        final nextGapEvidence = _validateNextPage(page);
        _metadata = page.metadata;
        await _persistPage(session, page, _nextPageIndex);
        if (!_connectionMatches(communicator, generation)) return;
        _lastPersistedSequence = page.lastSequence;
        _lastPersistedDeliveryToken = page.deliveryToken;
        _sequenceGapEvidence = nextGapEvidence;
        _nextPageIndex++;
        _persistedBytes += page.pageBytes.length;
        _recentRecords.addAll(page.records);
        if (_recentRecords.length > _recentRecordLimit) {
          _recentRecords.removeRange(
            0,
            _recentRecords.length - _recentRecordLimit,
          );
        }
        _notify();
      }
    } catch (error) {
      if (communicator != null &&
          sessionId != null &&
          isRunning &&
          _connectionMatches(communicator, generation)) {
        try {
          final stopped = await communicator.hfCaptureStop(sessionId);
          if (_connectionMatches(communicator, generation)) {
            _metadata = stopped;
          }
        } catch (stopError) {
          _resumeBlocked = true;
          throw StateError(
            'HF capture drain failed: $error; stopping capture also failed: $stopError',
          );
        }
      }
      rethrow;
    } finally {
      _drainCompleter = null;
      completer.complete();
      if (communicator != null &&
          _connectionMatches(communicator, generation) &&
          (isRunning || needsDrain)) {
        _schedulePoll(const Duration(milliseconds: 500));
      }
    }
  }

  int _validateNextPage(HfCapturePage page) {
    if (page.metadata.firstSequence != page.firstSequence ||
        page.metadata.storedRecords < page.records.length) {
      throw const FormatException('HF capture page metadata mismatch');
    }
    var gaps = _sequenceGapEvidence;
    var previous = _lastPersistedSequence;
    for (final record in page.records) {
      if (previous == null) {
        gaps = _addGapEvidence(gaps, record.sequence);
      } else {
        final distance = hfCaptureSequenceDistance(previous, record.sequence);
        if (distance == 0 || distance > 0x7FFFFFFF) {
          throw const FormatException('Invalid HF capture page transition');
        }
        gaps = _addGapEvidence(gaps, distance - 1);
      }
      previous = record.sequence;
    }
    if (gaps > page.metadata.droppedRecords) {
      throw const FormatException('Unexplained HF capture page transition');
    }
    return gaps;
  }

  int _addGapEvidence(int current, int additional) {
    if (additional <= 0) return current;
    return current >= 0xFFFFFFFF - additional
        ? 0xFFFFFFFF
        : current + additional;
  }

  Future<void> _persistPage(
    Directory session,
    HfCapturePage page,
    int pageIndex,
  ) async {
    final index = pageIndex.toString().padLeft(10, '0');
    final first = page.firstSequence.toString().padLeft(10, '0');
    final last = page.lastSequence!.toString().padLeft(10, '0');
    final crc = hfCaptureCrc32(
      page.pageBytes,
    ).toRadixString(16).padLeft(8, '0');
    final pages = Directory(path.join(session.path, 'pages'));
    final destination = File(
      path.join(pages.path, '$index-$first-$last-$crc.hfcap'),
    );
    if (await destination.exists()) {
      final existing = await destination.readAsBytes();
      if (!listEquals(existing, page.pageBytes)) {
        throw StateError('Conflicting persisted HF capture page');
      }
      return;
    }
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(page.pageBytes, flush: true);
    await temporary.rename(destination.path);
  }

  Future<void> _writePendingManifest(
    Directory session,
    DateTime startedAt,
    HfCaptureMode mode,
    int startToken,
    String? transport,
  ) async {
    if (transport != 'usb' && transport != 'ble') {
      throw StateError('HF capture START requires a USB or BLE transport');
    }
    final destination = _pendingManifestFile();
    if (await destination.exists()) {
      throw StateError('A pending HF capture manifest already exists');
    }
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': _pendingManifestVersion,
        'deviceId': _deviceId,
        'startToken': startToken,
        'transport': transport,
        'mode': mode.value,
        'directory': path.basename(session.path),
        'startedAt': startedAt.toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temporary.rename(destination.path);
  }

  Future<void> _writeActiveManifest() async {
    final root = _rootDirectory!;
    final session = _sessionDirectory!;
    final metadata = _metadata!;
    final startedAt = _startedAt!;
    final destination = _activeManifestFile();
    if (await destination.exists()) {
      throw StateError('An active HF capture manifest already exists');
    }
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': _activeManifestVersion,
        'deviceId': _deviceId,
        'sessionId': metadata.sessionId,
        'bootId': metadata.bootId,
        'startToken': metadata.startToken,
        'mode': metadata.mode.value,
        'directory': path.basename(session.path),
        'startedAt': startedAt.toUtc().toIso8601String(),
      }),
      flush: true,
    );
    if (!identical(root, _rootDirectory)) {
      throw StateError('HF capture storage changed while writing manifest');
    }
    await temporary.rename(destination.path);
  }

  File _activeManifestFile() {
    final root = _rootDirectory;
    final deviceId = _deviceId;
    if (root == null || deviceId == null) {
      throw StateError('HF capture device storage is not initialized');
    }
    return File(path.join(root.path, 'active-$deviceId.json'));
  }

  File _pendingManifestFile() {
    final root = _rootDirectory;
    final deviceId = _deviceId;
    if (root == null || deviceId == null) {
      throw StateError('HF capture device storage is not initialized');
    }
    return File(path.join(root.path, 'pending-$deviceId.json'));
  }

  Future<void> _clearActiveManifest() async {
    if (_rootDirectory == null || _deviceId == null) return;
    final file = _activeManifestFile();
    if (await file.exists()) await file.delete();
  }

  Future<void> _clearPendingManifest() async {
    if (_rootDirectory == null || _deviceId == null) return;
    final file = _pendingManifestFile();
    if (await file.exists()) await file.delete();
  }

  Future<void> _writeIncompleteSummary(
    Directory session, {
    required int? sessionId,
    required int? bootId,
    required int startToken,
    required int mode,
    required DateTime startedAt,
    required String reason,
  }) async {
    final summary = File(path.join(session.path, _sessionSummaryName));
    if (await summary.exists()) return;

    var pageCount = 0;
    var persistedBytes = 0;
    final pages = Directory(path.join(session.path, 'pages'));
    if (await pages.exists()) {
      await for (final entity in pages.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.hfcap')) {
          pageCount++;
          persistedBytes += await entity.length();
        }
      }
    }

    final temporary = File('${summary.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'protocolVersion': hfCaptureProtocolVersion,
        'deviceId': _deviceId,
        'sessionId': sessionId,
        'bootId': bootId,
        'startToken': startToken,
        'mode': mode,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': DateTime.now().toUtc().toIso8601String(),
        'persistedBytes': persistedBytes,
        'pageCount': pageCount,
        'cleanlyDrained': false,
        'incompleteReason': reason,
      }),
      flush: true,
    );
    await temporary.rename(summary.path);
  }

  Future<void> _archiveIncompleteCapture(_IncompleteCapture capture) async {
    await _writeIncompleteSummary(
      capture.session,
      sessionId: capture.sessionId,
      bootId: capture.bootId,
      startToken: capture.startToken,
      mode: capture.mode,
      startedAt: capture.startedAt,
      reason: capture.reason,
    );
    if (capture.pendingManifest) {
      await _clearPendingManifest();
    } else {
      await _clearActiveManifest();
    }
    _incompleteCapture = null;
    _resumeBlocked = false;
    _needsFinalize = false;
  }

  Future<void> _finishSession() async {
    _needsFinalize = true;
    final session = _sessionDirectory;
    final metadata = _metadata;
    final startedAt = _startedAt;
    if (session == null ||
        metadata == null ||
        startedAt == null ||
        metadata.state != HfCaptureState.stopped ||
        metadata.storedRecords != 0) {
      throw StateError(
        'HF capture cannot finalize before it is stopped and drained',
      );
    }
    final summary = File(path.join(session.path, _sessionSummaryName));
    if (!await summary.exists()) {
      final temporary = File('${summary.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'protocolVersion': hfCaptureProtocolVersion,
          'deviceId': _deviceId,
          'sessionId': metadata.sessionId,
          'bootId': metadata.bootId,
          'startToken': metadata.startToken,
          'mode': metadata.mode.value,
          'startedAt': startedAt.toUtc().toIso8601String(),
          'endedAt': DateTime.now().toUtc().toIso8601String(),
          'observedRecords': metadata.observedRecords,
          'droppedRecords': metadata.droppedRecords,
          'persistedBytes': _persistedBytes,
          'pageCount': _nextPageIndex,
          'sequenceGapEvidence': _sequenceGapEvidence,
          'elapsedTicks': metadata.elapsedTicks,
          'overflowed': metadata.overflowed,
          'cleanlyDrained': true,
        }),
        flush: true,
      );
      await temporary.rename(summary.path);
    }
    await _clearActiveManifest();
    await _clearPendingManifest();
    _resumeBlocked = false;
    _incompleteCapture = null;
    _sessionFinalized = true;
    _needsFinalize = false;
  }

  void _schedulePoll(Duration delay) {
    _pollTimer?.cancel();
    if (_disposed || (!isRunning && !needsDrain) || _communicator == null) {
      return;
    }
    _pollTimer = Timer(delay, _requestDrain);
  }

  Future<void> _waitForDrain() async {
    final active = _drainCompleter;
    if (active != null) await active.future;
  }

  void _beginOperation() {
    _busy = true;
    _operationCompleter = Completer<void>();
  }

  void _endOperation() {
    _busy = false;
    final operation = _operationCompleter;
    _operationCompleter = null;
    if (operation != null && !operation.isCompleted) operation.complete();
  }

  Future<void> _waitForOperation() async {
    final operation = _operationCompleter;
    if (operation != null) await operation.future;
  }

  bool _connectionMatches(ChameleonCommunicator communicator, int generation) =>
      !_disposed &&
      generation == _connectionGeneration &&
      identical(_communicator, communicator);

  String _normalizeDeviceId(String value) {
    final normalized = value.toLowerCase();
    if (normalized.length != 16 ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(normalized)) {
      throw const FormatException('Invalid device chip ID');
    }
    return normalized;
  }

  int _newStartToken() {
    final random = Random.secure();
    var token = 0;
    while (token == 0) {
      token = (random.nextInt(0x10000) << 16) | random.nextInt(0x10000);
    }
    return token;
  }

  void _resetSessionState() {
    _sessionDirectory = null;
    _lastPersistedSequence = null;
    _lastPersistedDeliveryToken = null;
    _sequenceGapEvidence = 0;
    _nextPageIndex = 0;
    _persistedBytes = 0;
    _startedAt = null;
    _metadata = null;
    _lastReaderCard = null;
    _recentRecords.clear();
    _resumeBlocked = false;
    _incompleteCapture = null;
    _sessionFinalized = false;
    _needsFinalize = false;
  }

  ChameleonCommunicator _requireCommunicator() {
    final communicator = _communicator;
    if (communicator == null) {
      throw StateError('No connected device for HF capture');
    }
    return communicator;
  }

  void _setError(Object error) {
    _error = error.toString();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionGeneration++;
    _pollTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    _communicator = null;
    super.dispose();
  }
}
