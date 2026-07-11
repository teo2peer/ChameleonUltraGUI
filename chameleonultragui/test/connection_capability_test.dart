import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  test('capability bootstrap failure tears down the new connection', () async {
    final serial = _TimeoutSerial()
      ..connected = true
      ..pendingConnection = true;
    final state = ChameleonGUIState(SharedPreferencesProvider())
      ..log = Logger(level: Level.off)
      ..connector = serial;

    await expectLater(
        state.attachConnectedCommunicator(), throwsA(isA<TimeoutException>()));

    expect(state.communicator, isNull);
    expect(serial.connected, isFalse);
    expect(serial.pendingConnection, isFalse);
    expect(serial.disconnectCount, greaterThanOrEqualTo(1));
  });
}

class _TimeoutSerial extends AbstractSerial {
  int disconnectCount = 0;

  _TimeoutSerial() : super(log: Logger(level: Level.off));

  @override
  Future<void> open() async {
    isOpen = true;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) {
    throw TimeoutException('test write timeout');
  }

  @override
  Future<bool> performDisconnect() async {
    disconnectCount++;
    connected = false;
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
