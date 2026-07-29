import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_mobile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:usb_serial/usb_serial.dart';

void main() {
  test('reconnect retains one USB input and detach subscription', () async {
    final events = StreamController<UsbEvent>.broadcast();
    final ports = List.generate(5, (_) => _FakeUsbPort());
    final serial = _TestMobileSerial(ports, events.stream);

    for (var index = 0; index < ports.length; index++) {
      expect(await serial.connectSpecificDevice(_deviceName), isTrue);
      expect(ports[index].inputController.hasListener, isTrue);
      expect(events.hasListener, isTrue);
      for (var previous = 0; previous < index; previous++) {
        expect(ports[previous].inputController.hasListener, isFalse);
        expect(ports[previous].closeCount, 1);
      }
    }

    await serial.performDisconnect();
    for (final port in ports) {
      expect(port.inputController.hasListener, isFalse);
      expect(port.closeCount, 1);
    }
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('matching USB detach tears down the current generation once', () async {
    final events = StreamController<UsbEvent>.broadcast();
    final port = _FakeUsbPort();
    final serial = _TestMobileSerial([port], events.stream);
    expect(await serial.connectSpecificDevice(_deviceName), isTrue);

    events.add(_event(UsbEvent.ACTION_USB_DETACHED, 'other'));
    await Future<void>.delayed(Duration.zero);
    expect(port.closeCount, 0);

    events.add(_event(UsbEvent.ACTION_USB_DETACHED, _deviceName));
    await _waitFor(() => port.closeCount == 1);
    expect(serial.connected, isFalse);
    expect(port.inputController.hasListener, isFalse);
    expect(events.hasListener, isFalse);

    events.add(_event(UsbEvent.ACTION_USB_DETACHED, _deviceName));
    await Future<void>.delayed(Duration.zero);
    expect(port.closeCount, 1);
    await events.close();
  });

  test('failed USB open closes the owned candidate without listeners',
      () async {
    final events = StreamController<UsbEvent>.broadcast();
    final port = _FakeUsbPort(openResult: false);
    final serial = _TestMobileSerial([port], events.stream);

    expect(await serial.connectSpecificDevice(_deviceName), isFalse);
    expect(port.closeCount, 1);
    expect(port.inputController.hasListener, isFalse);
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('USB configuration error awaits teardown', () async {
    final events = StreamController<UsbEvent>.broadcast();
    final port = _FakeUsbPort(failConfiguration: true);
    final serial = _TestMobileSerial([port], events.stream);

    await expectLater(
      serial.connectSpecificDevice(_deviceName),
      throwsA(isA<StateError>()),
    );
    expect(port.closeCount, 1);
    expect(port.inputController.hasListener, isFalse);
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('subscription cancellation error still closes remaining resources',
      () async {
    final events = StreamController<UsbEvent>.broadcast();
    final port = _FakeUsbPort(failInputCancel: true);
    final serial = _TestMobileSerial([port], events.stream);
    expect(await serial.connectSpecificDevice(_deviceName), isTrue);

    await expectLater(serial.performDisconnect(), throwsA(isA<StateError>()));
    expect(port.closeCount, 1);
    expect(events.hasListener, isFalse);
    await events.close();
  });
}

const _deviceName = '/dev/chameleon-usb';

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for teardown');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

UsbEvent _event(String action, String deviceName) {
  return UsbEvent()
    ..event = action
    ..device = UsbDevice(
      deviceName,
      0x6868,
      1,
      'ChameleonUltra',
      'Proxgrind',
      1,
      'serial',
      1,
    );
}

class _TestMobileSerial extends MobileSerial {
  _TestMobileSerial(this.ports, this.events)
      : super(log: Logger(level: Level.off));

  final List<_FakeUsbPort> ports;
  final Stream<UsbEvent> events;
  var _nextPort = 0;

  UsbDevice get deviceDescription => UsbDevice(
        _deviceName,
        0x6868,
        1,
        'ChameleonUltra',
        'Proxgrind',
        1,
        'serial',
        1,
      );

  @override
  Future<List<UsbDevice>> listUsbDevices() async => [deviceDescription];

  @override
  Future<UsbPort?> createUsbPort(UsbDevice device) async => ports[_nextPort++];

  @override
  Stream<UsbEvent>? get usbEvents => events;
}

class _FakeUsbPort implements UsbPort {
  _FakeUsbPort({
    this.openResult = true,
    this.failConfiguration = false,
    this.failInputCancel = false,
  }) : inputController = StreamController<Uint8List>(
          onCancel: failInputCancel
              ? () => Future<void>.error(
                    StateError('input cancellation failed'),
                  )
              : null,
        );

  final bool openResult;
  final bool failConfiguration;
  final bool failInputCancel;
  final StreamController<Uint8List> inputController;
  int closeCount = 0;

  @override
  Stream<Uint8List> get inputStream => inputController.stream;

  @override
  Future<bool> open() async => openResult;

  @override
  Future<bool> close() async {
    await Future<void>.delayed(Duration.zero);
    closeCount++;
    return true;
  }

  @override
  Future<void> setRTS(bool value) async {}

  @override
  Future<void> setDTR(bool value) async {
    if (failConfiguration) throw StateError('configuration failed');
  }

  @override
  Future<void> setPortParameters(
      int baudRate, int dataBits, int stopBits, int parity) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
