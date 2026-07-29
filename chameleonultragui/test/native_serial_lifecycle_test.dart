import 'package:chameleonultragui/connector/serial_native.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  test('rejected native probes are closed and disposed', () async {
    final ports = List.generate(
      20,
      (index) => _FakeSerialPort(
        manufacturer: 'Other',
        productName: 'Port $index',
      ),
    );
    final serial = _TestNativeSerial(ports);

    expect(await serial.availableChameleons(false), isEmpty);

    for (final port in ports) {
      expect(port.closeCount, 1);
      expect(port.disposeCount, 1);
    }
    expect(serial.port, isNull);
  });

  test('recognized discovery probe is disposed rather than retained', () async {
    final candidate = _FakeSerialPort(
      manufacturer: 'Proxgrind',
      productName: 'ChameleonUltra',
    );
    final serial = _TestNativeSerial([candidate]);

    final devices = await serial.availableChameleons(false);

    expect(devices, hasLength(1));
    expect(candidate.closeCount, 1);
    expect(candidate.disposeCount, 1);
    expect(serial.port, isNull);
  });

  test('selected native port is disposed exactly once at disconnect', () async {
    final candidate = _FakeSerialPort(
      manufacturer: 'Proxgrind',
      productName: 'ChameleonUltra',
    );
    final serial = _TestNativeSerial([candidate]);

    expect(await serial.connectSpecificDevice('port-0'), isTrue);
    expect(candidate.closeCount, 1);
    expect(candidate.disposeCount, 0);
    expect(serial.port, same(candidate));

    expect(await serial.performDisconnect(), isTrue);
    expect(candidate.closeCount, 1);
    expect(candidate.disposeCount, 1);
    expect(await serial.performDisconnect(), isFalse);
    expect(candidate.disposeCount, 1);
  });

  test('configuration failure closes and disposes the probe', () async {
    final candidate = _FakeSerialPort(
      manufacturer: 'Proxgrind',
      productName: 'ChameleonUltra',
    );
    final serial = _TestNativeSerial([candidate], failConfiguration: true);

    expect(await serial.connectDevice('port-0', false), isFalse);
    expect(candidate.closeCount, 1);
    expect(candidate.disposeCount, 1);
  });
}

class _TestNativeSerial extends NativeSerial {
  _TestNativeSerial(
    this.candidates, {
    this.failConfiguration = false,
  }) : super(log: Logger(level: Level.off));

  final List<_FakeSerialPort> candidates;
  final bool failConfiguration;
  var _nextCandidate = 0;

  @override
  Future<List> availableDevices() async =>
      List.generate(candidates.length, (index) => 'port-$index');

  @override
  SerialPort createSerialPort(String address) => candidates[_nextCandidate++];

  @override
  void configureSerialPort(SerialPort candidate) {
    if (failConfiguration) throw StateError('configuration failed');
  }
}

class _FakeSerialPort implements SerialPort {
  _FakeSerialPort({
    required this.manufacturer,
    required this.productName,
  });

  @override
  final String? manufacturer;
  @override
  final String? productName;
  @override
  final int? vendorId = 0x6868;

  bool _open = false;
  int closeCount = 0;
  int disposeCount = 0;

  @override
  bool get isOpen => _open;

  @override
  bool openReadWrite() {
    _open = true;
    return true;
  }

  @override
  bool close() {
    closeCount++;
    _open = false;
    return true;
  }

  @override
  void dispose() {
    disposeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
