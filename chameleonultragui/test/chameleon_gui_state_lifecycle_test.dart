import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dispose invalidates a blocked successful device scan', () async {
    final fixture = await _fixture();
    var notifications = 0;
    fixture.state.addListener(() => notifications++);

    final scan = fixture.state.refreshDeviceScan();
    await fixture.serial.started.future;
    fixture.state.dispose();

    expect(fixture.serial.connectionStateCallback, isNull);
    await _waitFor(() => fixture.serial.disconnectCount == 1);
    fixture.serial.discovery.complete(const [
      Chameleon(
        port: 'late-device',
        device: ChameleonDevice.ultra,
        type: ConnectionType.usb,
        dfu: false,
      ),
    ]);
    await scan;

    expect(notifications, 0);
    expect(fixture.state.availableDevices, isEmpty);
    expect(fixture.state.hasCompletedDeviceScan, isFalse);
  });

  test('dispose invalidates a blocked device scan error', () async {
    final fixture = await _fixture();
    var notifications = 0;
    fixture.state.addListener(() => notifications++);

    final scan = fixture.state.refreshDeviceScan();
    await fixture.serial.started.future;
    fixture.state.dispose();
    fixture.serial.discovery.completeError(StateError('late scan failure'));
    await scan;

    expect(notifications, 0);
    expect(fixture.serial.disconnectCount, 1);
    expect(fixture.state.scanError, isNull);
    expect(fixture.state.hasCompletedDeviceScan, isFalse);
  });

  test('disconnect rejects slot work queued for the previous connection',
      () async {
    final fixture = await _fixture();
    fixture.serial.connected = true;
    fixture.state.log = Logger(level: Level.off);
    fixture.state.communicator = ChameleonCommunicator(
      fixture.state.log!,
      port: fixture.serial,
    );
    final started = Completer<void>();
    final blocker = Completer<void>();
    final first = fixture.state.runSlotOperation(() {
      started.complete();
      return blocker.future;
    });
    await started.future;
    var secondRan = false;
    final second = fixture.state.runSlotOperation(() async {
      secondRan = true;
    });
    final secondExpectation = expectLater(second, throwsStateError);

    await fixture.state.disconnect();
    blocker.complete();
    await first;

    await secondExpectation;
    expect(secondRan, isFalse);
  });
}

Future<_LifecycleFixture> _fixture() async {
  SharedPreferences.setMockInitialValues({
    'auto_scan_enabled': true,
    'auto_connect_first_found': false,
  });
  final preferences = SharedPreferencesProvider();
  await preferences.load();
  final serial = _BlockingSerial();
  final state = ChameleonGUIState(preferences)..connector = serial;
  serial.connectionStateCallback = state.onConnectorStateChanged;
  return _LifecycleFixture(state, serial);
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for lifecycle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _LifecycleFixture {
  const _LifecycleFixture(this.state, this.serial);

  final ChameleonGUIState state;
  final _BlockingSerial serial;
}

class _BlockingSerial extends AbstractSerial {
  _BlockingSerial() : super(log: Logger(level: Level.off));

  final discovery = Completer<List<Chameleon>>();
  final started = Completer<void>();
  int disconnectCount = 0;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) {
    if (!started.isCompleted) started.complete();
    return discovery.future;
  }

  @override
  Future<bool> performDisconnect() async {
    disconnectCount++;
    resetConnectionState();
    notifyConnectionStateChanged();
    return true;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => false;

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => false;
}
