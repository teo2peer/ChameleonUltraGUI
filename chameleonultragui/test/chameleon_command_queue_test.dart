import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  test('bootstraps capabilities once and serializes commands', () async {
    final serial = _FakeSerial();
    final communicator = _communicator(serial);

    await Future.wait([
      communicator.sendCmd(ChameleonCommand.getAppVersion),
      communicator.sendCmd(ChameleonCommand.getDeviceMode),
    ]);

    expect(serial.maxConcurrentWrites, 1);
    expect(serial.commands, [
      ChameleonCommand.getDeviceCapabilities.value,
      ChameleonCommand.getAppVersion.value,
      ChameleonCommand.getDeviceMode.value,
    ]);
  });

  test('rejects commands absent from the advertised capabilities', () async {
    final serial = _FakeSerial(capabilities: {
      ChameleonCommand.getDeviceCapabilities.value,
      ChameleonCommand.getAppVersion.value,
    });
    final communicator = _communicator(serial);

    await expectLater(communicator.sendCmd(ChameleonCommand.getDeviceMode),
        throwsA(isA<ChameleonUnsupportedCommandException>()));
    expect(serial.commands, [ChameleonCommand.getDeviceCapabilities.value]);
  });

  test('caches capability reads', () async {
    final serial = _FakeSerial();
    final communicator = _communicator(serial);

    expect(await communicator.supportsCommand(ChameleonCommand.getAppVersion),
        isTrue);
    expect(await communicator.supportsCommand(ChameleonCommand.getDeviceMode),
        isTrue);
    expect(await communicator.getDeviceCapabilities(), isNotEmpty);

    expect(
        serial.commands
            .where((id) => id == ChameleonCommand.getDeviceCapabilities.value),
        hasLength(1));
  });

  for (final legacyStatus in [0x67, 0x69]) {
    test(
        'allows optimistic commands for legacy status 0x${legacyStatus.toRadixString(16)}',
        () async {
      final serial = _FakeSerial(capabilityStatus: legacyStatus);
      final communicator = _communicator(serial);

      await communicator.sendCmd(ChameleonCommand.getAppVersion);

      expect(await communicator.supportsCommand(ChameleonCommand.getDeviceMode),
          isNull);
      expect(serial.commands, [
        ChameleonCommand.getDeviceCapabilities.value,
        ChameleonCommand.getAppVersion.value,
      ]);
    });
  }

  test('rejects malformed capability payloads', () async {
    final serial = _FakeSerial(capabilityPayload: Uint8List.fromList([0x01]));
    final communicator = _communicator(serial);

    await expectLater(
        communicator.initializeCapabilities(), throwsFormatException);
    expect(serial.commands, [ChameleonCommand.getDeviceCapabilities.value]);
  });

  test('write timeout invalidates the communicator and disconnects', () async {
    final command = ChameleonCommand.getAppVersion;
    final serial = _FakeSerial(hangingCommands: {command.value});
    final communicator =
        _communicator(serial, writeTimeout: const Duration(milliseconds: 10));

    await communicator.initializeCapabilities();
    await expectLater(
        communicator.sendCmd(command), throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(Duration.zero);
    expect(serial.disconnected, isTrue);
    await expectLater(communicator.sendCmd(ChameleonCommand.getDeviceMode),
        throwsA(isA<ChameleonCommunicatorClosedException>()));
    expect(serial.commands, [
      ChameleonCommand.getDeviceCapabilities.value,
      command.value,
    ]);
  });

  test('quarantines a timed-out command until its late response is discarded',
      () async {
    final command = ChameleonCommand.getAppVersion;
    var respond = false;
    final serial = _FakeSerial(onCommand: (serial, id) async {
      if (id == ChameleonCommand.getDeviceCapabilities.value) {
        await serial.emitCapabilities();
      } else if (respond) {
        await serial.emit(id, data: [0x22]);
      }
    });
    final communicator = _communicator(serial);
    await communicator.initializeCapabilities();

    await expectLater(
        communicator.sendCmd(command,
            timeout: const Duration(milliseconds: 10)),
        throwsA(isA<ChameleonResponseTimeoutException>()));
    await expectLater(communicator.sendCmd(command),
        throwsA(isA<ChameleonCommandResponseUncertainException>()));
    expect(serial.commands.where((id) => id == command.value), hasLength(1));

    await serial.emit(command.value, data: [0x11]);
    respond = true;
    final response = await communicator.sendCmd(command);
    expect(response!.data, [0x22]);
  });

  test('discards a late response coalesced with another command response',
      () async {
    final timedOut = ChameleonCommand.getAppVersion;
    final next = ChameleonCommand.getDeviceMode;
    final serial = _FakeSerial(onCommand: (serial, id) async {
      if (id == ChameleonCommand.getDeviceCapabilities.value) {
        await serial.emitCapabilities();
      } else if (id == next.value) {
        await serial.emitFrames([
          serial.responseFrame(timedOut.value, data: [0x11]),
          serial.responseFrame(next.value, data: [0x33]),
        ]);
      }
    });
    final communicator = _communicator(serial);
    await communicator.initializeCapabilities();

    await expectLater(
        communicator.sendCmd(timedOut,
            timeout: const Duration(milliseconds: 10)),
        throwsA(isA<ChameleonResponseTimeoutException>()));
    final response = await communicator.sendCmd(next);
    expect(response!.data, [0x33]);
  });

  test('handles a synchronous response emitted during write', () async {
    final serial = _FakeSerial(synchronousResponses: true);
    final communicator = _communicator(serial);

    final response = await communicator.sendCmd(ChameleonCommand.getAppVersion);

    expect(response, isNotNull);
  });

  test('skipReceive does not leak serializer state', () async {
    final serial = _FakeSerial(respondToCommands: false);
    final communicator = _communicator(serial);
    await communicator.initializeCapabilities();

    await communicator.sendCmd(ChameleonCommand.enterBootloader,
        skipReceive: true);

    expect(communicator.commandQueue, isEmpty);
  });
}

ChameleonCommunicator _communicator(_FakeSerial serial,
        {Duration writeTimeout = const Duration(seconds: 1)}) =>
    ChameleonCommunicator(Logger(level: Level.off),
        port: serial, writeTimeout: writeTimeout);

typedef _CommandHandler = Future<void> Function(_FakeSerial serial, int id);

class _FakeSerial extends AbstractSerial {
  final int capabilityStatus;
  final Uint8List? capabilityPayload;
  final Set<int> capabilities;
  final Set<int> hangingCommands;
  final bool respondToCommands;
  final bool synchronousResponses;
  final _CommandHandler? onCommand;
  final List<int> commands = [];
  int _activeWrites = 0;
  int maxConcurrentWrites = 0;
  bool disconnected = false;

  _FakeSerial({
    this.capabilityStatus = chameleonStatusSuccess,
    this.capabilityPayload,
    Set<int>? capabilities,
    this.hangingCommands = const <int>{},
    this.respondToCommands = true,
    this.synchronousResponses = false,
    this.onCommand,
  })  : capabilities = capabilities ??
            ChameleonCommand.values.map((command) => command.value).toSet(),
        super(log: Logger(level: Level.off));

  @override
  Future<void> open() async {
    isOpen = true;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final commandId = (command[2] << 8) | command[3];
    commands.add(commandId);
    _activeWrites++;
    if (_activeWrites > maxConcurrentWrites) {
      maxConcurrentWrites = _activeWrites;
    }
    if (hangingCommands.contains(commandId)) {
      return Completer<bool>().future;
    }
    if (!synchronousResponses) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (onCommand != null) {
      await onCommand!(this, commandId);
    } else if (commandId == ChameleonCommand.getDeviceCapabilities.value) {
      await emitCapabilities();
    } else if (respondToCommands) {
      await emit(commandId);
    }
    _activeWrites--;
    return true;
  }

  Future<void> emitCapabilities() => emit(
        ChameleonCommand.getDeviceCapabilities.value,
        status: capabilityStatus,
        data: capabilityPayload ?? _capabilityBytes(capabilities),
      );

  Future<void> emit(int commandId,
      {int status = chameleonStatusSuccess, List<int> data = const []}) async {
    await messageCallback(responseFrame(commandId, status: status, data: data));
  }

  Future<void> emitFrames(List<List<int>> frames) async {
    await messageCallback(frames.expand((frame) => frame).toList());
  }

  List<int> responseFrame(int commandId,
      {int status = chameleonStatusSuccess, List<int> data = const []}) {
    final frame = <int>[
      0x11,
      _lrc([0x11]),
      commandId >> 8,
      commandId & 0xFF,
      status >> 8,
      status & 0xFF,
      data.length >> 8,
      data.length & 0xFF,
    ];
    frame.add(_lrc(frame.sublist(2, 8)));
    frame.addAll(data);
    frame.add(_lrc(frame));
    return frame;
  }

  Uint8List _capabilityBytes(Set<int> values) => Uint8List.fromList([
        for (final value in values) ...[value >> 8, value & 0xFF]
      ]);

  int _lrc(List<int> data) {
    var sum = 0;
    for (final byte in data) {
      sum = (sum + byte) & 0xFF;
    }
    return (0x100 - sum) & 0xFF;
  }

  @override
  Future<bool> performDisconnect() async {
    disconnected = true;
    isOpen = false;
    return true;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;

  @override
  bool isManualConnectionSupported() => false;
}
