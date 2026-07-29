import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'retains MTU payload and awaits ordered normal and DFU chunks',
    () async {
      final writes = <_BleWrite>[];
      var writeInProgress = false;
      final serial = BLESerial(
        log: Logger(level: Level.off),
        connectionPriorityRequester: (_, _) async {},
        mtuRequester: (_, _) async => 27,
        writeRequester: (_, value, withResponse) async {
          expect(writeInProgress, isFalse);
          writeInProgress = true;
          writes.add(_BleWrite(value, withResponse));
          await Future<void>.delayed(Duration.zero);
          writeInProgress = false;
        },
      );
      serial.rxCharacteristic = QualifiedCharacteristic(
        serviceId: nrfUUID,
        characteristicId: uartRX,
        deviceId: 'backend',
      );
      serial.firmwareCharacteristic = QualifiedCharacteristic(
        serviceId: dfuUUID,
        characteristicId: dfuFirmware,
        deviceId: 'backend',
      );
      final normal = Uint8List.fromList(List.generate(55, (index) => index));
      final firmware = Uint8List.fromList(
        List.generate(50, (index) => 100 + index),
      );

      await serial.optimizeConnection('backend', isAndroid: true);
      await serial.write(normal);
      await serial.write(firmware, firmware: true);

      expect(writes.map((write) => write.value.length), [24, 24, 7, 24, 24, 2]);
      expect(writes.map((write) => write.withResponse), [
        true,
        true,
        true,
        false,
        false,
        false,
      ]);
      expect(writes.take(3).expand((write) => write.value), normal);
      expect(writes.skip(3).expand((write) => write.value), firmware);
    },
  );

  test('uses a safe 20-byte payload when MTU negotiation fails', () async {
    final chunkLengths = <int>[];
    final serial = BLESerial(
      log: Logger(level: Level.off),
      connectionPriorityRequester: (_, _) async {},
      mtuRequester: (_, _) => Future<int>.error(StateError('MTU failed')),
      writeRequester: (_, value, _) async => chunkLengths.add(value.length),
    );
    serial.rxCharacteristic = QualifiedCharacteristic(
      serviceId: nrfUUID,
      characteristicId: uartRX,
      deviceId: 'backend',
    );

    await serial.optimizeConnection('backend', isAndroid: true);
    await serial.write(Uint8List(41));

    expect(chunkLengths, [20, 20, 1]);
  });

  test('failed final handshake fully tears down both subscriptions', () async {
    final ble = _FakeReactiveBle();
    final serial = BLESerial(
      log: Logger(level: Level.off),
      reactiveBle: ble,
      writeRequester: (_, _, _) =>
          Future<void>.error(StateError('handshake rejected')),
    );
    _addDevice(serial);

    final result = serial.connectSpecificInternal(_deviceId);
    await _waitFor(
      () =>
          ble.connectionControllers.isNotEmpty &&
          ble.connectionControllers.single.hasListener,
    );
    ble.connectionControllers.single.add(_connectedUpdate);

    expect(await result.timeout(const Duration(seconds: 1)), isFalse);
    expect(ble.connectionCancelCount, 1);
    expect(ble.receiveCancelCount, 1);
    expect(serial.connection, isNull);
    expect(serial.receivedDataSubscription, isNull);
    expect(serial.connected, isFalse);
    expect(serial.pendingConnection, isFalse);
    await ble.close();
  });

  test('connection attempt times out and disposes its subscription', () async {
    final ble = _FakeReactiveBle();
    const timeout = Duration(milliseconds: 25);
    final serial = BLESerial(
      log: Logger(level: Level.off),
      reactiveBle: ble,
      connectionAttemptTimeout: timeout,
    );
    _addDevice(serial);

    final result = serial.connectSpecificInternal(_deviceId);
    expect(await result.timeout(const Duration(seconds: 1)), isFalse);

    expect(ble.requestedConnectionTimeout, timeout);
    expect(ble.connectionCancelCount, 1);
    expect(ble.connectionControllers.single.hasListener, isFalse);
    expect(serial.pendingConnection, isFalse);
    await ble.close();
  });

  test(
    'connection stream completion fails and tears down the attempt',
    () async {
      final ble = _FakeReactiveBle();
      final serial = BLESerial(
        log: Logger(level: Level.off),
        reactiveBle: ble,
      );
      _addDevice(serial);

      final result = serial.connectSpecificInternal(_deviceId);
      await _waitFor(
        () =>
            ble.connectionControllers.isNotEmpty &&
            ble.connectionControllers.single.hasListener,
      );
      await ble.connectionControllers.single.close();

      expect(await result.timeout(const Duration(seconds: 1)), isFalse);
      expect(serial.pendingConnection, isFalse);
      expect(serial.connection, isNull);
      await ble.close();
    },
  );

  test(
    'disconnect still cancels connection when receive cancel throws',
    () async {
      final receiveController = StreamController<List<int>>(
        onCancel: () => Future<void>.error(StateError('receive cancel failed')),
      );
      var connectionCancelCount = 0;
      final connectionController = StreamController<ConnectionStateUpdate>(
        onCancel: () => connectionCancelCount++,
      );
      final serial = BLESerial(log: Logger(level: Level.off));
      serial.receivedDataSubscription = receiveController.stream.listen((_) {});
      serial.connection = connectionController.stream.listen((_) {});
      serial.pendingConnection = true;

      await expectLater(serial.performDisconnect(), throwsA(isA<StateError>()));

      expect(connectionCancelCount, 1);
      expect(connectionController.hasListener, isFalse);
      expect(serial.pendingConnection, isFalse);
      await receiveController.close();
      await connectionController.close();
    },
  );

  test('scan timeout cancels its owned subscription', () async {
    final ble = _FakeReactiveBle();
    final serial = BLESerial(
      log: Logger(level: Level.off),
      reactiveBle: ble,
      scanDuration: const Duration(milliseconds: 10),
    );

    final devices = await serial
        .availableDevices(isIOS: false)
        .timeout(const Duration(seconds: 1));

    expect(devices, isEmpty);
    expect(ble.scanCancelCount, 1);
    expect(ble.scanController.hasListener, isFalse);
    expect(serial.inSearch, isFalse);
    await ble.close();
  });

  test(
    'iOS scan errors complete the future and dispose scan resources',
    () async {
      final ble = _FakeReactiveBle();
      final serial = BLESerial(
        log: Logger(level: Level.off),
        reactiveBle: ble,
        scanDuration: const Duration(seconds: 10),
      );
      final error = StateError('scan denied');

      final search = serial.availableDevices(isIOS: true);
      await _waitFor(() => ble.scanController.hasListener);
      ble.scanController.addError(error);

      await expectLater(search, throwsA(same(error)));
      expect(ble.scanCancelCount, 1);
      expect(ble.scanController.hasListener, isFalse);
      expect(serial.inSearch, isFalse);
      await ble.close();
    },
  );

  test('successful DFU connection records BLE connection type', () async {
    final ble = _FakeReactiveBle();
    final serial = BLESerial(
      log: Logger(level: Level.off),
      reactiveBle: ble,
    );
    _addDevice(serial, dfu: true);

    final result = serial.connectSpecificInternal(_deviceId);
    await _waitFor(
      () =>
          ble.connectionControllers.isNotEmpty &&
          ble.connectionControllers.single.hasListener,
    );
    ble.connectionControllers.single.add(_connectedUpdate);

    expect(await result.timeout(const Duration(seconds: 1)), isTrue);
    expect(serial.connectionType, ConnectionType.ble);
    expect(serial.isDFU, isTrue);
    await serial.performDisconnect();
    await ble.close();
  });
}

const _deviceId = 'ble-device';
const _connectedUpdate = ConnectionStateUpdate(
  deviceId: _deviceId,
  connectionState: DeviceConnectionState.connected,
  failure: null,
);

void _addDevice(BLESerial serial, {bool dfu = false}) {
  serial.chameleonMap[_deviceId] = Chameleon(
    port: _deviceId,
    device: ChameleonDevice.ultra,
    type: ConnectionType.ble,
    dfu: dfu,
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for BLE lifecycle event');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _BleWrite {
  const _BleWrite(this.value, this.withResponse);

  final Uint8List value;
  final bool withResponse;
}

class _FakeReactiveBle implements FlutterReactiveBle {
  _FakeReactiveBle() {
    scanController = StreamController<DiscoveredDevice>.broadcast(
      onCancel: () => scanCancelCount++,
    );
  }

  late final StreamController<DiscoveredDevice> scanController;
  final List<StreamController<ConnectionStateUpdate>> connectionControllers =
      [];
  final List<StreamController<List<int>>> receiveControllers = [];
  int scanCancelCount = 0;
  int connectionCancelCount = 0;
  int receiveCancelCount = 0;
  Duration? requestedConnectionTimeout;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) {
    return scanController.stream;
  }

  @override
  Stream<ConnectionStateUpdate> connectToAdvertisingDevice({
    required String id,
    required List<Uuid> withServices,
    required Duration prescanDuration,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    requestedConnectionTimeout = connectionTimeout;
    final controller = StreamController<ConnectionStateUpdate>.broadcast(
      onCancel: () => connectionCancelCount++,
    );
    connectionControllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  ) {
    final controller = StreamController<List<int>>.broadcast(
      onCancel: () => receiveCancelCount++,
    );
    receiveControllers.add(controller);
    return controller.stream;
  }

  Future<void> close() async {
    if (!scanController.isClosed) await scanController.close();
    for (final controller in receiveControllers) {
      if (!controller.isClosed) await controller.close();
    }
    for (final controller in connectionControllers) {
      if (!controller.isClosed) await controller.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
