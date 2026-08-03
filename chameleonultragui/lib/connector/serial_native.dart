import 'dart:async';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_abstract.dart';

class NativeSerial extends AbstractSerial {
  // Class for PC Serial Communication
  SerialPort? port;
  bool checkDFU = true;
  SerialPortReader? reader;
  StreamSubscription<Uint8List>? _readerSubscription;
  int _readerGeneration = 0;

  NativeSerial({required super.log});

  @override
  bool isManualConnectionSupported() {
    return true;
  }

  Future<List> availableDevices() async {
    return SerialPort.availablePorts;
  }

  @override
  Future<bool> performConnect() async {
    for (final port in await availableDevices()) {
      if (await connectDevice(port, true)) {
        portName = port;
        connected = true;
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> performDisconnect() async {
    final hadState = hasConnectionState || port != null || reader != null;
    final activeReader = reader;
    final activeSubscription = _readerSubscription;
    final activePort = port;
    _readerGeneration++;
    reader = null;
    _readerSubscription = null;
    port = null;
    resetConnectionState();
    try {
      try {
        await activeSubscription?.cancel();
        activeReader?.close();
      } finally {
        if (activePort != null) {
          try {
            if (activePort.isOpen) activePort.close();
          } finally {
            activePort.dispose();
          }
        }
      }
    } finally {
      if (hadState) notifyConnectionStateChanged();
    }
    return activePort != null;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];
    for (final port in await availableDevices()) {
      if (await connectDevice(port, false)) {
        if (onlyDFU) {
          if (checkDFU) {
            output.add(
              Chameleon(
                port: port,
                device: device,
                type: connectionType,
                dfu: checkDFU,
              ),
            );
          }
        } else {
          output.add(
            Chameleon(
              port: port,
              device: device,
              type: connectionType,
              dfu: checkDFU,
            ),
          );
        }
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    if (port != null || reader != null || hasConnectionState) {
      await performDisconnect();
    }
    if (await connectDevice(devicePort, true)) {
      portName = devicePort;
      connected = true;
      activeDevicePort = devicePort;
      return true;
    }
    return false;
  }

  @protected
  SerialPort createSerialPort(String address) => SerialPort(address);

  @protected
  void configureSerialPort(SerialPort candidate) {
    candidate.config = SerialPortConfig()
      ..baudRate = 115200
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none
      ..rts = SerialPortRts.flowControl
      ..cts = SerialPortCts.flowControl
      ..dsr = SerialPortDsr.flowControl
      ..dtr = SerialPortDtr.flowControl
      ..setFlowControl(SerialPortFlowControl.rtsCts);
  }

  Future<bool> connectDevice(String address, bool setPort) async {
    if (port != null && port!.isOpen && !setPort) {
      log.d("Chameleon is connected now");
    }

    log.d("Connecting to $address");
    SerialPort? candidate;
    var ownershipTransferred = false;
    try {
      candidate = createSerialPort(address);
      if (!candidate.openReadWrite()) return false;
      configureSerialPort(candidate);
      log.d("Connected to $address");
      log.d("Manufacturer: ${candidate.manufacturer}");
      log.d("Product: ${candidate.productName}");
      String? description;
      try {
        description = candidate.description?.toLowerCase();
      } catch (_) {
        // Optional USB metadata can be unavailable on otherwise valid ports.
      }
      bool isChameleon = false;
      if (candidate.manufacturer == "Proxgrind" ||
          (description?.contains("chameleon") ?? false)) {
        isChameleon = true;
        if ((candidate.productName ?? '').contains('ChameleonUltra')) {
          device = ChameleonDevice.ultra;
        } else if (description?.contains('ultra') ?? false) {
          device = ChameleonDevice.ultra;
        } else {
          device = ChameleonDevice.lite;
        }
      } else if (setPort) {
        isChameleon = true;
        device = ChameleonDevice.ultra;
      }

      if (isChameleon) {
        log.d("Found Chameleon ${chameleonDeviceName(device)}!");

        connectionType = ConnectionType.usb;

        checkDFU = candidate.vendorId == 0x1915;

        if (!candidate.close()) return false;

        if (setPort) {
          port = candidate;
          isDFU = checkDFU;
          ownershipTransferred = true;
        }

        return true;
      }

      candidate.close();
      return false;
    } on SerialPortError catch (e) {
      log.e(e);
      try {
        candidate?.close();
      } catch (_) {}
      return false;
    } catch (e, stackTrace) {
      log.e('Serial probe failed', error: e, stackTrace: stackTrace);
      return false;
    } finally {
      if (!ownershipTransferred && candidate != null) {
        try {
          if (candidate.isOpen) candidate.close();
        } finally {
          candidate.dispose();
        }
      }
    }
  }

  @override
  Future<void> open() async {
    port!.openReadWrite();
    final activeReader = SerialPortReader(port!, timeout: 2500);
    final generation = ++_readerGeneration;
    reader = activeReader;
    _readerSubscription = activeReader.stream.listen(
      (data) async {
        if (generation != _readerGeneration ||
            !identical(reader, activeReader)) {
          return;
        }
        try {
          await messageCallback(data);
        } catch (_) {
          log.w("Received unexpected data: ${bytesToHex(data)}");
        }
      },
      onDone: () async {
        if (generation != _readerGeneration ||
            !identical(reader, activeReader)) {
          return;
        }
        await performDisconnect();
      },
      onError: (_) async {
        if (generation != _readerGeneration ||
            !identical(reader, activeReader)) {
          return;
        }
        await performDisconnect();
      },
    );
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    return writeWithTimeout(command, firmware: firmware);
  }

  @override
  Future<bool> writeWithTimeout(
    Uint8List command, {
    bool firmware = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final written = port!.write(command, timeout: timeout.inMilliseconds);
    if (written != command.length) {
      throw TimeoutException(
        'Serial write timed out after $written of ${command.length} bytes',
        timeout,
      );
    }
    return true;
  }
}
