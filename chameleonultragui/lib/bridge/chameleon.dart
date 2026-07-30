import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/emv_trace.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/pm3_protocol.dart';
import 'package:chameleonultragui/bridge/chameleon_frame_decoder.dart';
import 'package:logger/logger.dart';

const int chameleonStatusSuccess = 0x68;
const int chameleonDeviceSettingsVersion = 6;
const Duration isoDepSessionControlTimeout = Duration(seconds: 6);
const int activeSlotSnapshotProtocolVersion = 2;
const int activeSlotSnapshotCommitMaxMilliseconds = 46000;
const Duration activeSlotSnapshotSaveTimeout = Duration(seconds: 55);
const int _activeSlotSnapshotBegin = 0;
const int _activeSlotSnapshotSaveRelease = 1;
const int _activeSlotSnapshotAbort = 2;

String _chameleonStatusDescription(int status) {
  return switch (status) {
    0x60 => 'invalid parameter',
    0x66 =>
      'device is in the wrong mode, BLE radio is unavailable, or the BLE control link is not encrypted',
    0x67 => 'unsupported command',
    0x69 => 'command is not implemented',
    0x70 => 'flash write failed',
    0x71 => 'flash read failed',
    0x72 => 'active slot has the wrong card type',
    0x73 => 'device memory error',
    0x74 => 'device could not create a response',
    0x75 => 'command execution failed',
    _ => 'unexpected device status',
  };
}

class ChameleonCommandException implements Exception {
  final ChameleonCommand command;
  final int status;

  const ChameleonCommandException(this.command, this.status);

  @override
  String toString() {
    final hex = status.toRadixString(16).padLeft(2, '0').toUpperCase();
    return 'Command ${command.name} (${command.value}) failed: '
        '${_chameleonStatusDescription(status)} (status 0x$hex)';
  }
}

class ChameleonSecureBleLinkException extends ChameleonCommandException {
  const ChameleonSecureBleLinkException(ChameleonCommand command)
    : super(command, 0x66);

  @override
  String toString() =>
      'The Chameleon rejected commands because the BLE control link is not encrypted. '
      'Reconnect and accept pairing, or remove the stale system bond and pair again.';
}

class IsoDepReaderSessionExchangeException extends ChameleonCommandException {
  const IsoDepReaderSessionExchangeException(
    int status, {
    this.isoDepError,
    this.rfStatus,
    this.wtxCount,
  }) : super(ChameleonCommand.hf14a4ReaderSessionExchange, status);

  final int? isoDepError;
  final int? rfStatus;
  final int? wtxCount;

  bool get hasDiagnostics =>
      isoDepError != null && rfStatus != null && wtxCount != null;

  bool get firmwareSessionClosed => hasDiagnostics;

  String get isoDepErrorDescription => switch (isoDepError) {
    0 => 'none',
    1 => 'invalid parameters',
    2 => 'RF transport failure',
    3 => 'CRC failure',
    4 => 'invalid ISO-DEP block',
    5 => 'ISO-DEP sequence failure',
    6 => 'response overflow',
    7 => 'RF timeout',
    _ => 'unknown ISO-DEP failure',
  };

  @override
  String toString() {
    if (!hasDiagnostics) return super.toString();
    final outerHex = status.toRadixString(16).padLeft(2, '0').toUpperCase();
    final rfHex = rfStatus!.toRadixString(16).padLeft(2, '0').toUpperCase();
    return 'Backend ISO-DEP exchange failed: $isoDepErrorDescription '
        '(device status 0x$outerHex, RF status 0x$rfHex, $wtxCount WTX); '
        'firmware closed the session';
  }
}

class IsoDepReaderSessionStartMetadataException implements Exception {
  const IsoDepReaderSessionStartMetadataException({
    required this.command,
    required this.formatError,
    required this.sessionId,
    required this.cleanupConfirmed,
    this.cleanupError,
  });

  final ChameleonCommand command;
  final FormatException formatError;
  final int? sessionId;
  final bool cleanupConfirmed;
  final Object? cleanupError;

  bool get sessionStateUncertain => !cleanupConfirmed;

  @override
  String toString() {
    final session = sessionId == null
        ? 'no valid session ID'
        : 'session $sessionId';
    if (cleanupConfirmed) {
      return 'Malformed successful ${command.name} metadata ($session); '
          'firmware STOP was confirmed: ${formatError.message}';
    }
    final cleanup = cleanupError == null ? '' : '; STOP failed: $cleanupError';
    return 'Malformed successful ${command.name} metadata ($session) left '
        'firmware session state uncertain: ${formatError.message}$cleanup';
  }
}

enum ChameleonCapabilityMode { uninitialized, advertised, legacyUnknown }

class ChameleonUnsupportedCommandException implements Exception {
  final ChameleonCommand command;

  const ChameleonUnsupportedCommandException(this.command);

  @override
  String toString() =>
      'Command ${command.name} (${command.value}) is not advertised by the connected firmware';
}

class ChameleonResponseTimeoutException implements Exception {
  final ChameleonCommand command;
  final Duration timeout;

  const ChameleonResponseTimeoutException(this.command, this.timeout);

  @override
  String toString() =>
      'Timed out after ${timeout.inMilliseconds} ms waiting for command ${command.name} (${command.value})';
}

class ChameleonCommandResponseUncertainException implements Exception {
  final ChameleonCommand command;

  const ChameleonCommandResponseUncertainException(this.command);

  @override
  String toString() =>
      'Command ${command.name} (${command.value}) cannot be retried until its late response arrives or the device reconnects';
}

class ChameleonCommunicatorClosedException implements Exception {
  final Object? cause;

  const ChameleonCommunicatorClosedException([this.cause]);

  @override
  String toString() => cause == null
      ? 'The device connection is closed'
      : 'The device connection is closed: $cause';
}

class MifareClassicActiveSlotSnapshot {
  final int slot;
  final TagType tagType;
  final int ownerGeneration;
  final int revision;

  const MifareClassicActiveSlotSnapshot({
    required this.slot,
    required this.tagType,
    required this.ownerGeneration,
    required this.revision,
  });
}

// Some ChatGPT magic
// Nobody knows how it works

class ChameleonCommunicator {
  int baudrate = 115200;
  AbstractSerial? _serialInstance;
  final ChameleonFrameDecoder _frameDecoder = ChameleonFrameDecoder();
  List<int> commandQueue = [];
  Future<void> _sendTail = Future<void>.value();
  int? _activeCommandId;
  Completer<ChameleonMessage>? _activeResponse;
  final Set<int> _uncertainResponseIds = <int>{};
  ChameleonCapabilityMode _capabilityMode =
      ChameleonCapabilityMode.uninitialized;
  Future<void>? _capabilityInitialization;
  Set<int> _capabilities = const <int>{};
  bool _disposed = false;
  Object? _disposeCause;

  final Logger log;
  final Duration writeTimeout;
  final Duration snapshotSaveTimeout;

  ChameleonCommunicator(
    this.log, {
    AbstractSerial? port,
    this.writeTimeout = const Duration(seconds: 5),
    this.snapshotSaveTimeout = activeSlotSnapshotSaveTimeout,
  }) {
    if (port != null) {
      open(port);
    }
  }

  dynamic open(AbstractSerial port) {
    _serialInstance = port;
  }

  Uint8List makeDataFrameBytes(
    ChameleonCommand cmd,
    int status,
    Uint8List? data,
  ) => buildChameleonFrame(command: cmd.value, status: status, data: data);

  Future<void> onSerialMessage(List<int> message) async {
    log.t("Received ${message.length} transport bytes");

    final result = _frameDecoder.add(message);
    for (final error in result.errors) {
      log.w('Discarded malformed transport data: $error');
    }
    for (final frame in result.frames) {
      final response = ChameleonMessage(
        command: frame.command,
        status: frame.status,
        data: frame.data,
      );
      final responseDescription =
          response.command == ChameleonCommand.hf14a4ReaderSessionExchange.value
          ? '<redacted payment APDU response, ${response.data.length} bytes>'
          : bytesToHex(response.data);
      log.d(
        "Received message: command = ${response.command}, status = ${response.status}, data = $responseDescription",
      );
      _dispatchResponse(response);
    }
  }

  void _dispatchResponse(ChameleonMessage message) {
    if (_disposed) return;
    if (_uncertainResponseIds.remove(message.command)) {
      log.w('Discarded late response for command ${message.command}');
      return;
    }
    final response = _activeResponse;
    if (_activeCommandId == message.command &&
        response != null &&
        !response.isCompleted) {
      response.complete(message);
      return;
    }
    log.w('Discarded unsolicited response for command ${message.command}');
  }

  Set<int>? get cachedDeviceCapabilities =>
      _capabilityMode == ChameleonCapabilityMode.advertised
      ? _capabilities
      : null;

  bool get usesBleTransport =>
      _serialInstance?.connectionType == ConnectionType.ble;

  bool? supportsCommandSync(ChameleonCommand command) =>
      switch (_capabilityMode) {
        ChameleonCapabilityMode.advertised => _capabilities.contains(
          command.value,
        ),
        ChameleonCapabilityMode.legacyUnknown => null,
        ChameleonCapabilityMode.uninitialized => null,
      };

  Future<bool?> supportsCommand(ChameleonCommand command) async {
    await initializeCapabilities();
    return supportsCommandSync(command);
  }

  Future<void> initializeCapabilities() {
    return _capabilityInitialization ??= _initializeCapabilities();
  }

  Future<void> _initializeCapabilities() async {
    var response =
        await _enqueueCommand(
              ChameleonCommand.getDeviceCapabilities,
              checkCapabilities: false,
            )
            as ChameleonMessage;
    if (usesBleTransport && response.status == 0x66) {
      // Pairing/encryption can complete shortly after the BLE connection event.
      for (
        var attempt = 0;
        attempt < 12 && response.status == 0x66;
        attempt++
      ) {
        await Future.delayed(const Duration(milliseconds: 250));
        response =
            await _enqueueCommand(
                  ChameleonCommand.getDeviceCapabilities,
                  checkCapabilities: false,
                )
                as ChameleonMessage;
      }
    }
    if (response.status == chameleonStatusSuccess) {
      if (response.data.length.isOdd) {
        throw const FormatException(
          'Device capability payload must contain 16-bit command IDs',
        );
      }
      final capabilities = <int>{};
      for (var i = 0; i < response.data.length; i += 2) {
        capabilities.add((response.data[i] << 8) | response.data[i + 1]);
      }
      _capabilities = Set<int>.unmodifiable(capabilities);
      _capabilityMode = ChameleonCapabilityMode.advertised;
      return;
    }
    if (response.status == 0x67 || response.status == 0x69) {
      _capabilities = const <int>{};
      _capabilityMode = ChameleonCapabilityMode.legacyUnknown;
      return;
    }
    if (response.status == 0x66 && usesBleTransport) {
      throw const ChameleonSecureBleLinkException(
        ChameleonCommand.getDeviceCapabilities,
      );
    }
    throw ChameleonCommandException(
      ChameleonCommand.getDeviceCapabilities,
      response.status,
    );
  }

  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    if (cmd != ChameleonCommand.getDeviceCapabilities) {
      await initializeCapabilities();
    }
    return _enqueueCommand(
      cmd,
      data: data,
      timeout: timeout,
      skipReceive: skipReceive,
      checkCapabilities: cmd != ChameleonCommand.getDeviceCapabilities,
    );
  }

  Future<ChameleonMessage> _sendChecked(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    Set<int> allowedStatuses = const {chameleonStatusSuccess},
  }) async {
    final response = await sendCmd(cmd, data: data, timeout: timeout);
    if (response == null || !allowedStatuses.contains(response.status)) {
      throw ChameleonCommandException(cmd, response?.status ?? 0xffff);
    }
    return response;
  }

  Future<ChameleonMessage?> _enqueueCommand(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    required bool checkCapabilities,
  }) async {
    _ensureOpen();
    final previous = _sendTail;
    final release = Completer<void>();
    _sendTail = release.future;
    await previous;
    try {
      _ensureOpen();
      if (checkCapabilities &&
          _capabilityMode == ChameleonCapabilityMode.advertised &&
          !_capabilities.contains(cmd.value)) {
        throw ChameleonUnsupportedCommandException(cmd);
      }
      if (_uncertainResponseIds.contains(cmd.value)) {
        throw ChameleonCommandResponseUncertainException(cmd);
      }
      return await _sendCommand(
        cmd,
        data: data,
        timeout: timeout,
        skipReceive: skipReceive,
      );
    } finally {
      commandQueue.remove(cmd.value);
      release.complete();
    }
  }

  Future<ChameleonMessage?> _sendCommand(
    ChameleonCommand cmd, {
    Uint8List? data,
    required Duration timeout,
    required bool skipReceive,
  }) async {
    final serial = _serialInstance;
    if (serial == null) {
      throw const ChameleonCommunicatorClosedException('No serial transport');
    }
    if (!serial.isOpen) {
      await serial.open();
      await serial.registerCallback(onSerialMessage);
      serial.isOpen = true;
    }

    final dataFrame = makeDataFrameBytes(cmd, 0x00, data);
    commandQueue.add(cmd.value);
    if (cmd == ChameleonCommand.hf14a4ReaderSessionExchange) {
      log.t("Sending redacted ISO-DEP session exchange frame");
      log.d(
        "Sending message: command = ${cmd.value}, data = <redacted payment APDU, ${data?.length ?? 0} bytes>",
      );
    } else {
      log.t("Sending: ${bytesToHex(dataFrame)}");
      log.d(
        "Sending message: command = ${cmd.value}, data = ${bytesToHex(data ?? Uint8List(0))}",
      );
    }

    if (skipReceive) {
      _uncertainResponseIds.add(cmd.value);
      await _writeFrame(serial, dataFrame);
      return null;
    }

    final response = Completer<ChameleonMessage>();
    _activeCommandId = cmd.value;
    _activeResponse = response;
    try {
      await _writeFrame(serial, dataFrame);
      return await response.future.timeout(
        timeout,
        onTimeout: () {
          if (_frameDecoder.retainedByteCount != 0) {
            final error = ChameleonResponseTimeoutException(cmd, timeout);
            dispose(error);
            unawaited(serial.performDisconnect());
            throw error;
          }
          _uncertainResponseIds.add(cmd.value);
          throw ChameleonResponseTimeoutException(cmd, timeout);
        },
      );
    } finally {
      if (_activeCommandId == cmd.value) {
        _activeCommandId = null;
        _activeResponse = null;
      }
    }
  }

  Future<void> _writeFrame(AbstractSerial serial, Uint8List frame) async {
    try {
      final written = await serial.writeWithTimeout(
        frame,
        timeout: writeTimeout,
      );
      if (!written) throw StateError('Serial transport rejected the write');
    } catch (error) {
      _activeCommandId = null;
      _activeResponse = null;
      dispose(error);
      unawaited(serial.performDisconnect());
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw ChameleonCommunicatorClosedException(_disposeCause);
    }
  }

  void dispose([Object? cause]) {
    if (_disposed) return;
    _disposed = true;
    _disposeCause = cause;
    final response = _activeResponse;
    if (response != null && !response.isCompleted) {
      response.completeError(ChameleonCommunicatorClosedException(cause));
    }
    _activeCommandId = null;
    _activeResponse = null;
    _uncertainResponseIds.clear();
    commandQueue.clear();
    _frameDecoder.reset();
  }

  Future<void> _invalidateAndDisconnect(Object cause) async {
    final serial = _serialInstance;
    dispose(cause);
    if (serial != null) {
      try {
        await serial.performDisconnect();
      } catch (_) {}
    }
  }

  Future<FirmwareVersion> getFirmwareVersion() async {
    final resp = await _sendChecked(ChameleonCommand.getAppVersion);
    if (resp.data.length != 2) {
      throw const FormatException('Invalid firmware version response');
    }

    // Check for legacy protocol
    if (resp.data[0] == 0 && resp.data[1] == 1) {
      return FirmwareVersion(legacyProtocol: true, version: 256);
    } else {
      return FirmwareVersion(
        legacyProtocol: false,
        version: bytesToU16(resp.data),
      );
    }
  }

  Future<String> getDeviceChipID() async {
    var resp = await sendCmd(ChameleonCommand.getDeviceChipID);
    return bytesToHex(resp!.data);
  }

  Future<String> getDeviceBLEAddress() async {
    var resp = await sendCmd(ChameleonCommand.getDeviceBLEAddress);
    return bytesToHexSpace(resp!.data).replaceAll(" ", ":");
  }

  Future<bool> isReaderDeviceMode() async {
    const command = ChameleonCommand.getDeviceMode;
    final resp = await sendCmd(command);
    if (resp == null || resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp?.status ?? 0xffff);
    }
    if (resp.data.length != 1 || resp.data[0] > 1) {
      throw const FormatException('Invalid device mode response');
    }
    return resp.data[0] == 1;
  }

  Future<void> setReaderDeviceMode(bool readerMode) async {
    const command = ChameleonCommand.changeDeviceMode;
    final resp = await sendCmd(
      command,
      data: Uint8List.fromList([readerMode ? 1 : 0]),
    );
    if (resp == null || resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp?.status ?? 0xffff);
    }
  }

  Future<CardData?> scan14443aTag() async {
    const command = ChameleonCommand.scan14ATag;
    final resp = await sendCmd(command);
    if (resp == null) {
      throw const ChameleonCommandException(command, 0xffff);
    }
    if (resp.status == 0x01 && resp.data.isEmpty) return null;
    if (resp.status != 0x00) {
      throw ChameleonCommandException(command, resp.status);
    }
    if (resp.data.isEmpty) {
      throw const FormatException('Empty successful ISO14443-A scan response');
    }
    final uidLength = resp.data[0];
    if (!const {4, 7, 10}.contains(uidLength) ||
        resp.data.length < uidLength + 5) {
      throw const FormatException('Invalid ISO14443-A scan response');
    }
    final atsLength = resp.data[uidLength + 4];
    if (resp.data.length != uidLength + 5 + atsLength) {
      throw const FormatException('Invalid ISO14443-A ATS length');
    }
    return CardData(
      uid: resp.data.sublist(1, uidLength + 1),
      atqa: Uint8List.fromList(
        resp.data.sublist(uidLength + 1, uidLength + 3).reversed.toList(),
      ),
      sak: resp.data[uidLength + 3],
      ats: resp.data.sublist(uidLength + 5),
    );
  }

  Future<CardData?> scan14443aTagKeep() async {
    const command = ChameleonCommand.hf14aScanKeep;
    final resp = await sendCmd(command);
    if (resp == null) {
      throw const ChameleonCommandException(command, 0xffff);
    }
    if (resp.status == 0x01 && resp.data.isEmpty) return null;
    if (resp.status != 0x00) {
      throw ChameleonCommandException(command, resp.status);
    }
    if (resp.data.isEmpty) {
      throw const FormatException('Empty successful ISO14443-A scan response');
    }
    final uidLength = resp.data[0];
    if (!const {4, 7, 10}.contains(uidLength) ||
        resp.data.length < uidLength + 5) {
      throw const FormatException('Invalid ISO14443-A scan response');
    }
    final atsLength = resp.data[uidLength + 4];
    if (resp.data.length != uidLength + 5 + atsLength) {
      throw const FormatException('Invalid ISO14443-A ATS length');
    }
    return CardData(
      uid: Uint8List.fromList(resp.data.sublist(1, uidLength + 1)),
      atqa: Uint8List.fromList(
        resp.data.sublist(uidLength + 1, uidLength + 3).reversed.toList(),
      ),
      sak: resp.data[uidLength + 3],
      ats: Uint8List.fromList(resp.data.sublist(uidLength + 5)),
    );
  }

  Future<Pm3Hf14aRawResponse> hf14aRaw(Pm3Hf14aRawRequest request) async {
    final command = ChameleonCommand.hf14ARawCommand;
    final response = await sendCmd(
      command,
      data: request.encode(),
      timeout: Duration(milliseconds: request.responseTimeoutMs + 2000),
    );
    if (response == null) {
      throw ChameleonCommandException(command, 0xffff);
    }
    return Pm3Hf14aRawResponse(status: response.status, data: response.data);
  }

  Future<void> setHf14aField(bool enabled) async {
    await _sendChecked(
      enabled
          ? ChameleonCommand.hf14aSetFieldOn
          : ChameleonCommand.hf14aSetFieldOff,
    );
  }

  Future<Pm3Hf14aConfig> getHf14aConfig() async {
    final response = await _sendChecked(ChameleonCommand.hf14aGetConfig);
    return Pm3Hf14aConfig.decode(response.data);
  }

  Future<void> setHf14aConfig(Pm3Hf14aConfig config) async {
    await _sendChecked(ChameleonCommand.hf14aSetConfig, data: config.encode());
  }

  Future<bool> detectMf1Support() async {
    // Detects if it is a Mifare Classic tag
    // true - Mifare Classic
    // false - any other card
    return (await sendCmd(ChameleonCommand.mf1SupportDetect))!.status == 0;
  }

  Future<NTLevel> getMf1NTLevel() async {
    // Get level of nt (weak/static/hard) in Mifare Classic
    var resp = (await sendCmd(ChameleonCommand.mf1NTLevelDetect))!.data[0];
    if (resp == 0) {
      return NTLevel.static;
    } else if (resp == 1) {
      return NTLevel.weak;
    } else if (resp == 2) {
      return NTLevel.hard;
    } else {
      return NTLevel.unknown;
    }
  }

  Future<DarksideResult> checkMf1Darkside() async {
    // Check card vulnerability to Mifare Classic darkside attack
    var message = (await sendCmd(
      ChameleonCommand.mf1DarksideAcquire,
      data: Uint8List.fromList([0x61, 0x03, 1, 2]),
      timeout: const Duration(seconds: 60),
    ))!;
    int status = message.status;
    if (message.data.isNotEmpty) {
      status = message.data[0];
    }

    if (status == 0) {
      return DarksideResult.vulnerable;
    } else if (status == 1) {
      return DarksideResult.cantFixNT;
    } else if (status == 2) {
      return DarksideResult.luckAuthOK;
    } else if (status == 3) {
      return DarksideResult.notSendingNACK;
    } else if (status == 4) {
      return DarksideResult.tagChanged;
    } else {
      return DarksideResult.fixed;
    }
  }

  Future<NTDistance> getMf1NTDistance(
    int block,
    int keyType,
    Uint8List keyKnown,
  ) async {
    // Get PRNG distance
    // keyType 0x60 if A key, 0x61 B key
    var resp = await sendCmd(
      ChameleonCommand.mf1NTDistanceDetect,
      data: Uint8List.fromList([keyType, block, ...keyKnown]),
    );
    if (resp == null || resp.status != 0 || resp.data.length < 8) {
      throw StateError('Invalid MIFARE Classic NT distance response');
    }

    final distance = bytesToU32(resp.data.sublist(4, 8));
    if (distance > 65534) {
      throw StateError('Invalid MIFARE Classic NT distance value: $distance');
    }

    return NTDistance(
      uid: bytesToU32(resp.data.sublist(0, 4)),
      distance: distance,
    );
  }

  Future<NestedNonces> getMf1NestedNonces(
    int block,
    int keyType,
    Uint8List knownKey,
    int targetBlock,
    int targetKeyType, {
    NTLevel level = NTLevel.weak,
    bool slow = false,
  }) async {
    // Collect nonces for nested attack
    // keyType 0x60 if A key, 0x61 B key
    int i = level == NTLevel.static ? 4 : 0;
    ChameleonCommand command = ChameleonCommand.mf1NestedAcquire;
    List<int> padding = [];
    if (level == NTLevel.static) {
      command = ChameleonCommand.mf1StaticNestedAcquire;
    } else if (level == NTLevel.hard) {
      command = ChameleonCommand.mf1HardNestedAcquire;
      padding = [slow ? 1 : 0];
    }

    var resp = await sendCmd(
      command,
      data: Uint8List.fromList([
        ...padding,
        keyType,
        block,
        ...knownKey,
        targetKeyType,
        targetBlock,
      ]),
      timeout: const Duration(seconds: 30),
    );
    if (resp == null || resp.status != 0) {
      throw StateError('MIFARE Classic nonce acquisition failed');
    }
    final payloadLength = resp.data.length - i;
    final itemLength = level == NTLevel.static ? 8 : 9;
    if (payloadLength < 0 || payloadLength % itemLength != 0) {
      throw StateError('Malformed MIFARE Classic nonce response');
    }
    var nonces = NestedNonces(nonces: []);

    while (i < resp.data.length) {
      if (level == NTLevel.static) {
        nonces.nonces.add(
          NestedNonce(
            nt: bytesToU32(resp.data.sublist(i, i + 4)),
            ntEnc: bytesToU32(resp.data.sublist(i + 4, i + 8)),
            parity: 0,
          ),
        );

        i += 8;
      } else {
        nonces.nonces.add(
          NestedNonce(
            nt: bytesToU32(resp.data.sublist(i, i + 4)),
            ntEnc: bytesToU32(resp.data.sublist(i + 4, i + 8)),
            parity: resp.data[i + 8],
          ),
        );

        i += 9;
      }
    }

    return nonces;
  }

  Future<Darkside> getMf1Darkside(
    int targetBlock,
    int targetKeyType,
    bool firstRecover,
    int syncMax,
  ) async {
    // Collect parameters for darkside attack
    // keyType 0x60 if A key, 0x61 B key
    var resp = await sendCmd(
      ChameleonCommand.mf1DarksideAcquire,
      data: Uint8List.fromList([
        targetKeyType,
        targetBlock,
        firstRecover ? 1 : 0,
        syncMax,
      ]),
      timeout: const Duration(seconds: 60),
    );

    if (resp!.data[0] != 0) {
      throw ("Not vulnerable to Darkside");
    }

    resp.data = resp.data.sublist(1);

    return Darkside(
      uid: bytesToU32(resp.data.sublist(0, 4)),
      nt1: bytesToU32(resp.data.sublist(4, 8)),
      par: bytesToU64(resp.data.sublist(8, 16)),
      ks1: bytesToU64(resp.data.sublist(16, 24)),
      nr: bytesToU32(resp.data.sublist(24, 28)),
      ar: bytesToU32(resp.data.sublist(28, 32)),
    );
  }

  Future<(int, NestedNonces, NestedNonces, Uint8List)?>
  getMf1StaticEncryptedNestedAcquire({
    int sectorCount = 16,
    int startingSector = 0,
  }) async {
    for (var key in gMifareClassicBackdoorKeys) {
      var resp = await sendCmd(
        ChameleonCommand.mf1StaticEncryptedNestedAcquire,
        data: Uint8List.fromList([...key, sectorCount, startingSector]),
      );
      if (resp!.status == 0) {
        var uid = bytesToU32(Uint8List.fromList(resp.data.sublist(0, 4)));
        int i = 4;
        var aNonces = NestedNonces(nonces: []);
        var bNonces = NestedNonces(nonces: []);

        while (i < resp.data.length) {
          aNonces.nonces.add(
            NestedNonce(
              nt: reconstructFullNt(resp.data, i),
              ntEnc: bytesToU32(resp.data.sublist(i + 3, i + 7)),
              parity: parityToInt(resp.data[i + 2]),
            ),
          );
          bNonces.nonces.add(
            NestedNonce(
              nt: reconstructFullNt(resp.data, i + 7),
              ntEnc: bytesToU32(resp.data.sublist(i + 10, i + 14)),
              parity: parityToInt(resp.data[i + 9]),
            ),
          );
          i += 14;
        }

        return (uid, aNonces, bNonces, key);
      }
    }

    return null;
  }

  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async {
    // Check if key is valid for block
    // keyType 0x60 if A key, 0x61 B key
    int status = (await sendCmd(
      ChameleonCommand.mf1CheckKey,
      data: Uint8List.fromList([keyType, block, ...key]),
    ))!.status;

    return status == 0;
  }

  Future<Uint8List?> mf1AuthMultipleKeys(
    int block,
    int keyType,
    List<Uint8List> keys,
  ) async {
    var resp = (await sendCmd(
      ChameleonCommand.mf1CheckKeysOnBlock,
      data: Uint8List.fromList([
        block,
        keyType,
        keys.length,
        ...keys.expand((key) => key),
      ]),
      timeout: Duration(seconds: (3 + keys.length).clamp(5, 20)),
    ));

    return resp!.status == 0 ? resp.data.sublist(1) : null;
  }

  Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key) async {
    // Read block
    // keyType 0x60 if A key, 0x61 B key
    return (await sendCmd(
      ChameleonCommand.mf1ReadBlock,
      data: Uint8List.fromList([keyType, block, ...key]),
    ))!.data;
  }

  // Auth once, read `count` consecutive blocks of the start block's sector.
  // Returns the blocks actually read (16 bytes each; may be fewer than count on
  // error, or empty on old firmware) so the caller can fall back to per-block.
  Future<List<Uint8List>> mf1ReadBlocks(
    int startBlock,
    int count,
    int keyType,
    Uint8List key,
  ) async {
    try {
      final resp = await sendCmd(
        ChameleonCommand.mf1ReadBlocks,
        data: Uint8List.fromList([keyType, startBlock, count, ...key]),
      );
      final data = resp?.data ?? Uint8List(0);
      final blocks = <Uint8List>[];
      for (var i = 0; i + 16 <= data.length; i += 16) {
        blocks.add(Uint8List.fromList(data.sublist(i, i + 16)));
      }
      return blocks;
    } catch (_) {
      return const []; // unsupported / timeout -> caller falls back
    }
  }

  // Check a key set against ALL sectors in one firmware call
  // (MF1_CHECK_KEYS_OF_SECTORS) — far fewer round-trips than per-sector checks.
  // mask: 10 bytes, 2 bits per sector in byte s~/4 at shift 6-(s%4)*2
  //   (bit 0b10 = skip keyA, 0b01 = skip keyB).
  // Returns sectorKey-index (sector*2 + keyType) -> found key, or null if the
  // command is unsupported / failed (so the caller can fall back per-sector).
  Future<Map<int, Uint8List>?> mf1CheckKeysOfSectors(
    Uint8List mask,
    List<Uint8List> keys,
  ) async {
    if (mask.length != 10 || keys.isEmpty || keys.length > 83) return null;
    try {
      final resp = await sendCmd(
        ChameleonCommand.mf1CheckKeysOfSectors,
        data: Uint8List.fromList([...mask, for (final k in keys) ...k]),
        // ~ auth time per key across the unmasked sectors, capped.
        timeout: Duration(seconds: (5 + keys.length).clamp(10, 90)),
      );
      if (resp == null || resp.data.length != 490) return null;
      final d = resp.data;
      final found = <int, Uint8List>{};
      for (var s = 0; s < 40; s++) {
        final shift = 6 - (s % 4) * 2;
        final bits = (d[s ~/ 4] >> shift) & 0x03;
        if (bits & 0x02 != 0) {
          found[s * 2] = Uint8List.fromList(
            d.sublist(10 + s * 12, 10 + s * 12 + 6),
          );
        }
        if (bits & 0x01 != 0) {
          found[s * 2 + 1] = Uint8List.fromList(
            d.sublist(10 + s * 12 + 6, 10 + s * 12 + 12),
          );
        }
      }
      return found;
    } catch (_) {
      return null;
    }
  }

  Future<bool> mf1WriteBlock(
    int block,
    int keyType,
    Uint8List key,
    Uint8List data,
  ) async {
    // Write block
    // keyType 0x60 if A key, 0x61 B key
    return (await sendCmd(
          ChameleonCommand.mf1WriteBlock,
          data: Uint8List.fromList([keyType, block, ...key, ...data]),
        ))!.status ==
        0;
  }

  Future<void> activateSlot(int slot) async {
    // Slot 0-7
    const command = ChameleonCommand.setActiveSlot;
    final resp = await sendCmd(command, data: Uint8List.fromList([slot]));
    if (resp == null || resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp?.status ?? 0xffff);
    }
  }

  Future<void> setSlotType(int slot, TagType type) async {
    const command = ChameleonCommand.setSlotTagType;
    final resp = await sendCmd(
      command,
      data: Uint8List.fromList([slot, ...u16ToBytes(type.value)]),
    );
    if (resp == null || resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp?.status ?? 0xffff);
    }
  }

  Future<void> setDefaultDataToSlot(int slot, TagType type) async {
    const command = ChameleonCommand.setSlotDataDefault;
    final resp = await sendCmd(
      command,
      data: Uint8List.fromList([slot, ...u16ToBytes(type.value)]),
    );
    if (resp == null || resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp?.status ?? 0xffff);
    }
  }

  Future<void> enableSlot(int slot, TagFrequency frequency, bool status) async {
    const command = ChameleonCommand.setSlotEnable;
    final resp = await sendCmd(
      command,
      data: Uint8List.fromList([slot, frequency.value, status ? 1 : 0]),
    );
    if (resp == null || resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp?.status ?? 0xffff);
    }
  }

  Future<bool> isMf1DetectionMode() async {
    final command = ChameleonCommand.mf1GetDetectionStatus;
    final resp = (await sendCmd(command))!;
    if (resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp.status);
    }
    if (resp.data.length != 1 || resp.data[0] > 1) {
      throw const FormatException('Invalid MF1 detection status response');
    }
    return resp.data[0] == 1;
  }

  Future<void> setMf1DetectionStatus(bool status) async {
    final command = ChameleonCommand.mf1SetDetectionEnable;
    final resp = await sendCmd(
      command,
      data: Uint8List.fromList([status ? 1 : 0]),
    );
    if (resp!.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp.status);
    }
  }

  Future<int> getMf1DetectionCount() async {
    final command = ChameleonCommand.mf1GetDetectionCount;
    final resp = (await sendCmd(command))!;
    if (resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp.status);
    }
    if (resp.data.length != 4) {
      throw const FormatException('Invalid MF1 detection count response');
    }
    final count = resp.data.buffer.asByteData().getUint32(0, Endian.big);
    if (count > 1000) {
      throw FormatException('Invalid MF1 detection count: $count');
    }
    return count;
  }

  Future<void> setMf1RandomUidMode(bool enabled) async {
    // Emulate a new random UID on each reader activation (per-slot).
    // Note: random UID fragments MFKey32 recovery; use a fixed UID for capture.
    final command = ChameleonCommand.mf1SetRandomUidMode;
    final resp = await sendCmd(
      command,
      data: Uint8List.fromList([enabled ? 1 : 0]),
    );
    if (resp!.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp.status);
    }
  }

  Future<bool> getMf1RandomUidMode() async {
    var resp = await sendCmd(ChameleonCommand.mf1GetRandomUidMode);
    return resp!.data[0] == 1;
  }

  Future<void> setMf1ReaderKeysAnim(bool enabled) async {
    // Toggle the center-out rainbow LED animation used during reader-key capture.
    final command = ChameleonCommand.mf1SetReaderKeysAnim;
    final resp = await sendCmd(
      command,
      data: Uint8List.fromList([enabled ? 1 : 0]),
    );
    if (resp!.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp.status);
    }
  }

  Future<List<DetectionResult>> getMf1DetectionRecords(int count) async {
    if (count < 0 || count > 1000) {
      throw RangeError.range(count, 0, 1000, 'count');
    }
    final records = <DetectionResult>[];
    while (records.length < count) {
      final command = ChameleonCommand.mf1GetDetectionResult;
      final request = Uint8List(4)
        ..buffer.asByteData().setUint32(0, records.length, Endian.big);
      final response = (await sendCmd(command, data: request))!;
      if (response.status != chameleonStatusSuccess) {
        throw ChameleonCommandException(command, response.status);
      }
      final data = response.data;
      if (data.isEmpty || data.length % 18 != 0) {
        throw const FormatException('Invalid MF1 detection log page');
      }

      for (
        var offset = 0;
        offset + 18 <= data.length && records.length < count;
        offset += 18
      ) {
        records.add(
          DetectionResult(
            block: data[offset],
            type: 0x60 + (data[offset + 1] & 0x01),
            isNested: ((data[offset + 1] >> 1) & 0x01) == 0x01,
            uid: bytesToU32(data.sublist(offset + 2, offset + 6)),
            nt: bytesToU32(data.sublist(offset + 6, offset + 10)),
            nr: bytesToU32(data.sublist(offset + 10, offset + 14)),
            ar: bytesToU32(data.sublist(offset + 14, offset + 18)),
          ),
        );
      }
    }
    return records;
  }

  Future<Map<int, Map<int, Map<String, List<DetectionResult>>>>>
  getMf1DetectionResult(int count) async {
    final resultList = await getMf1DetectionRecords(count);

    // Classify
    Map<int, Map<int, Map<String, List<DetectionResult>>>> resultMap = {};
    for (DetectionResult item in resultList) {
      if (!resultMap.containsKey(item.uid)) {
        resultMap[item.uid] = {};
      }

      int block = item.block;
      if (!resultMap[item.uid]!.containsKey(block)) {
        resultMap[item.uid]![block] = {};
      }

      String typeChr = item.type == 0x60 ? 'A' : 'B';
      if (!resultMap[item.uid]![block]!.containsKey(typeChr)) {
        resultMap[item.uid]![block]![typeChr] = [];
      }

      resultMap[item.uid]![block]![typeChr]!.add(item);
    }

    return resultMap;
  }

  Future<void> setMf1BlockData(int startBlock, Uint8List blocks) async {
    // Set block data in emulator
    // Can contain multiple block data, automatically incremented from startBlock
    await _sendChecked(
      ChameleonCommand.mf1LoadBlockData,
      data: Uint8List.fromList([startBlock & 0xFF, ...blocks]),
    );
  }

  Future<void> setMf1AntiCollision(CardData card) async {
    await _sendChecked(
      ChameleonCommand.mf1SetAntiCollision,
      data: Uint8List.fromList([
        card.uid.length,
        ...card.uid,
        ...card.atqa.reversed,
        card.sak,
        card.ats.length,
        ...card.ats,
      ]),
    );
  }

  Future<EM410XCard?> readEM410X() async {
    var resp = await sendCmd(ChameleonCommand.scanEM410Xtag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return EM410XCard.fromBytes(resp.data);
  }

  Future<HIDCard?> readHIDProx() async {
    var resp = await sendCmd(ChameleonCommand.scanHIDProxTag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return HIDCard.fromBytes(resp.data);
  }

  Future<VikingCard?> readViking() async {
    var resp = await sendCmd(ChameleonCommand.scanVikingTag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return VikingCard.fromBytes(resp.data);
  }

  Future<PacCard?> readPac() async {
    var resp = await sendCmd(ChameleonCommand.scanPacTag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return PacCard.fromBytes(resp.data);
  }

  Future<IoProxCard?> readIoProx() async {
    var resp = await sendCmd(ChameleonCommand.scanIoProxTag);

    if (resp!.data.isEmpty) {
      return null;
    }

    return IoProxCard.fromBytes(resp.data);
  }

  Future<Uint8List?> readJablotron() async {
    final response = await sendCmd(ChameleonCommand.scanJablotronTag);
    if (response == null) {
      throw const ChameleonCommandException(
        ChameleonCommand.scanJablotronTag,
        0xffff,
      );
    }
    if (response.status == 0x41 && response.data.isEmpty) return null;
    if (response.status != 0x40) {
      throw ChameleonCommandException(
        ChameleonCommand.scanJablotronTag,
        response.status,
      );
    }
    if (response.data.length != 5) {
      throw const FormatException('Invalid Jablotron scan response');
    }
    return Uint8List.fromList(response.data);
  }

  Future<Uint8List> readLfAdc() async {
    const command = ChameleonCommand.readLfAdc;
    final response = await sendCmd(command);
    if (response == null || response.status != 0x40) {
      throw ChameleonCommandException(command, response?.status ?? 0xffff);
    }
    if (response.data.isEmpty) {
      throw const FormatException('Empty LF ADC response');
    }
    return Uint8List.fromList(response.data);
  }

  Future<Pm3IoProxData> decodeIoProxRaw(Uint8List raw) async {
    if (raw.length != 8) {
      throw ArgumentError.value(raw.length, 'raw.length', 'must be 8');
    }
    final response = await _sendChecked(
      ChameleonCommand.ioProxDecodeRaw,
      data: raw,
    );
    return Pm3IoProxData.decode(response.data);
  }

  Future<Pm3IoProxData> composeIoProxId({
    required int version,
    required int facilityCode,
    required int cardNumber,
  }) async {
    if (version < 0 || version > 0xff) {
      throw RangeError.range(version, 0, 0xff, 'version');
    }
    if (facilityCode < 0 || facilityCode > 0xff) {
      throw RangeError.range(facilityCode, 0, 0xff, 'facilityCode');
    }
    if (cardNumber < 0 || cardNumber > 0xffff) {
      throw RangeError.range(cardNumber, 0, 0xffff, 'cardNumber');
    }
    final response = await _sendChecked(
      ChameleonCommand.ioProxComposeId,
      data: Uint8List.fromList([
        version,
        facilityCode,
        cardNumber >> 8,
        cardNumber & 0xff,
      ]),
    );
    return Pm3IoProxData.decode(response.data);
  }

  Future<void> setEM410XEmulatorID(Uint8List uid) async {
    if (uid.length != 5 && uid.length != 13) {
      throw ArgumentError.value(uid.length, 'uid.length', 'must be 5 or 13');
    }
    await _setLfEmulatorId(ChameleonCommand.setEM410XemulatorID, uid);
  }

  Future<void> setHIDProxEmulatorID(Uint8List uid) async {
    await _setLfEmulatorId(
      ChameleonCommand.setHIDProxEmulatorID,
      uid,
      expectedLength: 13,
    );
  }

  Future<void> setVikingEmulatorID(Uint8List uid) async {
    await _setLfEmulatorId(
      ChameleonCommand.setVikingEmulatorID,
      uid,
      expectedLength: 4,
    );
  }

  Future<void> setPacEmulatorID(Uint8List uid) async {
    await _setLfEmulatorId(
      ChameleonCommand.setPacEmulatorID,
      uid,
      expectedLength: 8,
    );
  }

  Future<void> setIoProxEmulatorID(Uint8List uid) async {
    await _setLfEmulatorId(
      ChameleonCommand.setIoProxEmulatorID,
      uid,
      expectedLength: 16,
    );
  }

  Future<void> setIdteckEmulatorID(Uint8List uid) async {
    await _setLfEmulatorId(
      ChameleonCommand.setIdteckEmulatorID,
      uid,
      expectedLength: 8,
    );
  }

  Future<void> _setLfEmulatorId(
    ChameleonCommand command,
    Uint8List uid, {
    int? expectedLength,
  }) async {
    if (expectedLength != null && uid.length != expectedLength) {
      throw ArgumentError.value(
        uid.length,
        'uid.length',
        'must be $expectedLength',
      );
    }
    final response = await sendCmd(command, data: uid);
    if (response == null) {
      throw StateError('Command ${command.name} returned no response');
    }
    if (response.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, response.status);
    }
  }

  Future<void> writeEM410XtoT55XX(
    Uint8List uid,
    Uint8List newKey,
    List<Uint8List> oldKeys,
  ) async {
    if (uid.length == 5) {
      await _writeT55xx(
        ChameleonCommand.writeEM410XtoT5577,
        uid,
        newKey,
        oldKeys,
      );
      return;
    }
    if (uid.length == 13) {
      await _writeT55xx(
        ChameleonCommand.writeEM410XElectraToT5577,
        uid,
        newKey,
        oldKeys,
      );
      return;
    }
    throw ("Invalid EM410X UID length");
  }

  Future<void> writeHIDProxToT55XX(
    Uint8List uid,
    Uint8List newKey,
    List<Uint8List> oldKeys,
  ) async {
    await _writeT55xx(
      ChameleonCommand.writeHIDProxToT5577,
      uid,
      newKey,
      oldKeys,
    );
  }

  Future<void> writeVikingToT55XX(
    Uint8List uid,
    Uint8List newKey,
    List<Uint8List> oldKeys,
  ) async {
    await _writeT55xx(
      ChameleonCommand.writeVikingToT5577,
      uid,
      newKey,
      oldKeys,
    );
  }

  Future<void> writePacToT55XX(
    Uint8List uid,
    Uint8List newKey,
    List<Uint8List> oldKeys,
  ) async {
    await _writeT55xx(ChameleonCommand.writePacToT5577, uid, newKey, oldKeys);
  }

  Future<void> writeIoProxToT55XX(
    Uint8List uid,
    Uint8List newKey,
    List<Uint8List> oldKeys,
  ) async {
    await _writeT55xx(
      ChameleonCommand.writeIoProxToT5577,
      uid,
      newKey,
      oldKeys,
    );
  }

  Future<void> _writeT55xx(
    ChameleonCommand command,
    Uint8List uid,
    Uint8List newKey,
    List<Uint8List> oldKeys,
  ) async {
    if (newKey.length != 4) {
      throw ArgumentError.value(newKey.length, 'newKey.length', 'must be 4');
    }
    if (oldKeys.isEmpty || oldKeys.length > 255) {
      throw ArgumentError.value(
        oldKeys.length,
        'oldKeys.length',
        'must be between 1 and 255',
      );
    }
    if (oldKeys.any((key) => key.length != 4)) {
      throw ArgumentError('Every old T55xx password must contain 4 bytes');
    }
    await _sendChecked(
      command,
      data: Uint8List.fromList([
        ...uid,
        ...newKey,
        ...oldKeys.expand((key) => key),
      ]),
      allowedStatuses: const {0x40},
    );
  }

  Future<Uint8List> lfSniff({int timeoutMs = 2000}) async {
    timeoutMs = timeoutMs.clamp(1, 10000);
    final resp = await sendCmd(
      ChameleonCommand.lfSniff,
      data: Uint8List.fromList([(timeoutMs >> 8) & 0xFF, timeoutMs & 0xFF]),
      timeout: Duration(seconds: timeoutMs ~/ 1000 + 2),
    );

    if (resp == null) {
      throw ('No response from LF sniff command');
    }

    if (resp.status == 0x40) {
      return resp.data;
    }

    if (resp.status == 0x41) {
      return Uint8List(0);
    }

    throw ('LF sniff failed with status 0x${resp.status.toRadixString(16)}');
  }

  // Run a reader-side ISO14443A + Crypto1 auth against a real card and return
  // all wire frames (same buffer format as hf14aSniff, parseable with
  // parseHf14aSniffFrames). key_type is 0x60 (A) or 0x61 (B).
  Future<Uint8List> hf14aAuthTrace(
    int block,
    int keyType,
    Uint8List key, {
    int timeoutMs = 5000,
  }) async {
    timeoutMs = timeoutMs.clamp(1, 30000);
    final resp = await sendCmd(
      ChameleonCommand.hf14aAuthTrace,
      data: Uint8List.fromList([
        keyType,
        block & 0xFF,
        ...key,
        (timeoutMs >> 8) & 0xFF,
        timeoutMs & 0xFF,
      ]),
      timeout: Duration(seconds: timeoutMs ~/ 1000 + 5),
    );
    if (resp == null) {
      throw ('No response from auth-trace command');
    }
    return resp.data;
  }

  // Select a card (with RATS) and send one ISO14443-4 T=CL APDU. Returns the
  // APDU response bytes (no PCB/CRC).
  Future<Uint8List> hf14a4ReaderApdu(Uint8List apdu) async {
    final resp = await sendCmd(
      ChameleonCommand.hf14a4ReaderApdu,
      data: apdu,
      timeout: const Duration(seconds: 3),
    );
    if (resp == null) {
      throw ('No response from reader APDU command');
    }
    if (resp.status != 0x00) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4ReaderApdu,
        resp.status,
      );
    }
    return resp.data;
  }

  Future<IsoDepReaderSessionInfo> hf14a4ReaderSessionStart() =>
      _hf14a4ReaderSessionStart(ChameleonCommand.hf14a4ReaderSessionStart);

  Future<IsoDepReaderSessionInfo> hf14a4ReaderSessionStartAppleTransit() =>
      _hf14a4ReaderSessionStart(
        ChameleonCommand.hf14a4ReaderSessionStartAppleTransit,
      );

  Future<IsoDepReaderSessionInfo> _hf14a4ReaderSessionStart(
    ChameleonCommand command,
  ) async {
    final resp = await sendCmd(command, timeout: isoDepSessionControlTimeout);
    if (resp == null) {
      throw const FormatException('Missing ISO-DEP session response');
    }
    if (resp.status != 0x00) {
      throw ChameleonCommandException(command, resp.status);
    }
    final data = resp.data;
    try {
      if (data.length < 15) {
        throw const FormatException('Truncated ISO-DEP session metadata');
      }
      final sessionId = bytesToU32(data.sublist(0, 4));
      final uidLength = data[4];
      if (sessionId == 0 || !const [4, 7, 10].contains(uidLength)) {
        throw const FormatException('Invalid ISO-DEP session metadata');
      }
      final fixedEnd = 5 + uidLength + 2 + 1 + 1;
      if (data.length < fixedEnd) {
        throw const FormatException('Truncated ISO-DEP card metadata');
      }
      final atsLength = data[fixedEnd - 1];
      if (atsLength < 2 || data.length != fixedEnd + atsLength) {
        throw const FormatException('Invalid ISO-DEP ATS metadata');
      }
      final sak = data[5 + uidLength + 2];
      if ((sak & 0x20) == 0) {
        throw const FormatException('Backend card is not ISO-DEP capable');
      }
      return IsoDepReaderSessionInfo(
        sessionId: sessionId,
        card: CardData(
          uid: Uint8List.fromList(data.sublist(5, 5 + uidLength)),
          atqa: Uint8List.fromList(
            data.sublist(5 + uidLength, 5 + uidLength + 2),
          ),
          sak: sak,
          ats: Uint8List.fromList(data.sublist(fixedEnd)),
        ),
      );
    } on FormatException catch (error, stackTrace) {
      final sessionId = data.length >= 4 ? bytesToU32(data.sublist(0, 4)) : 0;
      var cleanupConfirmed = false;
      Object? cleanupError;
      if (sessionId != 0) {
        try {
          await hf14a4ReaderSessionStop(sessionId);
          cleanupConfirmed = true;
        } catch (caught) {
          cleanupError = caught;
        }
      }
      final metadataError = IsoDepReaderSessionStartMetadataException(
        command: command,
        formatError: error,
        sessionId: sessionId == 0 ? null : sessionId,
        cleanupConfirmed: cleanupConfirmed,
        cleanupError: cleanupError,
      );
      if (!cleanupConfirmed) {
        unawaited(_invalidateAndDisconnect(metadataError));
      }
      Error.throwWithStackTrace(metadataError, stackTrace);
    }
  }

  Future<Uint8List> hf14a4ReaderSessionExchange(
    int sessionId,
    Uint8List apdu,
  ) async {
    if (sessionId <= 0 || sessionId > 0xffffffff) {
      throw RangeError.range(sessionId, 1, 0xffffffff, 'sessionId');
    }
    if (apdu.isEmpty || apdu.length > 512) {
      throw RangeError.range(apdu.length, 1, 512, 'APDU length');
    }
    const command = ChameleonCommand.hf14a4ReaderSessionExchange;
    final resp = await sendCmd(
      command,
      data: Uint8List.fromList([...u32ToBytes(sessionId), ...apdu]),
      timeout: const Duration(seconds: 6),
    );
    if (resp == null) {
      throw const FormatException('Missing ISO-DEP exchange response');
    }
    if (resp.status != 0x00) {
      if (resp.data.isNotEmpty && resp.data.length != 3) {
        throw const FormatException(
          'Malformed ISO-DEP exchange failure diagnostics',
        );
      }
      throw IsoDepReaderSessionExchangeException(
        resp.status,
        isoDepError: resp.data.length == 3 ? resp.data[0] : null,
        rfStatus: resp.data.length == 3 ? resp.data[1] : null,
        wtxCount: resp.data.length == 3 ? resp.data[2] : null,
      );
    }
    if (resp.data.length < 2 || resp.data.length > 512) {
      throw const FormatException('Invalid ISO-DEP APDU response length');
    }
    return Uint8List.fromList(resp.data);
  }

  Future<void> hf14a4ReaderSessionStop(int sessionId) async {
    if (sessionId <= 0 || sessionId > 0xffffffff) {
      throw RangeError.range(sessionId, 1, 0xffffffff, 'sessionId');
    }
    const command = ChameleonCommand.hf14a4ReaderSessionStop;
    final resp = await sendCmd(
      command,
      data: u32ToBytes(sessionId),
      timeout: isoDepSessionControlTimeout,
    );
    if (resp == null) {
      throw const FormatException('Missing ISO-DEP stop response');
    }
    if (resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, resp.status);
    }
    if (resp.data.isNotEmpty) {
      throw const FormatException('Unexpected ISO-DEP stop payload');
    }
  }

  /// Idempotently closes a relay backend after an uncertain exchange.
  ///
  /// The STOP response is ordered after every earlier exchange response on both
  /// USB and BLE. Once it arrives, any quarantined 6012 response is necessarily
  /// consumed or obsolete, so a new session can safely use 6012 again.
  Future<void> hf14a4ReaderSessionReset(int sessionId) async {
    if (sessionId <= 0 || sessionId > 0xffffffff) {
      throw RangeError.range(sessionId, 1, 0xffffffff, 'sessionId');
    }
    const command = ChameleonCommand.hf14a4ReaderSessionStop;
    final resp = await sendCmd(
      command,
      data: u32ToBytes(sessionId),
      timeout: isoDepSessionControlTimeout,
    );
    if (resp == null) {
      throw const FormatException('Missing ISO-DEP reset response');
    }
    if (resp.data.isNotEmpty) {
      throw const FormatException('Unexpected ISO-DEP reset payload');
    }
    if (!const {chameleonStatusSuccess, 0x60, 0x66}.contains(resp.status)) {
      throw ChameleonCommandException(command, resp.status);
    }
    _uncertainResponseIds.remove(
      ChameleonCommand.hf14a4ReaderSessionExchange.value,
    );
  }

  // Full EMV contactless scan in one firmware call (field cycle, select, RATS,
  // PPSE, SELECT AID, GPO, READ RECORDs). Returns the raw buffer:
  //   uid_len(1) uid(n) atqa(2) sak(1) ats_len(1) ats(m) num_apdus(1)
  //   then per APDU: cmd_len(1) cmd(n) resp_len_le(2) resp(m)
  // Read-only EMV scan when amount is null; with a 6-byte n12 BCD amount the
  // firmware also runs GENERATE AC (offline purchase simulation — no bank).
  Future<Uint8List> hf14a4EmvScan({Uint8List? amount}) async {
    if (amount != null && amount.length != 6) {
      throw ArgumentError('EMV amount must be 6 bytes (n12 BCD)');
    }
    final resp = await sendCmd(
      ChameleonCommand.hf14a4EmvScan,
      data: amount ?? Uint8List(0),
      timeout: const Duration(seconds: 12),
    );
    if (resp == null) {
      throw const ChameleonCommandException(
        ChameleonCommand.hf14a4EmvScan,
        0xffff,
      );
    }
    if (resp.status == 0x01 && resp.data.isEmpty) return Uint8List(0);
    if (resp.status != 0x00) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4EmvScan,
        resp.status,
      );
    }
    if (resp.data.isEmpty) {
      throw const FormatException('Empty successful EMV scan response');
    }
    return resp.data;
  }

  // Enumerate a MIFARE DESFire card in one call (GetVersion + GetApplicationIDs
  // + per-AID SelectApplication/GetFileIDs). Same packed buffer as EMV scan.
  Future<Uint8List> hf14a4DesfireScan() async {
    final resp = await sendCmd(
      ChameleonCommand.hf14a4DesfireScan,
      data: Uint8List(0),
      timeout: const Duration(seconds: 10),
    );
    if (resp == null) {
      throw const ChameleonCommandException(
        ChameleonCommand.hf14a4DesfireScan,
        0xffff,
      );
    }
    if (resp.status == 0x01 && resp.data.isEmpty) return Uint8List(0);
    if (resp.status != 0x00) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4DesfireScan,
        resp.status,
      );
    }
    if (resp.data.isEmpty) {
      throw const FormatException('Empty successful DESFire scan response');
    }
    return resp.data;
  }

  Future<EmvTraceStartResponse> hf14a4EmvTraceStart(
    EmvTraceRequest request,
  ) async {
    final resp = await sendCmd(
      ChameleonCommand.hf14a4EmvTraceStart,
      data: request.encode(),
      timeout: Duration(
        milliseconds: (request.budgetMs == 0 ? 12000 : request.budgetMs) + 5000,
      ),
    );
    if (resp == null) {
      throw ('No response from EMV trace START command');
    }
    // START returns the HF result directly (0 = card, 1 = no card).
    if (resp.status != 0x00 && resp.status != 0x01) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4EmvTraceStart,
        resp.status,
      );
    }
    return EmvTraceStartResponse.parse(resp.data);
  }

  Future<EmvTraceMeta> hf14a4EmvTraceMeta(int scanId) async {
    final resp = await sendCmd(
      ChameleonCommand.hf14a4EmvTraceMeta,
      data: encodeEmvTraceSessionRequest(scanId),
    );
    if (resp == null) {
      throw ('No response from EMV trace META command');
    }
    if (resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4EmvTraceMeta,
        resp.status,
      );
    }
    final meta = EmvTraceMeta.parse(resp.data);
    if (meta.scanId != scanId) {
      throw const FormatException('EMV trace META session mismatch');
    }
    return meta;
  }

  Future<EmvTracePage> hf14a4EmvTraceGet(
    int scanId,
    int startRecord, {
    int maxPayload = 4096,
  }) async {
    final resp = await sendCmd(
      ChameleonCommand.hf14a4EmvTraceGet,
      data: encodeEmvTraceGetRequest(scanId, startRecord, maxPayload),
    );
    if (resp == null) {
      throw ('No response from EMV trace GET command');
    }
    if (resp.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4EmvTraceGet,
        resp.status,
      );
    }
    if (resp.data.length > maxPayload) {
      throw const FormatException(
        'EMV trace GET response exceeds requested payload size',
      );
    }
    final page = EmvTracePage.parse(resp.data);
    if (page.scanId != scanId || page.startRecord != startRecord) {
      throw const FormatException('EMV trace GET session/cursor mismatch');
    }
    return page;
  }

  Future<EmvTraceCapture> hf14a4EmvTrace(
    EmvTraceRequest request, {
    int maxPayload = 4096,
  }) async {
    final start = await hf14a4EmvTraceStart(request);
    final meta = await hf14a4EmvTraceMeta(start.scanId);
    if (meta.state != EmvTraceState.complete &&
        meta.state != EmvTraceState.aborted) {
      throw const FormatException('EMV trace META session is not terminal');
    }
    if (start.state != meta.state || start.flags != meta.flags) {
      throw const FormatException('EMV trace START/META mismatch');
    }

    final pages = <EmvTracePage>[];
    var cursor = 0;
    while (cursor < meta.storedRecords) {
      final page = await hf14a4EmvTraceGet(
        meta.scanId,
        cursor,
        maxPayload: maxPayload,
      );
      if (page.nextRecord <= cursor) {
        throw const FormatException('EMV trace GET made no cursor progress');
      }
      if (page.nextRecord > meta.storedRecords) {
        throw const FormatException('EMV trace GET cursor exceeds META count');
      }
      pages.add(page);
      cursor = page.nextRecord;
    }
    return EmvTraceCapture.assemble(meta, pages, start: start);
  }

  Future<IsoDepDebugCounters> hf14a4DebugCounters() async {
    final response = await sendCmd(ChameleonCommand.hf14a4DebugCounters);
    if (response == null) {
      throw StateError('ISO-DEP debug counter command returned no response');
    }
    if (response.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4DebugCounters,
        response.status,
      );
    }
    if (response.data.length != 4) {
      throw const FormatException(
        'ISO-DEP debug counter response must be exactly 4 bytes',
      );
    }
    return IsoDepDebugCounters(
      receivedIBlocks: response.data[0],
      transmittedIBlocks: response.data[1],
      lastReceivedPcb: response.data[2],
      lastStaticResponseMatch: response.data[3],
    );
  }

  // ---- ISO14443-4 card emulation (terminal robustness testing in a lab) ----
  // Set the emulated card's anti-collision data (UID/ATQA/SAK/ATS).
  Future<void> hf14a4SetAntiColl(
    Uint8List uid,
    Uint8List atqa,
    int sak,
    Uint8List ats,
  ) async {
    if (![4, 7, 10].contains(uid.length) ||
        atqa.length != 2 ||
        ats.length > 255) {
      throw ArgumentError('invalid anti-collision parameters');
    }
    // ATQA reversed to wire order, matching setMf1AntiCollision.
    final response = await sendCmd(
      ChameleonCommand.hf14a4SetAntiColl,
      data: Uint8List.fromList([
        uid.length,
        ...uid,
        ...atqa.reversed,
        sak & 0xFF,
        ats.length,
        ...ats,
      ]),
    );
    if (response == null || response.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4SetAntiColl,
        response?.status ?? 0xffff,
      );
    }
  }

  // Clear all preloaded static APDU responses.
  Future<void> hf14a4ClearStaticResponses() async {
    final response = await sendCmd(
      ChameleonCommand.hf14a4StaticResp,
      data: Uint8List.fromList([0]),
    );
    if (response == null || response.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4StaticResp,
        response?.status ?? 0xffff,
      );
    }
  }

  // Add a static command-prefix -> response rule for the emulated card.
  Future<void> hf14a4AddStaticResponse(
    Uint8List command,
    Uint8List response,
  ) async {
    if (command.isEmpty || command.length > 16 || response.length > 260) {
      throw ArgumentError('invalid static response (cmd 1..16, resp <=260)');
    }
    final result = await sendCmd(
      ChameleonCommand.hf14a4StaticResp,
      data: Uint8List.fromList([
        command.length,
        ...command,
        (response.length >> 8) & 0xFF,
        response.length & 0xFF,
        ...response,
      ]),
    );
    if (result == null || result.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(
        ChameleonCommand.hf14a4StaticResp,
        result?.status ?? 0xffff,
      );
    }
  }

  Future<Uint8List> hf14aSniff({int timeoutMs = 5000}) async {
    timeoutMs = timeoutMs.clamp(1, 30000);
    final resp = await sendCmd(
      ChameleonCommand.hf14aSniff,
      data: Uint8List.fromList([(timeoutMs >> 8) & 0xFF, timeoutMs & 0xFF]),
      timeout: Duration(seconds: timeoutMs ~/ 1000 + 5),
    );

    if (resp == null) {
      throw ('No response from HF sniff command');
    }

    if (resp.status == 0x68 || resp.status == 0x00) {
      return resp.data;
    }

    if (resp.status == 0x01) {
      return Uint8List(0);
    }

    throw ('HF sniff failed with status 0x${resp.status.toRadixString(16)}');
  }

  Future<void> writeIdteckToT55XX(
    Uint8List uid,
    Uint8List newKey,
    List<Uint8List> oldKeys,
  ) async {
    await _writeT55xx(
      ChameleonCommand.writeIdteckToT5577,
      uid,
      newKey,
      oldKeys,
    );
  }

  Future<void> writeJablotronToT55XX(
    Uint8List uid,
    Uint8List newKey,
    List<Uint8List> oldKeys,
  ) async {
    if (uid.length != 5) {
      throw ArgumentError.value(uid.length, 'uid.length', 'must be 5');
    }
    await _writeT55xx(
      ChameleonCommand.writeJablotronToT5577,
      uid,
      newKey,
      oldKeys,
    );
  }

  Future<void> writeT55xxBlock({
    required int block,
    required int word,
    int? password,
    required bool page1,
  }) async {
    final maxBlock = page1 ? 3 : 7;
    if (block < 0 || block > maxBlock) {
      throw RangeError.range(block, 0, maxBlock, 'block');
    }
    if (word < 0 || word > 0xffffffff) {
      throw RangeError.range(word, 0, 0xffffffff, 'word');
    }
    if (password != null && (password < 0 || password > 0xffffffff)) {
      throw RangeError.range(password, 0, 0xffffffff, 'password');
    }
    final passwordValue = password ?? 0;
    await _sendChecked(
      ChameleonCommand.writeT55xxBlock,
      data: Uint8List.fromList([
        block,
        ...u32ToBytes(word),
        password == null ? 0 : 1,
        ...u32ToBytes(passwordValue),
        page1 ? 1 : 0,
      ]),
      allowedStatuses: const {0x40},
    );
  }

  Future<void> setSlotTagName(
    int index,
    String name,
    TagFrequency frequency,
  ) async {
    await _sendChecked(
      ChameleonCommand.setSlotTagNick,
      data: Uint8List.fromList([index, frequency.value, ...utf8.encode(name)]),
    );
  }

  Future<String> getSlotTagName(int index, TagFrequency frequency) async {
    final resp = await _sendChecked(
      ChameleonCommand.getSlotTagNick,
      data: Uint8List.fromList([index, frequency.value]),
    );
    if (resp.data.length > 32) {
      throw const FormatException('Invalid slot nickname response');
    }
    return utf8.decode(resp.data, allowMalformed: true);
  }

  Future<List<SlotNames>> getSlotTagNames() async {
    final resp = await _sendChecked(ChameleonCommand.getAllSlotNicks);
    List<SlotNames> slots = List.generate(8, (_) => SlotNames());

    int i = 0;
    int index = 0;

    while (i < resp.data.length && index < 8) {
      int hfLen = resp.data[i];
      i++;
      if (hfLen > 32 || i + hfLen > resp.data.length) {
        throw const FormatException('Invalid HF slot nickname length');
      }
      if (hfLen > 0) {
        slots[index].hf = utf8.decode(
          resp.data.sublist(i, i + hfLen),
          allowMalformed: true,
        );
        i += hfLen;
      } else {
        slots[index].hf = '';
        i += hfLen;
      }

      if (i >= resp.data.length) {
        throw const FormatException('Missing LF slot nickname length');
      }
      int lfLen = resp.data[i];
      i++;
      if (lfLen > 32 || i + lfLen > resp.data.length) {
        throw const FormatException('Invalid LF slot nickname length');
      }
      if (lfLen > 0) {
        slots[index].lf = utf8.decode(
          resp.data.sublist(i, i + lfLen),
          allowMalformed: true,
        );
        i += lfLen;
      } else {
        slots[index].lf = '';
        i += lfLen;
      }

      index++;
    }
    if (index != 8 || i != resp.data.length) {
      throw const FormatException('Invalid all-slot nickname response');
    }

    return slots;
  }

  Future<void> deleteSlotInfo(int index, TagFrequency frequency) async {
    await _sendChecked(
      ChameleonCommand.deleteSlotInfo,
      data: Uint8List.fromList([index, frequency.value]),
    );
  }

  Future<void> saveSlotData() async {
    final response = await sendCmd(ChameleonCommand.saveSlotNicks);
    if (response == null || response.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(
        ChameleonCommand.saveSlotNicks,
        response?.status ?? -1,
      );
    }
  }

  Future<MifareClassicActiveSlotSnapshot> beginActiveSlotSnapshot() async {
    await initializeCapabilities();
    if (supportsCommandSync(ChameleonCommand.activeSlotSnapshot) != true) {
      throw const ChameleonUnsupportedCommandException(
        ChameleonCommand.activeSlotSnapshot,
      );
    }
    final response = await _sendChecked(
      ChameleonCommand.activeSlotSnapshot,
      data: Uint8List.fromList([
        activeSlotSnapshotProtocolVersion,
        _activeSlotSnapshotBegin,
      ]),
    );
    final data = response.data;
    final revision = data.length >= 13 ? bytesToU32(data.sublist(9, 13)) : 0;
    final tagType = data.length >= 5
        ? numberToChameleonTag(bytesToU16(data.sublist(3, 5)))
        : TagType.unknown;
    final ownerGeneration = data.length >= 9
        ? bytesToU32(data.sublist(5, 9))
        : 0;
    final malformed =
        data.length != 13 ||
        data[0] != activeSlotSnapshotProtocolVersion ||
        data[1] != _activeSlotSnapshotBegin ||
        data[2] > 7 ||
        !isMifareClassic(tagType) ||
        ownerGeneration == 0 ||
        revision == 0;
    if (malformed) {
      const error = FormatException(
        'Invalid active-slot snapshot BEGIN response',
      );
      if (revision != 0) {
        try {
          await _abortActiveSlotSnapshotRevision(revision);
        } catch (_) {
          await _invalidateAndDisconnect(error);
        }
      } else {
        await _invalidateAndDisconnect(error);
      }
      throw error;
    }
    return MifareClassicActiveSlotSnapshot(
      slot: data[2],
      tagType: tagType,
      ownerGeneration: ownerGeneration,
      revision: revision,
    );
  }

  Future<void> saveReleaseActiveSlotSnapshot(
    MifareClassicActiveSlotSnapshot snapshot,
  ) async {
    try {
      final response = await _sendChecked(
        ChameleonCommand.activeSlotSnapshot,
        data: Uint8List.fromList([
          activeSlotSnapshotProtocolVersion,
          _activeSlotSnapshotSaveRelease,
          ...u32ToBytes(snapshot.revision),
        ]),
        timeout: snapshotSaveTimeout,
      );
      _validateActiveSlotSnapshotEnd(
        response.data,
        _activeSlotSnapshotSaveRelease,
        snapshot.revision,
      );
    } on ChameleonResponseTimeoutException catch (error) {
      await _invalidateAndDisconnect(error);
      rethrow;
    } on FormatException catch (error) {
      await _invalidateAndDisconnect(error);
      rethrow;
    }
  }

  Future<void> abortActiveSlotSnapshot(
    MifareClassicActiveSlotSnapshot snapshot,
  ) async {
    await _abortActiveSlotSnapshotRevision(snapshot.revision);
  }

  Future<void> _abortActiveSlotSnapshotRevision(int revision) async {
    final response = await _sendChecked(
      ChameleonCommand.activeSlotSnapshot,
      data: Uint8List.fromList([
        activeSlotSnapshotProtocolVersion,
        _activeSlotSnapshotAbort,
        ...u32ToBytes(revision),
      ]),
    );
    _validateActiveSlotSnapshotEnd(
      response.data,
      _activeSlotSnapshotAbort,
      revision,
    );
  }

  void _validateActiveSlotSnapshotEnd(
    Uint8List data,
    int operation,
    int revision,
  ) {
    if (data.length != 6 ||
        data[0] != activeSlotSnapshotProtocolVersion ||
        data[1] != operation ||
        bytesToU32(data.sublist(2, 6)) != revision) {
      throw const FormatException(
        'Invalid active-slot snapshot completion response',
      );
    }
  }

  Future<void> enterDFUMode() async {
    await sendCmd(ChameleonCommand.enterBootloader, skipReceive: true);
  }

  Future<void> factoryReset() async {
    await sendCmd(ChameleonCommand.factoryReset, skipReceive: true);
  }

  Future<void> saveSettings() async {
    await _sendChecked(ChameleonCommand.saveSettings);
  }

  Future<void> resetSettings() async {
    await _sendChecked(ChameleonCommand.resetSettings);
  }

  Future<void> setAnimationMode(AnimationSetting animation) async {
    await _sendChecked(
      ChameleonCommand.setAnimationMode,
      data: Uint8List.fromList([animation.value]),
    );
  }

  Future<AnimationSetting> getAnimationMode() async {
    final resp = await _sendChecked(ChameleonCommand.getAnimationMode);
    if (resp.data.length != 1) {
      throw const FormatException('Invalid animation-mode response');
    }
    return getAnimationModeType(resp.data[0]);
  }

  Future<String> getGitCommitHash() async {
    var resp = await sendCmd(ChameleonCommand.getGitVersion);
    return const AsciiDecoder().convert(resp!.data);
  }

  Future<int> getActiveSlot() async {
    // get the selected slot on the device, 0-7 (8 slots)
    final resp = await _sendChecked(ChameleonCommand.getActiveSlot);
    if (resp.data.length != 1 || resp.data[0] > 7) {
      throw const FormatException('Invalid active-slot response');
    }
    return resp.data[0];
  }

  Future<List<SlotTypes>> getSlotTagTypes() async {
    List<SlotTypes> tags = [];
    final resp = await _sendChecked(ChameleonCommand.getSlotInfo);
    if (resp.data.length != 32) {
      throw const FormatException('Invalid slot-info response');
    }
    var index = 0;
    for (var slot = 0; slot < 8; slot++) {
      tags.add(
        SlotTypes(
          hf: numberToChameleonTag(
            bytesToU16(resp.data.sublist(index, index + 2)),
          ),
          lf: numberToChameleonTag(
            bytesToU16(resp.data.sublist(index + 2, index + 4)),
          ),
        ),
      );

      index += 4;
    }
    return tags;
  }

  Future<EmulatorSettings> getMf1EmulatorSettings() async {
    final resp = await _sendChecked(ChameleonCommand.mf1GetEmulatorConfig);
    if (resp.data.length != 5 ||
        resp.data.take(4).any((value) => value > 1) ||
        resp.data[4] > 4) {
      throw const FormatException('Invalid MF1 emulator settings response');
    }
    MifareWriteMode mode = MifareWriteMode.normal;

    if (resp.data[4] == 1) {
      mode = MifareWriteMode.denied;
    } else if (resp.data[4] == 2) {
      mode = MifareWriteMode.deceive;
    } else if (resp.data[4] == 3 || resp.data[4] == 4) {
      mode = MifareWriteMode.shadow;
    }

    return EmulatorSettings(
      isDetectionEnabled: resp.data[0] == 1, // is detection enabled
      isGen1a: resp.data[1] == 1, // is gen1a mode enabled
      isGen2: resp.data[2] == 1, // is gen2 mode enabled
      isAntiColl:
          resp.data[3] ==
          1, // use anti collision data from block 0 mode enabled
      writeMode: mode, // write mode
    );
  }

  Future<bool> isMf1Gen1aMode() async {
    final resp = await _sendChecked(ChameleonCommand.mf1GetGen1aMode);
    if (resp.data.length != 1 || resp.data[0] > 1) {
      throw const FormatException('Invalid MF1 Gen1a response');
    }
    return resp.data[0] == 1;
  }

  Future<void> setMf1Gen1aMode(bool gen1aMode) async {
    await _sendChecked(
      ChameleonCommand.mf1SetGen1aMode,
      data: Uint8List.fromList([gen1aMode ? 1 : 0]),
    );
  }

  Future<bool> isMf1Gen2Mode() async {
    final resp = await _sendChecked(ChameleonCommand.mf1GetGen2Mode);
    if (resp.data.length != 1 || resp.data[0] > 1) {
      throw const FormatException('Invalid MF1 Gen2 response');
    }
    return resp.data[0] == 1;
  }

  Future<void> setMf1Gen2Mode(bool gen2Mode) async {
    await _sendChecked(
      ChameleonCommand.mf1SetGen2Mode,
      data: Uint8List.fromList([gen2Mode ? 1 : 0]),
    );
  }

  Future<bool> isMf1UseFirstBlockColl() async {
    final resp = await _sendChecked(ChameleonCommand.mf1GetFirstBlockColl);
    if (resp.data.length != 1 || resp.data[0] > 1) {
      throw const FormatException('Invalid MF1 anticollision-mode response');
    }
    return resp.data[0] == 1;
  }

  Future<void> setMf1UseFirstBlockColl(bool useColl) async {
    await _sendChecked(
      ChameleonCommand.mf1SetFirstBlockColl,
      data: Uint8List.fromList([useColl ? 1 : 0]),
    );
  }

  Future<MifareWriteMode> getMf1WriteMode() async {
    final resp = await _sendChecked(ChameleonCommand.mf1GetWriteMode);
    if (resp.data.length != 1 || resp.data[0] > 4) {
      throw const FormatException('Invalid MF1 write-mode response');
    }
    if (resp.data[0] == 1) {
      return MifareWriteMode.denied;
    } else if (resp.data[0] == 2) {
      return MifareWriteMode.deceive;
    } else if (resp.data[0] == 3 || resp.data[0] == 4) {
      return MifareWriteMode.shadow;
    } else {
      return MifareWriteMode.normal;
    }
  }

  Future<void> setMf1WriteMode(MifareWriteMode mode) async {
    await _sendChecked(
      ChameleonCommand.mf1SetWriteMode,
      data: Uint8List.fromList([mode.value]),
    );
  }

  Future<Mf1PrngType> getMf1PrngType() async {
    final resp = await _sendChecked(ChameleonCommand.mf1GetPrngType);
    if (resp.data.length != 1) {
      throw const FormatException('Invalid MF1 PRNG response');
    }
    return Mf1PrngType.values.firstWhere(
      (type) => type.value == resp.data[0],
      orElse: () =>
          throw FormatException("Unknown MF1 PRNG type ${resp.data[0]}"),
    );
  }

  Future<void> setMf1PrngType(Mf1PrngType type) async {
    await _sendChecked(
      ChameleonCommand.mf1SetPrngType,
      data: Uint8List.fromList([type.value]),
    );
  }

  Future<List<EnabledSlotInfo>> getEnabledSlots() async {
    var resp = await sendCmd(ChameleonCommand.getEnabledSlots);
    List<EnabledSlotInfo> slots = [];
    for (var slot = 0; slot < 8; slot++) {
      slots.add(
        EnabledSlotInfo(
          hf: resp!.data[slot * 2] != 0,
          lf: resp.data[slot * 2 + 1] != 0,
        ),
      );
    }
    return slots;
  }

  Future<BatteryCharge> getBatteryCharge() async {
    var resp = await sendCmd(ChameleonCommand.getBatteryCharge);
    return BatteryCharge(
      voltage: bytesToU16(resp!.data.sublist(0, 2)),
      percent: resp.data[2],
    );
  }

  Future<ButtonConfig> getButtonConfig(ButtonType type) async {
    var resp = await sendCmd(
      ChameleonCommand.getButtonPressConfig,
      data: Uint8List.fromList([type.value]),
    );
    return getButtonConfigType(resp!.data[0]);
  }

  Future<void> setButtonConfig(ButtonType type, ButtonConfig mode) async {
    await _sendChecked(
      ChameleonCommand.setButtonPressConfig,
      data: Uint8List.fromList([type.value, mode.value]),
    );
  }

  Future<ButtonConfig> getLongButtonConfig(ButtonType type) async {
    var resp = await sendCmd(
      ChameleonCommand.getLongButtonPressConfig,
      data: Uint8List.fromList([type.value]),
    );
    return getButtonConfigType(resp!.data[0]);
  }

  Future<void> setLongButtonConfig(ButtonType type, ButtonConfig mode) async {
    await _sendChecked(
      ChameleonCommand.setLongButtonPressConfig,
      data: Uint8List.fromList([type.value, mode.value]),
    );
  }

  Future<int> getSleepTimeout() async {
    var resp = await sendCmd(ChameleonCommand.getSleepTimeout);
    return resp!.data[0];
  }

  Future<void> setSleepTimeout(int seconds) async {
    if (seconds < 0 || seconds > 255) {
      throw RangeError.range(seconds, 0, 255, 'seconds');
    }
    await _sendChecked(
      ChameleonCommand.setSleepTimeout,
      data: Uint8List.fromList([seconds]),
    );
  }

  Future<void> clearBLEBoundedDevices() async {
    await _sendChecked(ChameleonCommand.bleClearBondedDevices);
  }

  Future<String> getBLEConnectionKey() async {
    var resp = await sendCmd(ChameleonCommand.bleGetConnectKey);
    return utf8.decode(resp!.data, allowMalformed: true);
  }

  Future<void> setBLEConnectKey(String key) async {
    await _sendChecked(
      ChameleonCommand.bleSetConnectKey,
      data: Uint8List.fromList(utf8.encode(key)),
    );
  }

  Future<bool> isBLEPairEnabled() async {
    var resp = await sendCmd(ChameleonCommand.bleGetPairEnable);
    return resp!.data[0] == 1;
  }

  Future<void> setBLEPairEnabled(bool status) async {
    await _sendChecked(
      ChameleonCommand.bleSetPairEnable,
      data: Uint8List.fromList([status ? 1 : 0]),
    );
  }

  Future<ChameleonDevice> getDeviceType() async {
    return (await sendCmd(ChameleonCommand.getDeviceType))!.data[0] == 0
        ? ChameleonDevice.ultra
        : ChameleonDevice.lite;
  }

  Future<Uint8List> mf1GetEmulatorBlock(int startBlock, int blockCount) async {
    if (startBlock < 0 ||
        startBlock > 255 ||
        blockCount < 1 ||
        blockCount > 32 ||
        startBlock + blockCount > 256) {
      throw RangeError('Emulator block range is outside MIFARE Classic memory');
    }
    final response = await _sendChecked(
      ChameleonCommand.mf1GetBlockData,
      data: Uint8List.fromList([startBlock, blockCount]),
    );
    final expectedLength = blockCount * 16;
    if (response.data.length != expectedLength) {
      throw FormatException(
        'Invalid MIFARE emulator read length: expected $expectedLength, got ${response.data.length}',
      );
    }
    return response.data;
  }

  Future<Uint8List> mf1GetSnapshotBlocks(
    MifareClassicActiveSlotSnapshot snapshot,
    int startBlock,
    int blockCount,
  ) async {
    final totalBlocks = mfClassicGetBlockCount(
      chameleonTagTypeGetMfClassicType(snapshot.tagType),
    );
    if (startBlock < 0 ||
        blockCount < 1 ||
        blockCount > 32 ||
        startBlock + blockCount > totalBlocks) {
      throw RangeError('Snapshot block range is outside the active card');
    }
    final response = await _sendChecked(
      ChameleonCommand.mf1GetBlockData,
      data: Uint8List.fromList([startBlock, blockCount]),
    );
    final expectedLength = blockCount * 16;
    if (response.data.length != expectedLength) {
      throw FormatException(
        'Invalid frozen MIFARE read length: expected $expectedLength, got ${response.data.length}',
      );
    }
    return response.data;
  }

  Future<CardData> mf1GetSnapshotAntiColl(
    MifareClassicActiveSlotSnapshot snapshot,
  ) async {
    if (!isMifareClassic(snapshot.tagType)) {
      throw const FormatException('Snapshot is not MIFARE Classic');
    }
    return mf1GetAntiCollData();
  }

  Future<CardData> mf1GetAntiCollData() async {
    final resp = await _sendChecked(ChameleonCommand.mf1GetAntiCollData);
    if (resp.data.isEmpty || !const {4, 7, 10}.contains(resp.data[0])) {
      throw const FormatException('Invalid MIFARE anticollision UID length');
    }
    final uidLength = resp.data[0];
    final atsLengthOffset = uidLength + 4;
    if (atsLengthOffset >= resp.data.length) {
      throw const FormatException('Truncated MIFARE anticollision response');
    }
    final atsLength = resp.data[atsLengthOffset];
    if (resp.data.length != uidLength + 5 + atsLength) {
      throw const FormatException(
        'Invalid MIFARE anticollision response length',
      );
    }
    return CardData(
      uid: resp.data.sublist(1, uidLength + 1),
      atqa: Uint8List.fromList(
        resp.data.sublist(uidLength + 1, uidLength + 3).reversed.toList(),
      ),
      sak: resp.data[uidLength + 3],
      ats: resp.data.sublist(uidLength + 5, uidLength + 5 + atsLength),
    );
  }

  Future<Uint8List> getEM410XEmulatorID() async {
    Uint8List data = (await sendCmd(
      ChameleonCommand.getEM410XemulatorID,
    ))!.data;

    if (data.length == 5 || data.length == 13) {
      return data;
    }

    if (data.length >= 2) {
      TagType type = numberToChameleonTag(bytesToU16(data.sublist(0, 2)));
      int uidLength = uidSizeForLfTag(type);

      if (uidLength > 0 && data.length >= uidLength + 2) {
        return data.sublist(2, 2 + uidLength);
      }
    }

    try {
      int slot = await getActiveSlot();
      TagType activeLfType = (await getSlotTagTypes())[slot].lf;
      int uidLength = uidSizeForLfTag(activeLfType);

      if (uidLength > 0) {
        if (data.length >= uidLength + 2) {
          return data.sublist(2, 2 + uidLength);
        }
        if (data.length >= uidLength) {
          return data.sublist(0, uidLength);
        }
      }
    } catch (_) {}

    return data;
  }

  Future<HIDCard> getHIDProxEmulatorID() async {
    return HIDCard.fromBytes(
      (await sendCmd(ChameleonCommand.getHIDProxEmulatorID))!.data,
    );
  }

  Future<VikingCard> getVikingEmulatorID() async {
    return VikingCard.fromBytes(
      (await sendCmd(ChameleonCommand.getVikingEmulatorID))!.data,
    );
  }

  Future<PacCard> getPacEmulatorID() async {
    return PacCard.fromBytes(
      (await sendCmd(ChameleonCommand.getPacEmulatorID))!.data,
    );
  }

  Future<IoProxCard> getIoProxEmulatorID() async {
    return IoProxCard.fromBytes(
      (await sendCmd(ChameleonCommand.getIoProxEmulatorID))!.data,
    );
  }

  Future<IdteckCard> getIdteckEmulatorID() async {
    return IdteckCard.fromBytes(
      (await sendCmd(ChameleonCommand.getIdteckEmulatorID))!.data,
    );
  }

  Future<DeviceSettings> getDeviceSettings() async {
    final resp = (await _sendChecked(ChameleonCommand.getDeviceSettings)).data;
    if (resp.length != 13 && resp.length != 14) {
      throw FormatException(
        'GET_DEVICE_SETTINGS expected 13 legacy or 14 v6 bytes, got ${resp.length}',
      );
    }
    final supportedVersion =
        resp[0] == chameleonDeviceSettingsVersion ||
        (resp[0] == 5 && resp.length == 13);
    if (!supportedVersion) {
      throw FormatException('Unsupported device settings version ${resp[0]}');
    }
    if (resp[6] > 1) {
      throw const FormatException('Invalid pairing-enabled setting');
    }

    AnimationSetting animationMode = getAnimationModeType(resp[1]);
    ButtonConfig aPress = getButtonConfigType(resp[2]),
        bPress = getButtonConfigType(resp[3]),
        aLongPress = getButtonConfigType(resp[4]),
        bLongPress = getButtonConfigType(resp[5]);

    return DeviceSettings(
      animation: animationMode,
      aPress: aPress,
      bPress: bPress,
      aLongPress: aLongPress,
      bLongPress: bLongPress,
      pairingEnabled: resp[6] == 1,
      key: utf8.decode(resp.sublist(7, 13), allowMalformed: true),
      wakeTimeSeconds: resp.length >= 14 ? resp[13] : null,
    );
  }

  Future<List<int>> getDeviceCapabilities() async {
    await initializeCapabilities();
    return cachedDeviceCapabilities?.toList(growable: false) ?? const <int>[];
  }

  Future<void> manipulateValueBlock(
    int srcBlock,
    int srcKeyType,
    Uint8List srcKey,
    MifareClassicValueBlockOperator op,
    int value,
    int dstBlock,
    int dstKeyType,
    Uint8List dstKey,
  ) async {
    await sendCmd(
      ChameleonCommand.mf1ManipulateValueBlock,
      data: Uint8List.fromList([
        srcKeyType,
        srcBlock,
        ...srcKey,
        op.value,
        value >> 24,
        value >> 16 & 0xFF,
        value >> 8 & 0xFF,
        value & 0xFF,
        dstKeyType,
        dstBlock,
        ...dstKey,
      ]),
    );
  }

  Future<Uint8List> send14ARaw(
    Uint8List data, {
    int respTimeoutMs = 100,
    int? bitLen,
    bool activateRfField = true,
    bool waitResponse = true,
    bool appendCrc = true,
    bool autoSelect = true,
    bool keepRfField = false,
    bool checkResponseCrc = true,
  }) async {
    bitLen ??= data.length * 8; // bits = bytes * 8(bit)
    int options = 0;

    if (activateRfField) {
      options += 128;
    }
    if (waitResponse) {
      options += 64;
    }
    if (appendCrc) {
      options += 32;
    }
    if (autoSelect) {
      options += 16;
    }
    if (keepRfField) {
      options += 8;
    }
    if (checkResponseCrc) {
      options += 4;
    }

    return (await sendCmd(
      ChameleonCommand.hf14ARawCommand,
      data: Uint8List.fromList([
        options,
        ...u16ToBytes(respTimeoutMs),
        ...u16ToBytes(bitLen),
        ...data,
      ]),
    ))!.data;
  }

  Future<bool> mf0GetMagicMode() async {
    return (await sendCmd(ChameleonCommand.mf0NtagGetUidMagicMode))!.data[0] ==
        1;
  }

  Future<void> mf0SetMagicMode(bool enabled) async {
    await _sendChecked(
      ChameleonCommand.mf0NtagSetUidMagicMode,
      data: Uint8List.fromList([enabled ? 1 : 0]),
    );
  }

  Future<Uint8List> mf0EmulatorReadPages(int from, int count) async {
    return (await sendCmd(
      ChameleonCommand.mf0NtagReadEmuPageData,
      data: Uint8List.fromList([from, count]),
    ))!.data;
  }

  Future<void> mf0EmulatorWritePages(int from, Uint8List data) async {
    await _sendChecked(
      ChameleonCommand.mf0NtagWriteEmuPageData,
      data: Uint8List.fromList([from, data.length >> 2, ...data]),
    );
  }

  Future<Uint8List> mf0EmulatorGetVersionData() async {
    return (await sendCmd(ChameleonCommand.mf0NtagGetVersionData))!.data;
  }

  Future<void> mf0EmulatorSetVersionData(Uint8List data) async {
    await _sendChecked(
      ChameleonCommand.mf0NtagSetVersionData,
      data: Uint8List.fromList([...data]),
    );
  }

  Future<Uint8List> mf0EmulatorGetSignatureData() async {
    return (await sendCmd(ChameleonCommand.mf0NtagGetSignatureData))!.data;
  }

  Future<void> mf0EmulatorSetSignatureData(Uint8List data) async {
    await _sendChecked(
      ChameleonCommand.mf0NtagSetSignatureData,
      data: Uint8List.fromList([...data]),
    );
  }

  Future<int> mf0ResetAuthCount() async {
    final response = await _sendChecked(ChameleonCommand.mf0NtagResetAuthCount);
    if (response.data.length != 1) {
      throw const FormatException('Invalid auth-count reset response');
    }
    return response.data[0];
  }

  Future<int> mf0EmulatorGetPageCount() async {
    return (await sendCmd(ChameleonCommand.mf0NtagGetPageCount))!.data[0];
  }

  Future<(int, bool)> mf0EmulatorGetCounterData(int index) async {
    Uint8List data = (await sendCmd(
      ChameleonCommand.mf0NtagGetCounterData,
      data: Uint8List.fromList([index]),
    ))!.data;
    return (((data[2] << 16) | (data[1] << 8) | data[0]), data[3] == 0xBD);
  }

  Future<void> mf0EmulatorSetCounterData(
    int index,
    int value,
    bool resetTearing,
  ) async {
    await _sendChecked(
      ChameleonCommand.mf0NtagSetCounterData,
      data: Uint8List.fromList([
        index | ((resetTearing ? 1 : 0) << 7),
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
      ]),
    );
  }

  Future<MifareWriteMode> mf0NtagGetWriteMode() async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetWriteMode);
    if (resp!.data[0] == 1) {
      return MifareWriteMode.denied;
    } else if (resp.data[0] == 2) {
      return MifareWriteMode.deceive;
    } else if (resp.data[0] == 3) {
      return MifareWriteMode.shadow;
    } else {
      return MifareWriteMode.normal;
    }
  }

  Future<void> mf0NtagSetWriteMode(MifareWriteMode mode) async {
    await _sendChecked(
      ChameleonCommand.mf0NtagSetWriteMode,
      data: Uint8List.fromList([mode.value]),
    );
  }

  Future<bool> mf0NtagGetDetectionEnable() async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetDetectionEnable);
    return resp!.data[0] == 1;
  }

  Future<void> mf0NtagSetDetectionEnable(bool enabled) async {
    await _sendChecked(
      ChameleonCommand.mf0NtagSetDetectionEnable,
      data: Uint8List.fromList([enabled ? 1 : 0]),
    );
  }

  Future<int> mf0NtagGetDetectionCount() async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetDetectionCount);
    return bytesToU32(resp!.data);
  }

  Future<List<String>> mf0NtagGetDetectionLog(int index) async {
    var resp = await sendCmd(
      ChameleonCommand.mf0NtagGetDetectionLog,
      data: u32ToBytes(index),
    );

    List<String> resultList = [];
    int pos = 0;
    while (pos < resp!.data.length) {
      var password = resp.data.sublist(pos, pos + 4);
      resultList.add(bytesToHex(password));
      pos += 4;
    }

    return resultList;
  }

  Future<EmulatorSettings> mf0NtagGetEmulatorConfig() async {
    var resp = await sendCmd(ChameleonCommand.mf0NtagGetEmulatorConfig);
    MifareWriteMode mode = MifareWriteMode.normal;

    if (resp!.data[2] == 1) {
      mode = MifareWriteMode.denied;
    } else if (resp.data[2] == 2) {
      mode = MifareWriteMode.deceive;
    } else if (resp.data[2] == 3 || resp.data[2] == 4) {
      mode = MifareWriteMode.shadow;
    }

    return EmulatorSettings(
      isDetectionEnabled: resp.data[0] == 1, // is detection enabled
      isGen1a: false,
      isGen2: resp.data[1] == 1, // is uid magic mode enabled
      isAntiColl: false,
      writeMode: mode, // write mode
    );
  }
}
