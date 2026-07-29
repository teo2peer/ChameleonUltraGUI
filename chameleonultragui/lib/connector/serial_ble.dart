import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// Regular
Uuid nrfUUID = Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid uartRX = Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid uartTX = Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

// DFU
Uuid dfuUUID = Uuid.parse("FE59");
Uuid dfuControl = Uuid.parse("8EC90001-F315-4F60-9FB8-838830DAEA50");
Uuid dfuFirmware = Uuid.parse("8EC90002-F315-4F60-9FB8-838830DAEA50");

typedef BleWriteRequester = Future<void> Function(
  QualifiedCharacteristic characteristic,
  Uint8List value,
  bool withResponse,
);

class BLESerial extends AbstractSerial {
  FlutterReactiveBle? _flutterReactiveBle;
  final Future<void> Function(String, ConnectionPriority)?
      connectionPriorityRequester;
  final Future<int> Function(String, int)? mtuRequester;
  final BleWriteRequester? writeRequester;
  final Duration connectionAttemptTimeout;
  final Duration scanDuration;
  QualifiedCharacteristic? txCharacteristic;
  QualifiedCharacteristic? rxCharacteristic;
  QualifiedCharacteristic? firmwareCharacteristic;
  Characteristic? _resolvedRxCharacteristic;
  Characteristic? _resolvedFirmwareCharacteristic;
  Stream<List<int>>? receivedDataStream;
  StreamSubscription<List<int>>? receivedDataSubscription;
  StreamSubscription<ConnectionStateUpdate>? connection;
  int _connectRetryGeneration = 0;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  Timer? _scanTimer;
  Completer<bool>? _connectionCompleter;
  int _connectionGeneration = 0;
  int _effectiveAttPayload = 20;
  Map<String, Chameleon> chameleonMap = {};
  bool inSearch = false;

  BLESerial({
    required super.log,
    FlutterReactiveBle? reactiveBle,
    this.connectionPriorityRequester,
    this.mtuRequester,
    this.writeRequester,
    this.connectionAttemptTimeout = const Duration(seconds: 10),
    this.scanDuration = const Duration(seconds: 2),
  }) : _flutterReactiveBle = reactiveBle;

  FlutterReactiveBle get flutterReactiveBle =>
      _flutterReactiveBle ??= FlutterReactiveBle();

  Future<void> optimizeConnection(
    String deviceId, {
    bool? isAndroid,
  }) async {
    _effectiveAttPayload = 20;
    if (!(isAndroid ?? Platform.isAndroid)) return;
    try {
      final requester = connectionPriorityRequester;
      if (requester == null) {
        await flutterReactiveBle.requestConnectionPriority(
          deviceId: deviceId,
          priority: ConnectionPriority.highPerformance,
        );
      } else {
        await requester(deviceId, ConnectionPriority.highPerformance);
      }
    } catch (error) {
      log.w('Could not request high-performance BLE connection: $error');
    }
    try {
      final requester = mtuRequester;
      final mtu = requester == null
          ? await flutterReactiveBle.requestMtu(deviceId: deviceId, mtu: 247)
          : await requester(deviceId, 247);
      if (mtu >= 23) {
        _effectiveAttPayload = mtu - 3;
      }
      log.d('Negotiated BLE ATT MTU: $mtu');
    } catch (error) {
      log.w('Could not negotiate BLE ATT MTU 247: $error');
    }
  }

  Future<List> availableDevices({bool? isIOS}) async {
    if (inSearch) {
      log.w("Multiple searches in one time not allowed! FIXME");
      return [];
    }

    List<DiscoveredDevice> foundDevices = [];
    await performDisconnect();

    final completer = Completer<List<DiscoveredDevice>>();
    StreamSubscription<DiscoveredDevice>? subscription;
    var finished = false;

    Future<void> finishScan({
      List<DiscoveredDevice>? result,
      Object? error,
      StackTrace? stackTrace,
    }) async {
      if (finished) return;
      finished = true;
      final timer = _scanTimer;
      final activeSubscription = subscription;
      if (identical(_scanTimer, timer)) _scanTimer = null;
      if (identical(_scanSubscription, activeSubscription)) {
        _scanSubscription = null;
      }
      timer?.cancel();
      inSearch = false;
      try {
        await activeSubscription?.cancel();
      } catch (cancelError, cancelStackTrace) {
        log.e(
          'Could not cancel BLE scan',
          error: cancelError,
          stackTrace: cancelStackTrace,
        );
      }
      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(error, stackTrace ?? StackTrace.current);
      } else {
        final devices = result ?? foundDevices;
        completer.complete(devices);
        log.d('Found BLE devices: ${devices.length}');
      }
    }

    inSearch = true;
    try {
      subscription = flutterReactiveBle.scanForDevices(
        withServices: [nrfUUID, dfuUUID],
        scanMode: ScanMode.lowLatency,
      ).listen((device) {
        if (!foundDevices.contains(device)) {
          for (var foundDevice in foundDevices) {
            if (foundDevice.id == device.id) {
              return;
            }
          }
          foundDevices.add(device);
        }
      }, onError: (Object error, StackTrace stackTrace) {
        log.e("Got BLE search error: $error");
        if (isIOS ?? Platform.isIOS) {
          unawaited(finishScan(error: error, stackTrace: stackTrace));
        } else {
          unawaited(finishScan(result: []));
        }
      }, onDone: () {
        unawaited(finishScan());
      });
      _scanSubscription = subscription;
      if (!finished) {
        _scanTimer = Timer(scanDuration, () {
          unawaited(finishScan());
        });
      } else {
        final completedSubscription = subscription;
        if (identical(_scanSubscription, completedSubscription)) {
          _scanSubscription = null;
        }
        await completedSubscription.cancel();
      }
    } catch (error, stackTrace) {
      log.e(
        'Could not start BLE scan',
        error: error,
        stackTrace: stackTrace,
      );
      if (isIOS ?? Platform.isIOS) {
        await finishScan(error: error, stackTrace: stackTrace);
      } else {
        await finishScan(result: []);
      }
    }

    return completer.future;
  }

  @override
  bool isManualConnectionSupported() {
    return false;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];
    for (var bleDevice in await availableDevices()) {
      var dfuMode = false;
      if (bleDevice.name.startsWith('ChameleonUltra')) {
        device = ChameleonDevice.ultra;
      } else if (bleDevice.name.startsWith('ChameleonLite')) {
        device = ChameleonDevice.lite;
      } else if (bleDevice.name.startsWith('CU-')) {
        device = ChameleonDevice.ultra;
        dfuMode = true;
      } else if (bleDevice.name.startsWith('CL-')) {
        device = ChameleonDevice.lite;
        dfuMode = true;
      } else {
        // regular nRF device with UART
        continue;
      }

      connectionType = ConnectionType.ble;

      log.d("Found Chameleon ${chameleonDeviceName(device)}!");
      if (!onlyDFU || onlyDFU && dfuMode) {
        output.add(Chameleon(
            port: bleDevice.id,
            device: device,
            type: connectionType,
            dfu: dfuMode));
      }

      chameleonMap[bleDevice.id] = Chameleon(
          port: bleDevice.id,
          device: device,
          type: connectionType,
          dfu: dfuMode);
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    // As BLE is unstable, we try to connect 5 times
    // And fail only then
    final retryGeneration = ++_connectRetryGeneration;
    bool ret = false;
    for (var i = 0; i < 5; i++) {
      if (retryGeneration != _connectRetryGeneration) return false;
      ret = await connectSpecificInternal(devicePort);
      if (retryGeneration != _connectRetryGeneration) return false;
      if (ret) {
        break;
      }
    }

    return ret;
  }

  Future<bool> connectSpecificInternal(dynamic devicePort) async {
    final completer = Completer<bool>();
    void completeAttempt(bool value) {
      if (!completer.isCompleted) completer.complete(value);
      if (identical(_connectionCompleter, completer)) {
        _connectionCompleter = null;
      }
    }

    List<Uuid> services = [nrfUUID, uartRX, uartTX];
    if (chameleonMap[devicePort]!.dfu) {
      services = [dfuUUID, dfuControl, dfuFirmware];
    }

    await _performDisconnect(cancelRetryLoop: false);
    final generation = ++_connectionGeneration;
    _connectionCompleter = completer;
    pendingConnection = true;
    final timeoutTimer = Timer(connectionAttemptTimeout, () {
      unawaited(_disconnectGeneration(
        generation,
        error: TimeoutException(
          'BLE connection attempt timed out',
          connectionAttemptTimeout,
        ),
      ));
    });

    try {
      final candidateConnection = flutterReactiveBle
          .connectToAdvertisingDevice(
        id: devicePort,
        withServices: services,
        prescanDuration: const Duration(seconds: 5),
        connectionTimeout: connectionAttemptTimeout,
      )
          .listen((connectionState) async {
        if (generation != _connectionGeneration) return;
        log.w(connectionState);
        if (connectionState.connectionState ==
            DeviceConnectionState.connected) {
          try {
            await optimizeConnection(connectionState.deviceId);
            if (generation != _connectionGeneration) return;
            if (chameleonMap[devicePort]!.dfu) {
              txCharacteristic = QualifiedCharacteristic(
                  serviceId: dfuUUID,
                  characteristicId: dfuControl,
                  deviceId: connectionState.deviceId);
              receivedDataStream = flutterReactiveBle
                  .subscribeToCharacteristic(txCharacteristic!);
              await receivedDataSubscription?.cancel();
              if (generation != _connectionGeneration) return;
              receivedDataSubscription =
                  receivedDataStream!.listen((data) async {
                if (generation != _connectionGeneration) return;
                if (messageCallback != null) {
                  try {
                    await messageCallback(Uint8List.fromList(data));
                  } catch (_) {
                    log.w(
                        "Received unexpected data: ${bytesToHex(Uint8List.fromList(data))}");
                  }
                }
              }, onError: (Object error, StackTrace stackTrace) {
                unawaited(_disconnectGeneration(
                  generation,
                  error: error,
                  stackTrace: stackTrace,
                ));
              }, onDone: () {
                unawaited(_disconnectGeneration(generation));
              });

              rxCharacteristic = QualifiedCharacteristic(
                  serviceId: dfuUUID,
                  characteristicId: dfuControl,
                  deviceId: connectionState.deviceId);

              firmwareCharacteristic = QualifiedCharacteristic(
                  serviceId: dfuUUID,
                  characteristicId: dfuFirmware,
                  deviceId: connectionState.deviceId);

              portName = devicePort;
              device = chameleonMap[devicePort]!.device;
              activeDevicePort = devicePort;

              connected = true;
              pendingConnection = false;
              connectionType = ConnectionType.ble;
              isDFU = true;
              completeAttempt(true);
            } else {
              txCharacteristic = QualifiedCharacteristic(
                  serviceId: nrfUUID,
                  characteristicId: uartTX,
                  deviceId: connectionState.deviceId);
              receivedDataStream = flutterReactiveBle
                  .subscribeToCharacteristic(txCharacteristic!);
              await receivedDataSubscription?.cancel();
              if (generation != _connectionGeneration) return;
              receivedDataSubscription =
                  receivedDataStream!.listen((data) async {
                if (generation != _connectionGeneration) return;
                if (messageCallback != null) {
                  try {
                    await messageCallback(Uint8List.fromList(data));
                  } catch (_) {
                    log.w(
                        "Received unexpected data: ${bytesToHex(Uint8List.fromList(data))}");
                  }
                }
              }, onError: (Object error, StackTrace stackTrace) {
                unawaited(_disconnectGeneration(
                  generation,
                  error: error,
                  stackTrace: stackTrace,
                ));
              }, onDone: () {
                unawaited(_disconnectGeneration(generation));
              });

              rxCharacteristic = QualifiedCharacteristic(
                  serviceId: nrfUUID,
                  characteristicId: uartRX,
                  deviceId: connectionState.deviceId);

              await write(Uint8List.fromList([
                0x11,
                0xef,
                0x03,
                0xfb,
                0x00,
                0x00,
                0x00,
                0x00,
                0x02,
                0x00
              ]));
              if (generation != _connectionGeneration) return;

              connected = true;
              pendingConnection = false;
              portName = devicePort;
              device = chameleonMap[devicePort]!.device;
              activeDevicePort = devicePort;

              connectionType = ConnectionType.ble;
              isDFU = false;

              completeAttempt(true);
            }
          } catch (error, stackTrace) {
            await _disconnectGeneration(
              generation,
              error: error,
              stackTrace: stackTrace,
            );
            completeAttempt(false);
          }
        } else if (connectionState.connectionState ==
            DeviceConnectionState.disconnected) {
          await _disconnectGeneration(generation);
          completeAttempt(false);
        }
      }, onError: (Object error, StackTrace stackTrace) {
        unawaited(_disconnectGeneration(
          generation,
          error: error,
          stackTrace: stackTrace,
        ));
      }, onDone: () {
        unawaited(_disconnectGeneration(generation));
      });
      if (generation == _connectionGeneration) {
        connection = candidateConnection;
      } else {
        await candidateConnection.cancel();
      }
    } catch (error, stackTrace) {
      await _disconnectGeneration(
        generation,
        error: error,
        stackTrace: stackTrace,
      );
      completeAttempt(false);
    }

    return completer.future.whenComplete(timeoutTimer.cancel);
  }

  Future<void> _disconnectGeneration(
    int generation, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (generation != _connectionGeneration) return;
    if (error != null) {
      log.e('BLE connection failed', error: error, stackTrace: stackTrace);
    }
    try {
      await _performDisconnect(cancelRetryLoop: false);
    } catch (cancelError, cancelStackTrace) {
      log.e(
        'Could not fully cancel BLE subscriptions',
        error: cancelError,
        stackTrace: cancelStackTrace,
      );
    }
  }

  @override
  Future<bool> performDisconnect() => _performDisconnect(cancelRetryLoop: true);

  Future<bool> _performDisconnect({required bool cancelRetryLoop}) async {
    if (cancelRetryLoop) _connectRetryGeneration++;
    final hadState = hasConnectionState || connection != null;
    _connectionGeneration++;
    final pendingCompleter = _connectionCompleter;
    _connectionCompleter = null;
    final receiveSubscription = receivedDataSubscription;
    final activeConnection = connection;
    receivedDataSubscription = null;
    connection = null;
    resetConnectionState();
    txCharacteristic = null;
    rxCharacteristic = null;
    firmwareCharacteristic = null;
    _resolvedRxCharacteristic = null;
    _resolvedFirmwareCharacteristic = null;
    receivedDataStream = null;
    _effectiveAttPayload = 20;
    try {
      await receiveSubscription?.cancel();
    } finally {
      try {
        await activeConnection?.cancel();
      } finally {
        if (pendingCompleter != null && !pendingCompleter.isCompleted) {
          pendingCompleter.complete(false);
        }
        if (hadState) {
          notifyConnectionStateChanged();
        }
      }
    }
    return activeConnection != null;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final requested = firmware ? firmwareCharacteristic : rxCharacteristic;
    if (requested == null) {
      throw StateError(
          'BLE ${firmware ? 'firmware' : 'RX'} characteristic unavailable');
    }
    final requester = writeRequester;
    final characteristic = requester == null
        ? firmware
            ? await _resolveFirmwareCharacteristic()
            : await _resolveRxCharacteristic()
        : null;

    Future<void> writeChunk(Uint8List chunk) async {
      if (requester != null) {
        await requester(requested, chunk, !firmware);
      } else {
        await characteristic!.write(chunk, withResponse: !firmware);
      }
    }

    if (command.isEmpty) {
      await writeChunk(command);
    } else {
      for (var offset = 0; offset < command.length;) {
        final candidateEnd = offset + _effectiveAttPayload;
        final end =
            candidateEnd < command.length ? candidateEnd : command.length;
        await writeChunk(Uint8List.fromList(command.sublist(offset, end)));
        offset = end;
      }
    }

    return true;
  }

  Future<Characteristic> _resolveRxCharacteristic() async {
    final cached = _resolvedRxCharacteristic;
    if (cached != null) return cached;
    final requested = rxCharacteristic;
    if (requested == null) {
      throw StateError('BLE RX characteristic unavailable');
    }
    final resolved = await flutterReactiveBle.resolveSingle(requested);
    if (!identical(rxCharacteristic, requested)) {
      throw StateError('BLE connection changed while resolving RX');
    }
    _resolvedRxCharacteristic = resolved;
    return resolved;
  }

  Future<Characteristic> _resolveFirmwareCharacteristic() async {
    final cached = _resolvedFirmwareCharacteristic;
    if (cached != null) return cached;
    final requested = firmwareCharacteristic;
    if (requested == null) {
      throw StateError('BLE firmware characteristic unavailable');
    }
    final resolved = await flutterReactiveBle.resolveSingle(requested);
    if (!identical(firmwareCharacteristic, requested)) {
      throw StateError('BLE connection changed while resolving firmware');
    }
    _resolvedFirmwareCharacteristic = resolved;
    return resolved;
  }
}
