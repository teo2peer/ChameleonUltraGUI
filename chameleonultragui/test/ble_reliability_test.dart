import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon_ble.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/helpers/ble/ble_address.dart';
import 'package:chameleonultragui/helpers/ble/ble_presentation.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart'
    show ConnectionPriority;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BLE address conversion', () {
    test('displays MSB first and reverses only for the device API', () {
      final littleEndian = bleAddressToLittleEndian('C0:11:22:33:44:55');

      expect(littleEndian, [0x55, 0x44, 0x33, 0x22, 0x11, 0xC0]);
      expect(bleAddressFromLittleEndian(littleEndian), 'C0:11:22:33:44:55');
    });

    test('accepts hyphens but rejects incomplete octets', () {
      expect(bleAddressToLittleEndian('AA-BB-CC-DD-EE-FF'),
          [0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA]);
      expect(() => bleAddressToLittleEndian('A:BB:CC:DD:EE:FF'),
          throwsFormatException);
      expect(() => bleAddressToLittleEndian('AA:BB:CC:DD:EE:GG'),
          throwsFormatException);
    });
  });

  group('BLE numeric parser', () {
    test('parses explicit hex and decimal without radix autodetection', () {
      expect(bleParseHexOrDecimal('0x12'), 18);
      expect(bleParseHexOrDecimal('0Xff'), 255);
      expect(bleParseHexOrDecimal('12'), 12);
    });

    test('rejects empty values and prefixes without digits', () {
      expect(() => bleParseHexOrDecimal('  '), throwsFormatException);
      expect(() => bleParseHexOrDecimal('0x'), throwsFormatException);
    });
  });

  group('BLE command status validation', () {
    test('throws a useful command error before decoding an error payload',
        () async {
      final communicator = _FakeCommunicator(ChameleonMessage(
          command: ChameleonCommand.bleScanGetCount.value,
          status: 0x60,
          data: Uint8List(0)));

      await expectLater(
          communicator.blePassiveScanCount(),
          throwsA(isA<ChameleonCommandException>()
              .having((error) => error.status, 'status', 0x60)
              .having((error) => error.toString(), 'message',
                  contains('invalid parameter'))));
    });

    test('rejects a malformed successful payload', () async {
      final communicator = _FakeCommunicator(ChameleonMessage(
          command: ChameleonCommand.bleScanGetCount.value,
          status: chameleonStatusSuccess,
          data: Uint8List(0)));

      await expectLater(
          communicator.blePassiveScanCount(), throwsFormatException);
    });

    test('parses extended central state and ignores future appended fields',
        () async {
      final data = Uint8List.fromList([
        2,
        2,
        4,
        0,
        0x12,
        0x34,
        1,
        0,
        2,
        0,
        3,
        4,
        1,
        0,
        0,
        0,
        9,
        2,
        3,
        0,
        5,
        0xAA,
      ]);
      final communicator = _FakeCommunicator(ChameleonMessage(
          command: ChameleonCommand.bleCentralState.value,
          status: chameleonStatusSuccess,
          data: data));

      final state = await communicator.bleCentralState();
      expect(state.floodState, 1);
      expect(state.floodSent, 9);
      expect(state.readState, 2);
      expect(state.writeState, 3);
      expect(state.notificationCount, 5);
      expect(state.hasOperationState, isTrue);
    });

    test('rejects invalid public API arguments instead of truncating them',
        () async {
      final communicator = _FakeCommunicator(ChameleonMessage(
          command: 0, status: chameleonStatusSuccess, data: Uint8List(0)));

      await expectLater(communicator.bleConnect(Uint8List(6), addrType: 4),
          throwsArgumentError);
      await expectLater(communicator.blePassiveScanResults(startIndex: 256),
          throwsArgumentError);
      await expectLater(communicator.bleGattRead(0), throwsArgumentError);
      await expectLater(
          communicator.bleGattWrite(1, Uint8List(0)), throwsArgumentError);
      await expectLater(communicator.bleSubscribe(1, 3), throwsArgumentError);
      await expectLater(
          communicator.bleFuzzStart(1, intervalMs: 9), throwsArgumentError);
    });

    test('does not guess a CCCD when discovery reports not found', () async {
      final communicator = _QueuedCommunicator([
        ChameleonMessage(
            command: ChameleonCommand.bleFindCccd.value,
            status: chameleonStatusSuccess,
            data: Uint8List(0)),
        ChameleonMessage(
            command: ChameleonCommand.bleGetCccd.value,
            status: chameleonStatusSuccess,
            data: Uint8List.fromList([3, 0, 0])),
      ]);

      await expectLater(communicator.bleFindCccd(0x002a), throwsStateError);
      expect(communicator.commands,
          [ChameleonCommand.bleFindCccd, ChameleonCommand.bleGetCccd]);
    });
  });

  group('firmware command contracts', () {
    test('LF setters validate length and propagate firmware rejection',
        () async {
      final communicator = _FakeCommunicator(ChameleonMessage(
          command: ChameleonCommand.setPacEmulatorID.value,
          status: 0x72,
          data: Uint8List(0)));

      await expectLater(
          communicator.setPacEmulatorID(Uint8List(7)), throwsArgumentError);
      await expectLater(
          communicator.setPacEmulatorID(Uint8List(8)),
          throwsA(isA<ChameleonCommandException>()
              .having((error) => error.status, 'status', 0x72)));
    });

    test('decodes the four ISO-DEP debug counters exactly', () async {
      expect(ChameleonCommand.hf14a4DebugCounters.value, 6010);
      final communicator = _FakeCommunicator(ChameleonMessage(
          command: ChameleonCommand.hf14a4DebugCounters.value,
          status: chameleonStatusSuccess,
          data: Uint8List.fromList([7, 8, 0xA2, 3])));

      final counters = await communicator.hf14a4DebugCounters();
      expect(counters.receivedIBlocks, 7);
      expect(counters.transmittedIBlocks, 8);
      expect(counters.lastReceivedPcb, 0xA2);
      expect(counters.lastStaticResponseMatch, 3);
    });
  });

  test('BLE disconnect cancels the active UART receive subscription', () async {
    final controller = StreamController<List<int>>();
    final serial = BLESerial(log: Logger(level: Level.off));
    serial.receivedDataSubscription = controller.stream.listen((_) {});
    expect(controller.hasListener, isTrue);

    await serial.performDisconnect();

    expect(controller.hasListener, isFalse);
    await controller.close();
  });

  test('BLE relay transport requests low latency and MTU 247', () async {
    String? priorityDeviceId;
    ConnectionPriority? priority;
    String? mtuDeviceId;
    int? requestedMtu;
    final serial = BLESerial(
      log: Logger(level: Level.off),
      connectionPriorityRequester: (deviceId, requestedPriority) async {
        priorityDeviceId = deviceId;
        priority = requestedPriority;
      },
      mtuRequester: (deviceId, mtu) async {
        mtuDeviceId = deviceId;
        requestedMtu = mtu;
        return mtu;
      },
    );

    await serial.optimizeConnection('backend', isAndroid: true);

    expect(priorityDeviceId, 'backend');
    expect(priority, ConnectionPriority.highPerformance);
    expect(mtuDeviceId, 'backend');
    expect(requestedMtu, 247);
  });
}

class _FakeCommunicator extends ChameleonCommunicator {
  final ChameleonMessage response;

  _FakeCommunicator(this.response) : super(Logger());

  @override
  Future<ChameleonMessage?> sendCmd(ChameleonCommand cmd,
      {Uint8List? data,
      Duration timeout = const Duration(seconds: 5),
      bool skipReceive = false,
      bool firstRun = false}) async {
    return response;
  }
}

class _QueuedCommunicator extends ChameleonCommunicator {
  final List<ChameleonMessage> responses;
  final List<ChameleonCommand> commands = [];

  _QueuedCommunicator(this.responses) : super(Logger());

  @override
  Future<ChameleonMessage?> sendCmd(ChameleonCommand cmd,
      {Uint8List? data,
      Duration timeout = const Duration(seconds: 5),
      bool skipReceive = false,
      bool firstRun = false}) async {
    commands.add(cmd);
    return responses.removeAt(0);
  }
}
