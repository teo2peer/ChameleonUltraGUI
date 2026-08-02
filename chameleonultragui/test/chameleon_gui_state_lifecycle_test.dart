import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
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

  test(
    'disconnect rejects slot work queued for the previous connection',
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
    },
  );

  test(
    'BLE loss disarms LEDs but keeps the undercover launcher active',
    () async {
      final fixture = await _fixture();
      fixture.state.undercoverMode = true;
      fixture.state.undercoverDeviceArmed = true;
      fixture.serial.connected = false;

      fixture.state.onConnectorStateChanged();

      expect(fixture.state.undercoverMode, isTrue);
      expect(fixture.state.undercoverDeviceArmed, isFalse);
    },
  );

  test(
    'BLE enters local-only undercover without a firmware capability',
    () async {
      final fixture = await _fixture();
      fixture.serial.connected = true;
      fixture.serial.connectionType = ConnectionType.ble;
      fixture.state.log = Logger(level: Level.off);
      fixture.state.communicator = ChameleonCommunicator(
        fixture.state.log!,
        port: fixture.serial,
      );

      expect(fixture.state.canEnterUndercover, isTrue);
      await fixture.state.enterUndercover();

      expect(fixture.state.undercoverMode, isTrue);
      expect(fixture.state.undercoverDeviceArmed, isFalse);
      expect(fixture.serial.disconnectCount, 0);
    },
  );

  test('uncertain Undercover activation disconnects to restore LEDs', () async {
    final fixture = await _fixture();
    fixture.serial.connected = true;
    fixture.serial.connectionType = ConnectionType.ble;
    fixture.state.log = Logger(level: Level.off);
    fixture.state.communicator = _UndercoverTestCommunicator(
      fixture.serial,
      failActivation: true,
    );

    await expectLater(fixture.state.enterUndercover(), throwsStateError);

    expect(fixture.serial.disconnectCount, 1);
    expect(fixture.state.undercoverMode, isFalse);
    expect(fixture.state.undercoverDeviceArmed, isFalse);
  });

  test('uncertain activation reports an unconfirmed BLE disconnect', () async {
    final fixture = await _fixture();
    fixture.serial.connected = true;
    fixture.serial.connectionType = ConnectionType.ble;
    fixture.serial.failDisconnect = true;
    fixture.state.log = Logger(level: Level.off);
    fixture.state.communicator = _UndercoverTestCommunicator(
      fixture.serial,
      failActivation: true,
    );

    await expectLater(
      fixture.state.enterUndercover(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('disconnect could not be confirmed'),
        ),
      ),
    );

    expect(fixture.serial.connected, isTrue);
    expect(fixture.serial.disconnectCount, 2);
    expect(fixture.state.undercoverMode, isTrue);
    expect(fixture.state.undercoverDeviceArmed, isTrue);
  });

  test(
    'advertised Undercover capability arms and restores the device',
    () async {
      final fixture = await _fixture();
      fixture.serial.connected = true;
      fixture.serial.connectionType = ConnectionType.ble;
      fixture.state.log = Logger(level: Level.off);
      final communicator = _UndercoverTestCommunicator(fixture.serial);
      fixture.state.communicator = communicator;

      await fixture.state.enterUndercover();
      expect(fixture.state.undercoverMode, isTrue);
      expect(fixture.state.undercoverDeviceArmed, isTrue);
      expect(communicator.modes, [true]);

      await fixture.state.exitUndercover();
      expect(communicator.modes, [true, false]);
      expect(fixture.serial.disconnectCount, 0);
    },
  );

  test('failed LED restore disconnects before leaving undercover', () async {
    final fixture = await _fixture();
    fixture.serial.connected = true;
    fixture.serial.connectionType = ConnectionType.ble;
    fixture.state.log = Logger(level: Level.off);
    fixture.state.communicator = ChameleonCommunicator(
      fixture.state.log!,
      port: fixture.serial,
    );
    fixture.state.undercoverMode = true;
    fixture.state.undercoverDeviceArmed = true;

    await fixture.state.exitUndercover();

    expect(fixture.serial.disconnectCount, 1);
    expect(fixture.state.undercoverMode, isFalse);
    expect(fixture.state.undercoverDeviceArmed, isFalse);
  });

  test('failed LED restore and disconnect keep Undercover active', () async {
    final fixture = await _fixture();
    fixture.serial.connected = true;
    fixture.serial.connectionType = ConnectionType.ble;
    fixture.serial.failDisconnect = true;
    fixture.state.log = Logger(level: Level.off);
    fixture.state.communicator = _UndercoverTestCommunicator(
      fixture.serial,
      failDeactivation: true,
    );
    fixture.state.undercoverMode = true;
    fixture.state.undercoverDeviceArmed = true;

    await expectLater(fixture.state.exitUndercover(), throwsStateError);

    expect(fixture.serial.disconnectCount, 2);
    expect(fixture.state.undercoverMode, isTrue);
    expect(fixture.state.undercoverDeviceArmed, isTrue);
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
  bool failDisconnect = false;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) {
    if (!started.isCompleted) started.complete();
    return discovery.future;
  }

  @override
  Future<bool> performDisconnect() async {
    disconnectCount++;
    if (failDisconnect) throw StateError('BLE disconnect failed');
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

class _UndercoverTestCommunicator extends ChameleonCommunicator {
  _UndercoverTestCommunicator(
    AbstractSerial serial, {
    this.failActivation = false,
    this.failDeactivation = false,
  }) : super(Logger(level: Level.off), port: serial);

  final bool failActivation;
  final bool failDeactivation;
  final List<bool> modes = [];

  @override
  bool? supportsCommandSync(ChameleonCommand command) =>
      command == ChameleonCommand.setRuntimeUndercoverMode
      ? true
      : super.supportsCommandSync(command);

  @override
  Future<void> setRuntimeUndercoverMode(bool enabled) async {
    modes.add(enabled);
    if (enabled && failActivation) {
      throw StateError('Undercover activation response was lost');
    }
    if (!enabled && failDeactivation) {
      throw StateError('Undercover LED restore failed');
    }
  }
}
