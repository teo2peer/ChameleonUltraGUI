import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/dfu.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  test('DFU response timeout disconnects and rejects later commands', () async {
    final serial = _DfuSerial();
    final communicator = DFUCommunicator(
      Logger(level: Level.off),
      port: serial,
      viaBLE: true,
      responseTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      communicator.sendCmd(DFUCommand.ping, Uint8List(0)),
      throwsA(isA<TimeoutException>()),
    );
    expect(serial.disconnected, isTrue);

    await serial.emit([0x60, DFUCommand.ping.value, 0x01]);
    await expectLater(
      communicator.sendCmd(DFUCommand.getHW, Uint8List(0)),
      throwsA(isA<DFUTransferError>()),
    );
    expect(serial.writeCount, 1);
  });

  test('DFU MTU fallback does not swallow a transport timeout', () async {
    final serial = _DfuSerial();
    final communicator = DFUCommunicator(
      Logger(level: Level.off),
      port: serial,
      viaBLE: true,
      responseTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(communicator.getMTU(), throwsA(isA<TimeoutException>()));
    expect(serial.disconnected, isTrue);
  });

  test('DFU incrementally decodes a fragmented SLIP response', () async {
    final serial = _DfuSerial();
    final communicator = DFUCommunicator(
      Logger(level: Level.off),
      port: serial,
    );

    final resultFuture = communicator.sendCmd(DFUCommand.ping, Uint8List(0));
    await Future<void>.delayed(Duration.zero);
    final encoded = Slip.encode(Uint8List.fromList(
        [DFUCommand.response.value, DFUCommand.ping.value, 0x01, 0x42]));
    await serial.emit(encoded.sublist(0, 2));
    await serial.emit(encoded.sublist(2));

    expect(await resultFuture, [0x42]);
  });

  test('DFU rejects concurrent commands instead of completing the first',
      () async {
    final serial = _DfuSerial();
    final communicator = DFUCommunicator(
      Logger(level: Level.off),
      port: serial,
      viaBLE: true,
    );

    final first = communicator.sendCmd(DFUCommand.ping, Uint8List(0));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      communicator.sendCmd(DFUCommand.getHW, Uint8List(0)),
      throwsA(isA<DFUTransferError>()),
    );
    await serial.emit([0x60, DFUCommand.ping.value, 0x01]);
    expect(await first, isEmpty);
  });
}

class _DfuSerial extends AbstractSerial {
  int writeCount = 0;
  bool disconnected = false;

  _DfuSerial() : super(log: Logger(level: Level.off));

  @override
  Future<void> open() async {
    isOpen = true;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    writeCount++;
    return true;
  }

  Future<void> emit(List<int> data) async {
    await messageCallback(Uint8List.fromList(data));
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
