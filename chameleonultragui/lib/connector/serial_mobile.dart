import 'dart:async';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

// Class for Android Serial Communication
class MobileSerial extends AbstractSerial {
  Map<String, UsbDevice> deviceMap = {};
  UsbPort? port;
  StreamSubscription<Uint8List>? _inputSubscription;
  StreamSubscription<UsbEvent>? _usbEventSubscription;
  var _connectionGeneration = 0;

  MobileSerial({required super.log});

  @override
  bool isManualConnectionSupported() {
    return false;
  }

  @override
  Future<bool> performDisconnect() async {
    final hadState = hasConnectionState ||
        port != null ||
        _inputSubscription != null ||
        _usbEventSubscription != null;
    final inputSubscription = _inputSubscription;
    final usbEventSubscription = _usbEventSubscription;
    final activePort = port;
    _connectionGeneration++;
    _inputSubscription = null;
    _usbEventSubscription = null;
    port = null;
    resetConnectionState();
    try {
      await inputSubscription?.cancel();
    } finally {
      try {
        await usbEventSubscription?.cancel();
      } finally {
        try {
          if (activePort != null) await activePort.close();
        } finally {
          if (hadState) notifyConnectionStateChanged();
        }
      }
    }
    return activePort != null;
  }

  @protected
  Future<List<UsbDevice>> listUsbDevices() => UsbSerial.listDevices();

  @protected
  Future<UsbPort?> createUsbPort(UsbDevice device) => device.create();

  @protected
  Stream<UsbEvent>? get usbEvents => UsbSerial.usbEventStream;

  Future<List> availableDevices() async {
    device = ChameleonDevice.none;
    connectionType = ConnectionType.none;
    List<UsbDevice> availableDevices = await listUsbDevices();
    List output = [];
    deviceMap = {};

    for (var deviceValue in availableDevices) {
      deviceMap[deviceValue.deviceName] = deviceValue;
      output.add(deviceValue.deviceName);
    }

    return output;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];
    for (var deviceName in await availableDevices()) {
      if (deviceMap[deviceName]!.manufacturerName == "Proxgrind") {
        if (deviceMap[deviceName]!.productName!.startsWith('ChameleonUltra')) {
          device = ChameleonDevice.ultra;
        } else {
          device = ChameleonDevice.lite;
        }

        log.d("Found Chameleon ${chameleonDeviceName(device)}!");

        var dfuMode = deviceMap[deviceName]!.vid == 0x1915;

        if (onlyDFU) {
          if (dfuMode) {
            output.add(Chameleon(
                port: deviceName,
                device: device,
                type: ConnectionType.usb,
                dfu: dfuMode));
          }
        } else {
          output.add(Chameleon(
              port: deviceName,
              device: device,
              type: ConnectionType.usb,
              dfu: dfuMode));
        }
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    await performDisconnect();
    await availableDevices();
    if (deviceMap.containsKey(devicePort)) {
      final selectedDevice = deviceMap[devicePort]!;
      final candidate = await createUsbPort(selectedDevice);
      if (candidate == null) return false;
      final generation = ++_connectionGeneration;
      port = candidate;
      if ((selectedDevice.productName ?? '').contains('ChameleonUltra')) {
        device = ChameleonDevice.ultra;
      } else {
        device = ChameleonDevice.lite;
      }

      try {
        bool openResult = await candidate.open();
        if (!openResult) {
          await _disconnectGeneration(generation);
          return false;
        }

        await candidate.setRTS(true);
        await candidate.setDTR(true);

        await candidate.setPortParameters(115200, UsbPort.DATABITS_8,
            UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

        final input = candidate.inputStream;
        final events = usbEvents;
        if (input == null || events == null) {
          throw StateError('USB serial streams are unavailable');
        }
        _inputSubscription = input.listen((Uint8List data) async {
          if (generation != _connectionGeneration || port != candidate) return;
          final callback = messageCallback;
          if (callback == null) return;
          try {
            await callback(data);
          } catch (_) {
            log.w("Received unexpected data: ${bytesToHex(data)}");
          }
        },
            onDone: () => unawaited(_disconnectGeneration(generation)),
            onError: (_) => unawaited(_disconnectGeneration(generation)));

        _usbEventSubscription = events.listen((event) {
          if (generation == _connectionGeneration &&
              port == candidate &&
              event.event == UsbEvent.ACTION_USB_DETACHED &&
              event.device?.deviceName == devicePort) {
            log.w("Chameleon disconnected from USB");
            unawaited(_disconnectGeneration(generation));
          }
        });

        connected = true;
        connectionType = ConnectionType.usb;
        activeDevicePort = devicePort;
        final deviceName = devicePort.toString();
        portName = deviceName.length > 15
            ? deviceName.substring(deviceName.length - 15)
            : deviceName;
        isDFU = selectedDevice.vid == 0x1915;

        return true;
      } catch (_) {
        await _disconnectGeneration(generation);
        rethrow;
      }
    }
    return false;
  }

  Future<void> _disconnectGeneration(int generation) async {
    if (generation != _connectionGeneration) return;
    await performDisconnect();
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    await port!.write(command);
    return true;
  }
}
