import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/data_sync.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Codec for password-protected `.cusync` files.
abstract final class DataSyncBundleCodec {
  static const int version = 1;
  static const int pbkdf2Iterations = 600000;
  static const int maxBundleBytes = SyncLimits.maxEncodedBytes + 128;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const List<int> _magic = [0x43, 0x55, 0x53, 0x59, 0x4e, 0x43];
  static final AesGcm _cipher = AesGcm.with256bits();

  static Future<Uint8List> encode(
    SyncSnapshot snapshot,
    String password,
  ) async {
    if (password.isEmpty) {
      throw const FormatException('A bundle password is required');
    }
    final clearText = utf8.encode(snapshot.toJson());
    if (clearText.length > SyncLimits.maxEncodedBytes) {
      throw const FormatException('Sync snapshot exceeds the size limit');
    }

    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final header = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(version)
      ..addByte(1) // PBKDF2-HMAC-SHA256
      ..addByte(1) // AES-256-GCM
      ..addByte(_saltLength)
      ..addByte(_nonceLength)
      ..addByte(_tagLength)
      ..add(_uint32(pbkdf2Iterations))
      ..add(_uint32(clearText.length))
      ..add(salt)
      ..add(nonce);
    final authenticatedHeader = header.takeBytes();
    final key = await _bundleKey(password, salt);
    final box = await _cipher.encrypt(
      clearText,
      secretKey: key,
      nonce: nonce,
      aad: authenticatedHeader,
    );
    final result = Uint8List.fromList([
      ...authenticatedHeader,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    if (result.length > maxBundleBytes) {
      throw const FormatException(
        'Encrypted sync bundle exceeds the size limit',
      );
    }
    return result;
  }

  static Future<SyncSnapshot> decode(List<int> bundle, String password) async {
    if (password.isEmpty) {
      throw const FormatException('A bundle password is required');
    }
    const fixedHeaderLength = 20;
    if (bundle.length <
            fixedHeaderLength + _saltLength + _nonceLength + _tagLength ||
        bundle.length > maxBundleBytes) {
      throw const FormatException('Invalid encrypted sync bundle size');
    }
    final bytes = Uint8List.fromList(bundle);
    if (!_equal(bytes.sublist(0, _magic.length), _magic) ||
        bytes[6] != version ||
        bytes[7] != 1 ||
        bytes[8] != 1 ||
        bytes[9] != _saltLength ||
        bytes[10] != _nonceLength ||
        bytes[11] != _tagLength ||
        _readUint32(bytes, 12) != pbkdf2Iterations) {
      throw const FormatException('Unsupported encrypted sync bundle');
    }
    final clearLength = _readUint32(bytes, 16);
    if (clearLength > SyncLimits.maxEncodedBytes) {
      throw const FormatException(
        'Encrypted sync bundle exceeds the size limit',
      );
    }
    const saltStart = fixedHeaderLength;
    const nonceStart = saltStart + _saltLength;
    const cipherStart = nonceStart + _nonceLength;
    final tagStart = cipherStart + clearLength;
    if (tagStart + _tagLength != bytes.length) {
      throw const FormatException('Invalid encrypted sync bundle length');
    }
    final salt = bytes.sublist(saltStart, nonceStart);
    final nonce = bytes.sublist(nonceStart, cipherStart);
    final key = await _bundleKey(password, salt);
    try {
      final clearText = await _cipher.decrypt(
        SecretBox(
          bytes.sublist(cipherStart, tagStart),
          nonce: nonce,
          mac: Mac(bytes.sublist(tagStart)),
        ),
        secretKey: key,
        aad: bytes.sublist(0, cipherStart),
      );
      return SyncSnapshot.fromJson(
        utf8.decode(clearText, allowMalformed: false),
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong password or damaged sync bundle');
    }
  }

  static Future<SecretKey> _bundleKey(String password, List<int> salt) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      bits: 256,
      iterations: pbkdf2Iterations,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }
}

class DataSyncPairingCode {
  static const String scheme = 'cusync';
  static const int version = 2;

  final InternetAddress address;
  final int port;
  final Uint8List key;

  DataSyncPairingCode._(this.address, this.port, this.key);

  factory DataSyncPairingCode.parse(String encoded) {
    final Uri uri;
    try {
      uri = Uri.parse(encoded);
    } on FormatException {
      throw const FormatException('Invalid sync pairing code');
    }
    final parameters = uri.queryParametersAll;
    if (uri.scheme != scheme ||
        !uri.hasAuthority ||
        uri.host != 'pair' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.path != '/v$version' ||
        uri.fragment.isNotEmpty ||
        parameters.length != 3 ||
        parameters.keys.toSet().difference({
          'address',
          'port',
          'key',
        }).isNotEmpty ||
        parameters.values.any((values) => values.length != 1)) {
      throw const FormatException('Invalid sync pairing code');
    }
    final addressText = parameters['address']?.single ?? '';
    final address = InternetAddress.tryParse(addressText);
    final port = int.tryParse(parameters['port']?.single ?? '');
    final keyText = parameters['key']?.single ?? '';
    late final Uint8List key;
    try {
      key = base64Url.decode(base64Url.normalize(keyText));
    } on FormatException {
      throw const FormatException('Invalid sync pairing key');
    }
    if (address == null ||
        address.type != InternetAddressType.IPv4 ||
        address.isMulticast ||
        address.address == InternetAddress.anyIPv4.address ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        key.length != 32) {
      throw const FormatException('Invalid sync pairing code');
    }
    return DataSyncPairingCode._(address, port, key);
  }

  String encode() => Uri(
    scheme: scheme,
    host: 'pair',
    path: '/v$version',
    queryParameters: {
      'address': address.address,
      'port': '$port',
      'key': base64Url.encode(key).replaceAll('=', ''),
    },
  ).toString();
}

enum DataSyncHostStatus {
  listening,
  connected,
  receivedSnapshot,
  awaitingApproval,
  accepted,
  rejected,
  stopped,
  error,
}

typedef DataSyncApproval = FutureOr<bool> Function(SyncSnapshot snapshot);
typedef DataSyncStatusCallback = void Function(DataSyncHostStatus status);
typedef DataSyncCommitted =
    FutureOr<void> Function(SyncTransactionReceipt receipt);

abstract interface class DataSyncTransactionParticipant {
  Future<SyncTransactionReceipt> prepare(
    String transactionId,
    SyncSnapshot snapshot,
    SyncCheckpoint expectedCheckpoint, {
    SyncTransactionRole role = SyncTransactionRole.participant,
    SyncCheckpoint? peerCheckpoint,
    String? claimedTargetHash,
  });

  Future<SyncTransactionReceipt> commit(String transactionId);

  Future<SyncTransactionReceipt> abortFromCoordinator(
    String transactionId,
    String targetHash,
  );

  Future<SyncTransactionReceipt> reject(
    String transactionId,
    String targetHash,
  );

  Future<SyncTransactionReceipt?> query(String transactionId);

  Future<SyncCoordinatorRecovery?> coordinatorRecovery();

  Future<SyncCoordinatorRecovery> decideCoordinatorAbort(String transactionId);

  Future<void> completeCoordinator(String transactionId);

  Future<SyncTransactionReceipt?> pendingParticipant();
}

/// A foreground, one-client sync host. The QR key is valid for this host only.
class DataSyncPeerHost {
  static const Duration defaultTimeout = Duration(seconds: 20);
  static const Duration defaultInteractionTimeout = Duration(minutes: 10);

  final SyncState _localState;
  final DataSyncTransactionParticipant _participant;
  final DataSyncApproval _onApprove;
  final DataSyncCommitted? _onCommitted;
  final Duration _timeout;
  final Duration _interactionTimeout;
  final DataSyncStatusCallback? _onStatus;
  final ServerSocket _server;
  final SecretKey _key;
  final StreamController<DataSyncHostStatus> _statuses =
      StreamController<DataSyncHostStatus>.broadcast();
  final Completer<void> _done = Completer<void>();
  Socket? _socket;
  bool _stopped = false;
  String? _activeTransactionId;
  bool _debugDisconnectAfterCommit;
  final List<DateTime> _preAuthFailures = [];
  final int _maxPreAuthFailures;
  final Duration _preAuthBackoff;
  DateTime? _blockedUntil;
  DataSyncHostStatus _status = DataSyncHostStatus.listening;

  final String displayAddress;
  final String pairingCode;

  DataSyncPeerHost._(
    this._localState,
    this._participant,
    this._onApprove,
    this._onCommitted,
    this._timeout,
    this._interactionTimeout,
    this._onStatus,
    this._server,
    this._key,
    this.displayAddress,
    this.pairingCode,
    this._debugDisconnectAfterCommit,
    this._maxPreAuthFailures,
    this._preAuthBackoff,
  );

  int get port => _server.port;
  DataSyncHostStatus get status => _status;
  Stream<DataSyncHostStatus> get statusStream => _statuses.stream;
  Future<void> get done => _done.future;

  static Future<DataSyncPeerHost> start({
    required SyncState localState,
    required DataSyncTransactionParticipant participant,
    required DataSyncApproval onApprove,
    DataSyncCommitted? onCommitted,
    InternetAddress? addressOverride,
    Duration timeout = defaultTimeout,
    Duration interactionTimeout = defaultInteractionTimeout,
    DataSyncStatusCallback? onStatus,
    @visibleForTesting bool debugDisconnectAfterCommit = false,
    @visibleForTesting int debugMaxPreAuthFailures = 8,
    @visibleForTesting
    Duration debugPreAuthBackoff = const Duration(seconds: 5),
  }) async {
    if (timeout <= Duration.zero ||
        interactionTimeout <= Duration.zero ||
        debugMaxPreAuthFailures < 1 ||
        debugPreAuthBackoff <= Duration.zero) {
      throw ArgumentError('Sync timeouts must be positive');
    }
    final advertised = addressOverride ?? await _lanIPv4();
    if (advertised.type != InternetAddressType.IPv4 || advertised.isMulticast) {
      throw const FormatException('A valid LAN IPv4 address is required');
    }
    final bindAddress = addressOverride ?? InternetAddress.anyIPv4;
    final server = await ServerSocket.bind(bindAddress, 0, shared: false);
    final keyBytes = _randomBytes(32);
    final pairing = DataSyncPairingCode._(advertised, server.port, keyBytes);
    final pending = await participant.pendingParticipant();
    final host = DataSyncPeerHost._(
      localState,
      participant,
      onApprove,
      onCommitted,
      timeout,
      interactionTimeout,
      onStatus,
      server,
      SecretKey(keyBytes),
      advertised.address,
      pairing.encode(),
      debugDisconnectAfterCommit,
      debugMaxPreAuthFailures,
      debugPreAuthBackoff,
    );
    if (pending != null) {
      host._activeTransactionId = pending.transactionId;
      host._status = DataSyncHostStatus.awaitingApproval;
    }
    server.listen(
      host._accept,
      onError: host._serverError,
      cancelOnError: false,
    );
    scheduleMicrotask(() => host._emit(host._status));
    return host;
  }

  void _accept(Socket socket) {
    final blockedUntil = _blockedUntil;
    if (_stopped ||
        _socket != null ||
        (blockedUntil != null && DateTime.now().isBefore(blockedUntil))) {
      socket.destroy();
      return;
    }
    _socket = socket;
    _emit(DataSyncHostStatus.connected);
    unawaited(_runConnection(socket));
  }

  Future<void> _runConnection(Socket socket) async {
    final channel = _EncryptedChannel(socket, _key, _timeout);
    var authenticated = false;
    try {
      final first = await channel.readMessage();
      authenticated = true;
      switch (first.type) {
        case _MessageType.hello:
          if (_activeTransactionId != null) {
            throw StateError('Prepared participant accepts recovery only');
          }
          await _handleInitialExchange(channel, first.payload);
        case _MessageType.query:
          await _handleQuery(channel, first.payload);
        default:
          throw const FormatException('Unexpected peer sync message');
      }
    } catch (_) {
      if (!_stopped) {
        if (!authenticated) _recordPreAuthFailure();
        _emit(
          _activeTransactionId == null
              ? DataSyncHostStatus.listening
              : DataSyncHostStatus.awaitingApproval,
        );
      }
    } finally {
      channel.close();
      if (identical(_socket, socket)) _socket = null;
    }
  }

  Future<void> _handleInitialExchange(
    _EncryptedChannel channel,
    Uint8List payload,
  ) async {
    SyncState.fromJsonMap(_decodeObject(payload, 'peer hello'));
    _emit(DataSyncHostStatus.receivedSnapshot);
    await channel.writeJson(_MessageType.hostState, _localState.toJsonMap());
    final prepare = await channel.readMessage(timeout: _interactionTimeout);
    if (prepare.type != _MessageType.prepare) {
      throw const FormatException('Expected peer sync PREPARE');
    }
    await _handlePrepare(channel, prepare.payload);
  }

  Future<void> _handlePrepare(
    _EncryptedChannel channel,
    Uint8List payload,
  ) async {
    final request = _decodePrepare(payload);
    final transactionId = request.transactionId;
    _activeTransactionId = transactionId;
    if (request.expectedCheckpoint != _localState.checkpoint) {
      final rejected = await _participant.reject(
        transactionId,
        request.targetHash,
      );
      await _respondFromReceipt(channel, rejected);
      return;
    }

    var receipt = await _participant.query(transactionId);
    if (receipt != null) {
      _verifyReceipt(receipt, transactionId, request.targetHash);
      await _respondFromReceipt(channel, receipt);
      return;
    }

    _emit(DataSyncHostStatus.awaitingApproval);
    final accepted = await Future<bool>.sync(
      () => _onApprove(request.snapshot),
    ).timeout(_interactionTimeout);
    if (!accepted) {
      receipt = await _participant.reject(transactionId, request.targetHash);
      await _respondFromReceipt(channel, receipt);
      return;
    }

    receipt = await _participant.prepare(
      transactionId,
      request.snapshot,
      _localState.checkpoint,
      claimedTargetHash: request.targetHash,
    );
    _verifyReceipt(receipt, transactionId, request.targetHash);
    await _respondFromReceipt(channel, receipt);
  }

  Future<void> _handleQuery(
    _EncryptedChannel channel,
    Uint8List payload,
  ) async {
    final query = _decodeTransactionReference(payload, 'QUERY');
    _activeTransactionId = query.transactionId;
    final receipt = await _participant.query(query.transactionId);
    if (receipt == null) {
      await channel.writeJson(_MessageType.unknown, {
        'version': 2,
        'transactionId': query.transactionId,
        'targetHash': query.targetHash,
        'checkpoint': _localState.checkpoint.toJson(),
      });
      return;
    }
    _verifyReceipt(receipt, query.transactionId, query.targetHash);
    await _respondFromReceipt(channel, receipt);
  }

  Future<void> _respondFromReceipt(
    _EncryptedChannel channel,
    SyncTransactionReceipt receipt,
  ) async {
    switch (receipt.outcome) {
      case SyncTransactionOutcome.prepared:
        await channel.writeReceipt(_MessageType.prepared, receipt);
        await _awaitDecision(
          channel,
          receipt.transactionId,
          receipt.targetHash,
        );
      case SyncTransactionOutcome.committed:
        await channel.writeReceipt(_MessageType.ack, receipt);
        await _finishTerminal(DataSyncHostStatus.accepted);
      case SyncTransactionOutcome.aborted:
        await channel.writeReceipt(_MessageType.rejected, receipt);
        await _finishTerminal(DataSyncHostStatus.rejected);
    }
  }

  Future<void> _awaitDecision(
    _EncryptedChannel channel,
    String transactionId,
    String targetHash,
  ) async {
    final decision = await channel.readMessage(timeout: _interactionTimeout);
    final reference = _decodeTransactionReference(decision.payload, 'decision');
    if (reference.transactionId != transactionId ||
        reference.targetHash != targetHash) {
      throw const FormatException('Peer sync decision does not match PREPARE');
    }
    if (decision.type == _MessageType.abort) {
      final receipt = await _participant.abortFromCoordinator(
        transactionId,
        targetHash,
      );
      await _respondFromReceipt(channel, receipt);
      return;
    }
    if (decision.type != _MessageType.commit) {
      throw const FormatException('Expected peer sync COMMIT or ABORT');
    }

    final receipt = await _participant.commit(transactionId);
    _verifyReceipt(receipt, transactionId, targetHash);
    if (receipt.outcome != SyncTransactionOutcome.committed) {
      throw StateError('Peer sync COMMIT did not commit');
    }
    await Future<void>.sync(() => _onCommitted?.call(receipt));
    if (_debugDisconnectAfterCommit) {
      _debugDisconnectAfterCommit = false;
      channel.close();
      _emit(DataSyncHostStatus.listening);
      return;
    }
    await channel.writeReceipt(_MessageType.ack, receipt);
    await _finishTerminal(DataSyncHostStatus.accepted);
  }

  void _serverError(Object _) {
    unawaited(_fail());
  }

  void _recordPreAuthFailure() {
    final now = DateTime.now();
    _preAuthFailures.removeWhere(
      (attempt) => now.difference(attempt) > const Duration(seconds: 10),
    );
    _preAuthFailures.add(now);
    if (_preAuthFailures.length >= _maxPreAuthFailures) {
      _blockedUntil = now.add(_preAuthBackoff);
      _preAuthFailures.clear();
    }
  }

  Future<void> _fail() async {
    if (_stopped) return;
    _stopped = true;
    _emit(DataSyncHostStatus.error);
    await _server.close();
    _socket?.destroy();
    _socket = null;
    await _finish();
  }

  Future<void> _finishTerminal(DataSyncHostStatus status) async {
    if (_stopped) return;
    _stopped = true;
    _emit(status);
    await _server.close();
    await _finish();
  }

  void _emit(DataSyncHostStatus status) {
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
    _onStatus?.call(status);
  }

  Future<void> stop() async {
    if (_stopped) return done;
    _stopped = true;
    await _server.close();
    _socket?.destroy();
    _socket = null;
    _emit(DataSyncHostStatus.stopped);
    await _finish();
  }

  Future<void> dispose() => stop();

  Future<void> _finish() async {
    if (!_done.isCompleted) _done.complete();
    if (!_statuses.isClosed) await _statuses.close();
  }
}

class DataSyncClientExchange {
  final SyncState remoteState;
  final SyncState _localState;
  final DataSyncTransactionParticipant _participant;
  final DataSyncPairingCode _pairing;
  final _EncryptedChannel _channel;
  final Duration _timeout;
  final Duration _interactionTimeout;
  bool _completed = false;

  DataSyncClientExchange._(
    this.remoteState,
    this._localState,
    this._participant,
    this._pairing,
    this._channel,
    this._timeout,
    this._interactionTimeout,
  );

  SyncSnapshot get remoteSnapshot => remoteState.snapshot;

  Future<bool> complete(SyncSnapshot mergedSnapshot) async {
    if (_completed) throw StateError('This sync exchange is already complete');
    _completed = true;
    final transactionId = _newTransactionId();
    SyncTransactionReceipt? prepared;
    try {
      prepared = await _participant.prepare(
        transactionId,
        mergedSnapshot,
        _localState.checkpoint,
        role: SyncTransactionRole.coordinator,
        peerCheckpoint: remoteState.checkpoint,
      );
      if (prepared.outcome == SyncTransactionOutcome.aborted) return false;
      await _channel.writeJson(_MessageType.prepare, {
        'version': 2,
        'transactionId': transactionId,
        'snapshot': mergedSnapshot.toJsonMap(),
        'expectedCheckpoint': remoteState.checkpoint.toJson(),
        'targetHash': prepared.targetHash,
      });
      final response = await _channel.readMessage(timeout: _interactionTimeout);
      if (response.type == _MessageType.rejected) {
        final receipt = _decodeReceiptFor(
          response,
          SyncTransactionOutcome.aborted,
        );
        _verifyReceipt(receipt, transactionId, prepared.targetHash);
        await _participant.decideCoordinatorAbort(transactionId);
        await _participant.completeCoordinator(transactionId);
        return false;
      }
      if (response.type != _MessageType.prepared &&
          response.type != _MessageType.ack) {
        throw const FormatException('Invalid peer sync PREPARE response');
      }
      final remoteReceipt = _decodeReceiptFor(
        response,
        response.type == _MessageType.prepared
            ? SyncTransactionOutcome.prepared
            : SyncTransactionOutcome.committed,
      );
      _verifyReceipt(remoteReceipt, transactionId, prepared.targetHash);
      if (response.type == _MessageType.prepared &&
          remoteReceipt.checkpoint != remoteState.checkpoint) {
        throw const FormatException('Peer PREPARED identity does not match');
      }
      final committed = await _participant.commit(transactionId);
      if (committed.outcome != SyncTransactionOutcome.committed) {
        throw StateError('Local peer sync transaction did not commit');
      }
      if (response.type == _MessageType.ack) {
        await _participant.completeCoordinator(transactionId);
        return true;
      }

      await _channel.writeJson(
        _MessageType.commit,
        _transactionReference(transactionId, prepared.targetHash),
      );
      final ack = await _channel.readMessage(timeout: _interactionTimeout);
      if (ack.type != _MessageType.ack) {
        throw const FormatException('Expected peer sync ACK');
      }
      final ackReceipt = _decodeReceiptFor(
        ack,
        SyncTransactionOutcome.committed,
      );
      _verifyReceipt(ackReceipt, transactionId, prepared.targetHash);
      await _participant.completeCoordinator(transactionId);
      return true;
    } catch (error, stackTrace) {
      _channel.close();
      if (prepared == null) rethrow;
      final recovery = await _participant.coordinatorRecovery();
      if (recovery?.transactionId == transactionId &&
          recovery?.decision == SyncCoordinatorDecision.commitDecided) {
        return _recoverCommitted(recovery!);
      }
      final abortRecovery = await _participant.decideCoordinatorAbort(
        transactionId,
      );
      await _recoverRemoteAbort(
        pairing: _pairing,
        recovery: abortRecovery,
        timeout: _timeout,
      );
      await _participant.completeCoordinator(transactionId);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _channel.close();
    }
  }

  Future<bool> _recoverCommitted(SyncCoordinatorRecovery recovery) async {
    final local = await _participant.commit(recovery.transactionId);
    if (local.outcome != SyncTransactionOutcome.committed) {
      throw StateError('Decided local peer commit could not roll forward');
    }
    await _recoverRemoteCommit(
      pairing: _pairing,
      recovery: recovery,
      timeout: _timeout,
      interactionTimeout: _interactionTimeout,
    );
    await _participant.completeCoordinator(recovery.transactionId);
    return true;
  }

  void close() {
    _completed = true;
    _channel.close();
  }
}

abstract final class DataSyncPeerClient {
  static Future<void> resumePending({
    required String pairingCode,
    required SyncCoordinatorRecovery recovery,
    required DataSyncTransactionParticipant participant,
    Duration timeout = DataSyncPeerHost.defaultTimeout,
    Duration interactionTimeout = DataSyncPeerHost.defaultInteractionTimeout,
  }) async {
    final pairing = DataSyncPairingCode.parse(pairingCode);
    switch (recovery.decision) {
      case SyncCoordinatorDecision.prepared:
        recovery = await participant.decideCoordinatorAbort(
          recovery.transactionId,
        );
        await _recoverRemoteAbort(
          pairing: pairing,
          recovery: recovery,
          timeout: timeout,
        );
      case SyncCoordinatorDecision.abortDecided:
        await _recoverRemoteAbort(
          pairing: pairing,
          recovery: recovery,
          timeout: timeout,
        );
      case SyncCoordinatorDecision.commitDecided:
        final local = await participant.commit(recovery.transactionId);
        if (local.outcome != SyncTransactionOutcome.committed) {
          throw StateError('Decided local peer commit could not roll forward');
        }
        await _recoverRemoteCommit(
          pairing: pairing,
          recovery: recovery,
          timeout: timeout,
          interactionTimeout: interactionTimeout,
        );
    }
    await participant.completeCoordinator(recovery.transactionId);
  }

  static Future<void> resumeCommitted({
    required String pairingCode,
    required SyncCoordinatorRecovery recovery,
    required DataSyncTransactionParticipant participant,
    Duration timeout = DataSyncPeerHost.defaultTimeout,
    Duration interactionTimeout = DataSyncPeerHost.defaultInteractionTimeout,
  }) async {
    if (recovery.decision != SyncCoordinatorDecision.commitDecided) {
      throw StateError('Peer sync has no durable COMMIT decision');
    }
    await resumePending(
      pairingCode: pairingCode,
      recovery: recovery,
      participant: participant,
      timeout: timeout,
      interactionTimeout: interactionTimeout,
    );
  }

  static Future<DataSyncClientExchange> connect({
    required String pairingCode,
    required SyncState localState,
    required DataSyncTransactionParticipant participant,
    Duration timeout = DataSyncPeerHost.defaultTimeout,
    Duration interactionTimeout = DataSyncPeerHost.defaultInteractionTimeout,
  }) async {
    if (timeout <= Duration.zero || interactionTimeout <= Duration.zero) {
      throw ArgumentError('Sync timeouts must be positive');
    }
    final pairing = DataSyncPairingCode.parse(pairingCode);
    final channel = await _connectChannel(pairing, timeout);
    try {
      await channel.writeJson(_MessageType.hello, localState.toJsonMap());
      final message = await channel.readMessage();
      if (message.type != _MessageType.hostState) {
        throw const FormatException('Expected peer sync host state');
      }
      final remote = SyncState.fromJsonMap(
        _decodeObject(message.payload, 'host state'),
      );
      return DataSyncClientExchange._(
        remote,
        localState,
        participant,
        pairing,
        channel,
        timeout,
        interactionTimeout,
      );
    } catch (_) {
      channel.close();
      rethrow;
    }
  }
}

Future<void> _recoverRemoteCommit({
  required DataSyncPairingCode pairing,
  required SyncCoordinatorRecovery recovery,
  required Duration timeout,
  required Duration interactionTimeout,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    _EncryptedChannel? channel;
    try {
      channel = await _connectChannel(pairing, timeout);
      await channel.writeJson(
        _MessageType.query,
        _transactionReference(recovery.transactionId, recovery.targetHash),
      );
      var response = await channel.readMessage(timeout: interactionTimeout);
      if (response.type == _MessageType.prepared) {
        final prepared = _decodeReceiptFor(
          response,
          SyncTransactionOutcome.prepared,
        );
        _verifyReceipt(prepared, recovery.transactionId, recovery.targetHash);
        if (prepared.checkpoint != recovery.peerCheckpoint) {
          throw const FormatException('Peer recovery identity does not match');
        }
        await channel.writeJson(
          _MessageType.commit,
          _transactionReference(recovery.transactionId, recovery.targetHash),
        );
        response = await channel.readMessage(timeout: interactionTimeout);
      }
      if (response.type != _MessageType.ack) {
        throw StateError('Peer has no matching committed receipt');
      }
      final acknowledged = _decodeReceiptFor(
        response,
        SyncTransactionOutcome.committed,
      );
      _verifyReceipt(acknowledged, recovery.transactionId, recovery.targetHash);
      return;
    } catch (error) {
      lastError = error;
    } finally {
      channel?.close();
    }
  }
  throw lastError ?? StateError('Could not recover peer sync COMMIT');
}

Future<void> _recoverRemoteAbort({
  required DataSyncPairingCode pairing,
  required SyncCoordinatorRecovery recovery,
  required Duration timeout,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    _EncryptedChannel? channel;
    try {
      channel = await _connectChannel(pairing, timeout);
      await channel.writeJson(
        _MessageType.query,
        _transactionReference(recovery.transactionId, recovery.targetHash),
      );
      var response = await channel.readMessage(timeout: timeout);
      if (response.type == _MessageType.prepared) {
        final prepared = _decodeReceiptFor(
          response,
          SyncTransactionOutcome.prepared,
        );
        _verifyReceipt(prepared, recovery.transactionId, recovery.targetHash);
        if (prepared.checkpoint != recovery.peerCheckpoint) {
          throw const FormatException('Peer recovery identity does not match');
        }
        await channel.writeJson(
          _MessageType.abort,
          _transactionReference(recovery.transactionId, recovery.targetHash),
        );
        response = await channel.readMessage(timeout: timeout);
      }
      if (response.type == _MessageType.rejected) {
        final aborted = _decodeReceiptFor(
          response,
          SyncTransactionOutcome.aborted,
        );
        _verifyReceipt(aborted, recovery.transactionId, recovery.targetHash);
        return;
      }
      if (response.type == _MessageType.unknown) {
        final unknown = _decodeMap(response.payload, 'unknown transaction');
        if (unknown.length != 4 ||
            unknown['version'] != 2 ||
            unknown['transactionId'] != recovery.transactionId ||
            unknown['targetHash'] != recovery.targetHash ||
            SyncCheckpoint.fromJson(unknown['checkpoint']) !=
                recovery.peerCheckpoint) {
          throw const FormatException('Peer abort identity does not match');
        }
        return;
      }
      throw StateError('Peer did not acknowledge ABORT');
    } catch (error) {
      lastError = error;
    } finally {
      channel?.close();
    }
  }
  throw lastError ?? StateError('Could not recover peer sync ABORT');
}

enum _MessageType {
  hello,
  hostState,
  prepare,
  prepared,
  commit,
  ack,
  abort,
  rejected,
  query,
  unknown,
}

class _Message {
  final _MessageType type;
  final Uint8List payload;
  const _Message(this.type, this.payload);
}

class _EncryptedChannel {
  static const int maxFrameBytes = SyncLimits.maxEncodedBytes + 4096;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static final List<int> _aad = utf8.encode('cusync-peer-v2');
  static final AesGcm _cipher = AesGcm.with256bits();

  final Socket _socket;
  final SecretKey _key;
  final Duration _timeout;
  late final StreamIterator<Uint8List> _iterator = StreamIterator(_socket);
  Uint8List _chunk = Uint8List(0);
  int _chunkOffset = 0;
  bool _closed = false;

  _EncryptedChannel(this._socket, this._key, this._timeout);

  Future<void> writeJson(_MessageType type, Map<String, Object> value) async {
    await writeMessage(type, utf8.encode(jsonEncode(value)));
  }

  Future<void> writeReceipt(
    _MessageType type,
    SyncTransactionReceipt receipt,
  ) => writeJson(type, {'version': 2, 'receipt': receipt.toJson()});

  Future<void> writeMessage(_MessageType type, List<int> payload) async {
    if (_closed) throw StateError('Sync connection is closed');
    if (payload.length > maxFrameBytes - _nonceLength - _tagLength - 1) {
      throw const FormatException('Sync message exceeds the size limit');
    }
    final nonce = _randomBytes(_nonceLength);
    final clearText = Uint8List.fromList([type.index + 1, ...payload]);
    final box = await _cipher.encrypt(
      clearText,
      secretKey: _key,
      nonce: nonce,
      aad: _aad,
    );
    final frame = Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    if (frame.length > maxFrameBytes) {
      throw const FormatException(
        'Encrypted sync frame exceeds the size limit',
      );
    }
    _socket.add([..._uint32(frame.length), ...frame]);
    await _socket.flush().timeout(_timeout);
  }

  Future<_Message> readMessage({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? _timeout;
    final lengthBytes = await _readExactly(4, effectiveTimeout);
    final length = _readUint32(lengthBytes, 0);
    if (length < _nonceLength + _tagLength + 1 || length > maxFrameBytes) {
      throw const FormatException('Invalid encrypted sync frame size');
    }
    final frame = await _readExactly(length, effectiveTimeout);
    final tagStart = frame.length - _tagLength;
    try {
      final clearText = await _cipher.decrypt(
        SecretBox(
          frame.sublist(_nonceLength, tagStart),
          nonce: frame.sublist(0, _nonceLength),
          mac: Mac(frame.sublist(tagStart)),
        ),
        secretKey: _key,
        aad: _aad,
      );
      if (clearText.isEmpty ||
          clearText[0] < 1 ||
          clearText[0] > _MessageType.values.length) {
        throw const FormatException('Unknown sync message type');
      }
      return _Message(
        _MessageType.values[clearText[0] - 1],
        Uint8List.fromList(clearText.sublist(1)),
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('Invalid or damaged encrypted sync frame');
    }
  }

  Future<Uint8List> _readExactly(int count, Duration timeout) async {
    final result = Uint8List(count);
    final deadline = DateTime.now().add(timeout);
    var written = 0;
    while (written < count) {
      if (_chunkOffset == _chunk.length) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw TimeoutException('Timed out reading sync frame', timeout);
        }
        final hasNext = await _iterator.moveNext().timeout(remaining);
        if (!hasNext) {
          throw const FormatException('Sync connection closed early');
        }
        _chunk = _iterator.current;
        _chunkOffset = 0;
        if (_chunk.isEmpty) continue;
      }
      final available = _chunk.length - _chunkOffset;
      final needed = count - written;
      final take = min(available, needed);
      result.setRange(written, written + take, _chunk, _chunkOffset);
      written += take;
      _chunkOffset += take;
    }
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
  }
}

class _PrepareRequest {
  final String transactionId;
  final SyncSnapshot snapshot;
  final SyncCheckpoint expectedCheckpoint;
  final String targetHash;

  const _PrepareRequest({
    required this.transactionId,
    required this.snapshot,
    required this.expectedCheckpoint,
    required this.targetHash,
  });
}

class _TransactionReference {
  final String transactionId;
  final String targetHash;

  const _TransactionReference(this.transactionId, this.targetHash);
}

_PrepareRequest _decodePrepare(Uint8List payload) {
  final value = _decodeMap(payload, 'PREPARE');
  if (value.keys.toSet().length != 5 ||
      !value.keys.toSet().containsAll(const {
        'version',
        'transactionId',
        'snapshot',
        'expectedCheckpoint',
        'targetHash',
      }) ||
      value['version'] != 2 ||
      value['transactionId'] is! String ||
      value['targetHash'] is! String) {
    throw const FormatException('Invalid peer sync PREPARE');
  }
  final transactionId = value['transactionId']! as String;
  final targetHash = value['targetHash']! as String;
  if (transactionId.isEmpty ||
      transactionId.length > 128 ||
      !_isHash(targetHash)) {
    throw const FormatException('Invalid peer sync PREPARE');
  }
  return _PrepareRequest(
    transactionId: transactionId,
    snapshot: SyncSnapshot.fromJson(jsonEncode(value['snapshot'])),
    expectedCheckpoint: SyncCheckpoint.fromJson(value['expectedCheckpoint']),
    targetHash: targetHash,
  );
}

_TransactionReference _decodeTransactionReference(
  Uint8List payload,
  String label,
) {
  final value = _decodeMap(payload, label);
  if (value.length != 3 ||
      value['version'] != 2 ||
      value['transactionId'] is! String ||
      value['targetHash'] is! String) {
    throw FormatException('Invalid peer sync $label');
  }
  final transactionId = value['transactionId']! as String;
  final targetHash = value['targetHash']! as String;
  if (transactionId.isEmpty ||
      transactionId.length > 128 ||
      !_isHash(targetHash)) {
    throw FormatException('Invalid peer sync $label');
  }
  return _TransactionReference(transactionId, targetHash);
}

Map<String, Object> _transactionReference(
  String transactionId,
  String targetHash,
) => {'version': 2, 'transactionId': transactionId, 'targetHash': targetHash};

SyncTransactionReceipt _decodeReceipt(Uint8List payload) {
  final value = _decodeMap(payload, 'receipt');
  if (value.length != 2 || value['version'] != 2) {
    throw const FormatException('Invalid peer sync receipt');
  }
  return SyncTransactionReceipt.fromJson(value['receipt']);
}

SyncTransactionReceipt _decodeReceiptFor(
  _Message message,
  SyncTransactionOutcome expected,
) {
  final expectedType = switch (expected) {
    SyncTransactionOutcome.prepared => _MessageType.prepared,
    SyncTransactionOutcome.committed => _MessageType.ack,
    SyncTransactionOutcome.aborted => _MessageType.rejected,
  };
  final receipt = _decodeReceipt(message.payload);
  if (message.type != expectedType || receipt.outcome != expected) {
    throw const FormatException('Peer receipt type and outcome do not match');
  }
  return receipt;
}

void _verifyReceipt(
  SyncTransactionReceipt receipt,
  String transactionId,
  String targetHash,
) {
  if (receipt.transactionId != transactionId ||
      receipt.targetHash != targetHash) {
    throw const FormatException('Peer sync receipt does not match transaction');
  }
}

Object? _decodeObject(Uint8List payload, String label) {
  try {
    return jsonDecode(utf8.decode(payload, allowMalformed: false));
  } catch (_) {
    throw FormatException('Invalid peer sync $label');
  }
}

Map<String, dynamic> _decodeMap(Uint8List payload, String label) {
  final value = _decodeObject(payload, label);
  if (value is! Map<String, dynamic>) {
    throw FormatException('Invalid peer sync $label');
  }
  return value;
}

Future<_EncryptedChannel> _connectChannel(
  DataSyncPairingCode pairing,
  Duration timeout,
) async {
  final socket = await Socket.connect(
    pairing.address,
    pairing.port,
    timeout: timeout,
  );
  return _EncryptedChannel(socket, SecretKey(pairing.key), timeout);
}

String _newTransactionId() =>
    base64Url.encode(_randomBytes(24)).replaceAll('=', '');

bool _isHash(String value) =>
    value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

Future<InternetAddress> _lanIPv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback && !address.isMulticast) return address;
    }
  }
  throw const SocketException('No LAN IPv4 address is available');
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

Uint8List _uint32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);

int _readUint32(List<int> bytes, int offset) => ByteData.sublistView(
  Uint8List.fromList(bytes),
  offset,
  offset + 4,
).getUint32(0, Endian.big);

bool _equal(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
