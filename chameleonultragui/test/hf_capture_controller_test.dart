import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/chameleon_frame_decoder.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/helpers/hf_capture_controller.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists a page before acknowledging its last sequence', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final temporary = await Directory.systemTemp.createTemp('hf-capture-test-');
    final serial = _CaptureSerial(temporary);
    final communicator = ChameleonCommunicator(
      Logger(level: Level.off),
      port: serial,
    );
    final controller = HfCaptureController(
      preferences,
      directoryProvider: () async => temporary,
    );
    addTearDown(() async {
      controller.dispose();
      communicator.dispose();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    await communicator.initializeCapabilities();
    await controller.attach(communicator);
    await controller.start(HfCaptureMode.emulation);
    await serial.persistedAcknowledgement.future.timeout(
      const Duration(seconds: 10),
    );

    expect(serial.pageExistedBeforeAcknowledgement, isTrue);
    expect(serial.ackDeliveryTokens, [11]);
    expect(
      controller.persistedBytes,
      hfCapturePageHeaderSize + serial.record.length,
    );
    expect(controller.recentRecords.single.sequence, 0);

    final captureDirectory = controller.captureDirectory!;
    await controller.stop();
    final activeManifest = File(
      '${temporary.path}/hf-captures/active-0102030405060708.json',
    );
    expect(await activeManifest.exists(), isFalse);
    expect(await File('$captureDirectory/summary.json').exists(), isTrue);
  });

  test('resumes and drains retained records from a stopped session', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final temporary = await Directory.systemTemp.createTemp('hf-capture-test-');
    final root = Directory('${temporary.path}/hf-captures');
    final session = Directory('${root.path}/session-existing');
    await Directory('${session.path}/pages').create(recursive: true);
    final active = File('${root.path}/active-0102030405060708.json');
    await active.writeAsString(
      jsonEncode({
        'version': 2,
        'sessionId': 42,
        'bootId': 7,
        'startToken': 7,
        'deviceId': '0102030405060708',
        'mode': HfCaptureMode.emulation.value,
        'directory': 'session-existing',
        'startedAt': DateTime.utc(2026, 8, 2).toIso8601String(),
      }),
    );
    final serial = _CaptureSerial(temporary, hasRetainedSession: true);
    final communicator = ChameleonCommunicator(
      Logger(level: Level.off),
      port: serial,
    );
    final controller = HfCaptureController(
      preferences,
      directoryProvider: () async => temporary,
    );
    addTearDown(() async {
      controller.dispose();
      communicator.dispose();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    await communicator.initializeCapabilities();
    await controller.attach(communicator);
    await serial.persistedAcknowledgement.future.timeout(
      const Duration(seconds: 10),
    );

    expect(controller.isRunning, isFalse);
    expect(serial.statusTokens, [7]);
    expect(controller.needsDrain, isFalse);
    expect(controller.canStart, isTrue);
    expect(await active.exists(), isFalse);
    expect(await File('${session.path}/summary.json').exists(), isTrue);
    expect(
      session
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.hfcap')),
      hasLength(1),
    );
    expect(await File('${session.path}/summary.json').exists(), isTrue);
  });

  test(
    'recovers an uncertain START through owner-only STATUS discovery',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesProvider();
      await preferences.load();
      final temporary = await Directory.systemTemp.createTemp(
        'hf-capture-test-',
      );
      final root = Directory('${temporary.path}/hf-captures');
      final session = Directory('${root.path}/session-pending');
      await Directory('${session.path}/pages').create(recursive: true);
      final pending = File('${root.path}/pending-0102030405060708.json');
      await pending.writeAsString(
        jsonEncode({
          'version': 2,
          'deviceId': '0102030405060708',
          'startToken': 7,
          'transport': 'usb',
          'mode': HfCaptureMode.emulation.value,
          'directory': 'session-pending',
          'startedAt': DateTime.utc(2026, 8, 2).toIso8601String(),
        }),
      );
      final serial = _CaptureSerial(temporary, hasRetainedSession: true);
      final communicator = ChameleonCommunicator(
        Logger(level: Level.off),
        port: serial,
      );
      final controller = HfCaptureController(
        preferences,
        directoryProvider: () async => temporary,
      );
      addTearDown(() async {
        controller.dispose();
        communicator.dispose();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      await communicator.initializeCapabilities();
      await controller.attach(communicator);
      await serial.persistedAcknowledgement.future.timeout(
        const Duration(seconds: 10),
      );

      expect(serial.statusSessionIds, [0]);
      expect(serial.statusTokens, [7]);
      expect(await pending.exists(), isFalse);
      expect(await File('${session.path}/summary.json').exists(), isTrue);
      expect(controller.canStart, isTrue);
    },
  );

  test('ignores an active manifest owned by another device', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final temporary = await Directory.systemTemp.createTemp('hf-capture-test-');
    final root = Directory('${temporary.path}/hf-captures');
    final session = Directory('${root.path}/session-foreign');
    await Directory('${session.path}/pages').create(recursive: true);
    final active = File('${root.path}/active-ffffffffffffffff.json');
    await active.writeAsString(
      jsonEncode({
        'version': 2,
        'sessionId': 42,
        'bootId': 7,
        'startToken': 7,
        'deviceId': 'ffffffffffffffff',
        'mode': HfCaptureMode.emulation.value,
        'directory': 'session-foreign',
        'startedAt': DateTime.utc(2026, 8, 2).toIso8601String(),
      }),
    );
    final serial = _CaptureSerial(temporary);
    final communicator = ChameleonCommunicator(
      Logger(level: Level.off),
      port: serial,
    );
    final controller = HfCaptureController(
      preferences,
      directoryProvider: () async => temporary,
    );
    addTearDown(() async {
      controller.dispose();
      communicator.dispose();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    await communicator.initializeCapabilities();
    await controller.attach(communicator);

    expect(serial.statusRequests, 0);
    expect(controller.hasSession, isFalse);
    expect(controller.error, isNull);
    expect(controller.canStart, isTrue);
    expect(await active.exists(), isTrue);
  });

  test('validates every persisted page before sending an ACK', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final temporary = await Directory.systemTemp.createTemp('hf-capture-test-');
    final root = Directory('${temporary.path}/hf-captures');
    final session = Directory('${root.path}/session-corrupt');
    final pages = Directory('${session.path}/pages');
    await pages.create(recursive: true);
    final active = File('${root.path}/active-0102030405060708.json');
    await active.writeAsString(
      jsonEncode({
        'version': 2,
        'sessionId': 42,
        'bootId': 7,
        'startToken': 7,
        'deviceId': '0102030405060708',
        'mode': HfCaptureMode.emulation.value,
        'directory': 'session-corrupt',
        'startedAt': DateTime.utc(2026, 8, 2).toIso8601String(),
      }),
    );
    await File(
      '${pages.path}/0000000000-0000000000-0000000000-00000000.hfcap',
    ).writeAsBytes([0]);
    final serial = _CaptureSerial(
      temporary,
      hasRetainedSession: true,
      retainedStopped: false,
    );
    final communicator = ChameleonCommunicator(
      Logger(level: Level.off),
      port: serial,
    );
    final controller = HfCaptureController(
      preferences,
      directoryProvider: () async => temporary,
    );
    addTearDown(() async {
      controller.dispose();
      communicator.dispose();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    await communicator.initializeCapabilities();
    await controller.attach(communicator);

    expect(serial.statusRequests, 1);
    expect(serial.getRequests, 0);
    expect(serial.stopRequests, 1);
    expect(controller.canStart, isFalse);
    expect(controller.error, contains('before ACK'));
    expect(await active.exists(), isTrue);
  });

  test(
    'does not START until capture storage passes its write preflight',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesProvider();
      await preferences.load();
      final temporary = await Directory.systemTemp.createTemp(
        'hf-capture-test-',
      );
      final serial = _CaptureSerial(temporary);
      final communicator = ChameleonCommunicator(
        Logger(level: Level.off),
        port: serial,
      );
      final controller = HfCaptureController(
        preferences,
        directoryProvider: () async => temporary,
      );
      addTearDown(() async {
        controller.dispose();
        communicator.dispose();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      await communicator.initializeCapabilities();
      await controller.attach(communicator);
      final root = Directory('${temporary.path}/hf-captures');
      await root.delete(recursive: true);
      await File(root.path).writeAsString('not a directory');

      await expectLater(
        controller.start(HfCaptureMode.emulation),
        throwsA(isA<FileSystemException>()),
      );
      expect(serial.startRequests, 0);
    },
  );

  test('accepts a retained prefix loss explained by dropped records', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final temporary = await Directory.systemTemp.createTemp('hf-capture-test-');
    final serial = _CaptureSerial(
      temporary,
      recordSequence: 7,
      droppedRecords: 7,
    );
    final communicator = ChameleonCommunicator(
      Logger(level: Level.off),
      port: serial,
    );
    final controller = HfCaptureController(
      preferences,
      directoryProvider: () async => temporary,
    );
    addTearDown(() async {
      controller.dispose();
      communicator.dispose();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    await communicator.initializeCapabilities();
    await controller.attach(communicator);
    await controller.start(HfCaptureMode.emulation);
    await serial.persistedAcknowledgement.future.timeout(
      const Duration(seconds: 10),
    );

    expect(controller.recentRecords.single.sequence, 7);
    expect(controller.error, isNull);
  });

  test('archives local evidence when the device session is gone', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final temporary = await Directory.systemTemp.createTemp('hf-capture-test-');
    final root = Directory('${temporary.path}/hf-captures');
    final session = Directory('${root.path}/session-abandoned');
    await Directory('${session.path}/pages').create(recursive: true);
    final active = File('${root.path}/active-0102030405060708.json');
    await active.writeAsString(
      jsonEncode({
        'version': 2,
        'sessionId': 42,
        'bootId': 7,
        'startToken': 7,
        'deviceId': '0102030405060708',
        'mode': HfCaptureMode.emulation.value,
        'directory': 'session-abandoned',
        'startedAt': DateTime.utc(2026, 8, 2).toIso8601String(),
      }),
    );
    final serial = _CaptureSerial(temporary);
    final communicator = ChameleonCommunicator(
      Logger(level: Level.off),
      port: serial,
    );
    final controller = HfCaptureController(
      preferences,
      directoryProvider: () async => temporary,
    );
    addTearDown(() async {
      controller.dispose();
      communicator.dispose();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    await communicator.initializeCapabilities();
    await controller.attach(communicator);

    final summary =
        jsonDecode(await File('${session.path}/summary.json').readAsString())
            as Map<String, dynamic>;
    expect(await active.exists(), isFalse);
    expect(summary['cleanlyDrained'], isFalse);
    expect(summary['incompleteReason'], 'device-session-unavailable');
    expect(controller.canStart, isTrue);
  });

  test('rolls back controller attachment after storage failure', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final temporary = await Directory.systemTemp.createTemp('hf-capture-test-');
    final serial = _CaptureSerial(temporary);
    final communicator = ChameleonCommunicator(
      Logger(level: Level.off),
      port: serial,
    );
    final controller = HfCaptureController(
      preferences,
      directoryProvider: () => throw const FileSystemException('unavailable'),
    );
    addTearDown(() async {
      controller.dispose();
      communicator.dispose();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    await communicator.initializeCapabilities();
    await expectLater(
      controller.attach(communicator),
      throwsA(isA<FileSystemException>()),
    );

    expect(controller.isConnected, isFalse);
    expect(controller.error, contains('Unable to attach'));
  });
}

class _CaptureSerial extends AbstractSerial {
  _CaptureSerial(
    this.documents, {
    this.hasRetainedSession = false,
    this.retainedStopped = true,
    this.recordSequence = 0,
    this.droppedRecords = 0,
  }) : stopped = hasRetainedSession && retainedStopped,
       super(log: Logger(level: Level.off)) {
    connectionType = ConnectionType.usb;
    connected = true;
    record = Uint8List.fromList([
      ..._u16(21),
      hfCaptureProtocolVersion,
      1,
      ..._u32(recordSequence),
      ..._u64(1),
      0,
      0,
      ..._u16(8),
      ..._u16(1),
      0x26,
    ]);
  }

  final Directory documents;
  final bool hasRetainedSession;
  final bool retainedStopped;
  final int recordSequence;
  final int droppedRecords;
  final Completer<void> persistedAcknowledgement = Completer<void>();
  bool pageExistedBeforeAcknowledgement = false;
  bool stopped;
  int statusRequests = 0;
  final List<int> statusSessionIds = [];
  final List<int> statusTokens = [];
  int startRequests = 0;
  int startToken = 7;
  int stopRequests = 0;
  int getRequests = 0;
  final List<int> ackDeliveryTokens = [];

  late final Uint8List record;

  @override
  Future<void> open() async {
    isOpen = true;
  }

  @override
  Future<bool> write(Uint8List frame, {bool firmware = false}) async {
    final command = (frame[2] << 8) | frame[3];
    final length = (frame[6] << 8) | frame[7];
    final payload = frame.sublist(9, 9 + length);
    if (command == ChameleonCommand.getDeviceCapabilities.value) {
      await _emit(
        command,
        Uint8List.fromList([
          for (final value in [
            ChameleonCommand.getDeviceCapabilities.value,
            ChameleonCommand.getDeviceChipID.value,
            ChameleonCommand.hfCaptureStart.value,
            ChameleonCommand.hfCaptureStatus.value,
            ChameleonCommand.hfCaptureGet.value,
            ChameleonCommand.hfCaptureStop.value,
          ]) ...[value >> 8, value & 0xFF],
        ]),
      );
    } else if (command == ChameleonCommand.getDeviceChipID.value) {
      await _emit(command, Uint8List.fromList(List.generate(8, (i) => i + 1)));
    } else if (command == ChameleonCommand.hfCaptureStatus.value) {
      statusRequests++;
      statusSessionIds.add(_readU32(payload, 1));
      statusTokens.add(_readU32(payload, 5));
      if (hasRetainedSession) {
        await _emit(
          command,
          _metadata(
            state: stopped ? 2 : 1,
            firstSequence: recordSequence,
            nextSequence: (recordSequence + 1) & 0xFFFFFFFF,
            storedRecords: 1,
            observedRecords: droppedRecords + 1,
            droppedRecords: droppedRecords,
            usedBytes: record.length,
          ),
        );
      } else {
        await _emit(command, Uint8List(0), status: 0x75);
      }
    } else if (command == ChameleonCommand.hfCaptureStart.value) {
      startRequests++;
      startToken = _readU32(payload, 2);
      await _emit(command, _metadata(nextSequence: 0));
    } else if (command == ChameleonCommand.hfCaptureStop.value) {
      stopRequests++;
      stopped = true;
      await _emit(
        command,
        _metadata(
          state: 2,
          firstSequence: (recordSequence + 1) & 0xFFFFFFFF,
          nextSequence: (recordSequence + 1) & 0xFFFFFFFF,
          observedRecords: droppedRecords + 1,
          droppedRecords: droppedRecords,
        ),
      );
    } else if (command == ChameleonCommand.hfCaptureGet.value) {
      getRequests++;
      final hasAcknowledgement = payload[5] == 1;
      if (!hasAcknowledgement) {
        await _emit(command, _pageWithRecord());
      } else {
        ackDeliveryTokens.add(_readU64(payload, 10));
        final pages = Directory('${documents.path}/hf-captures');
        final persistedPages = pages
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.hfcap'))
            .toList();
        if (persistedPages.length == 1) {
          try {
            final bytes = await persistedPages.single.readAsBytes();
            final page = HfCapturePage.decode(bytes);
            pageExistedBeforeAcknowledgement =
                page.pageBytes.length ==
                hfCapturePageHeaderSize + record.length;
          } catch (_) {}
        }
        if (!persistedAcknowledgement.isCompleted) {
          persistedAcknowledgement.complete();
        }
        await _emit(command, _emptyPage());
      }
    }
    return true;
  }

  Uint8List _pageWithRecord() => Uint8List.fromList([
    ..._metadata(
      state: stopped ? 2 : 1,
      firstSequence: recordSequence,
      nextSequence: (recordSequence + 1) & 0xFFFFFFFF,
      storedRecords: 1,
      observedRecords: droppedRecords + 1,
      droppedRecords: droppedRecords,
      usedBytes: record.length,
    ),
    ..._u32(recordSequence),
    ..._u32((recordSequence + 1) & 0xFFFFFFFF),
    ..._u16(1),
    ..._u16(record.length),
    ..._u32(_crc32(record)),
    ..._u64(11),
    ...record,
  ]);

  Uint8List _emptyPage() => Uint8List.fromList([
    ..._metadata(
      state: stopped ? 2 : 1,
      firstSequence: (recordSequence + 1) & 0xFFFFFFFF,
      nextSequence: (recordSequence + 1) & 0xFFFFFFFF,
      observedRecords: droppedRecords + 1,
      droppedRecords: droppedRecords,
    ),
    ..._u32((recordSequence + 1) & 0xFFFFFFFF),
    ..._u32((recordSequence + 1) & 0xFFFFFFFF),
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);

  Uint8List _metadata({
    int state = 1,
    int firstSequence = 0,
    required int nextSequence,
    int storedRecords = 0,
    int observedRecords = 0,
    int droppedRecords = 0,
    int usedBytes = 0,
  }) => Uint8List.fromList([
    hfCaptureProtocolVersion,
    state,
    0,
    droppedRecords > 0 ? 1 : 0,
    ..._u32(42),
    ..._u32(firstSequence),
    ..._u32(nextSequence),
    ..._u32(storedRecords),
    ..._u32(observedRecords),
    ..._u32(droppedRecords),
    ..._u16(usedBytes),
    ..._u16(8192),
    ..._u64(1),
    ..._u32(7),
    ..._u32(startToken),
  ]);

  Future<void> _emit(
    int command,
    Uint8List data, {
    int status = chameleonStatusSuccess,
  }) => messageCallback(
    buildChameleonFrame(command: command, status: status, data: data),
  );

  @override
  Future<bool> performDisconnect() async => true;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;

  @override
  bool isManualConnectionSupported() => false;
}

List<int> _u16(int value) => [value >> 8, value & 0xFF];

List<int> _u32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u64(int value) => [
  for (var shift = 56; shift >= 0; shift -= 8) (value >> shift) & 0xFF,
];

int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320);
    }
  }
  return (~crc) & 0xFFFFFFFF;
}

int _readU32(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

int _readU64(Uint8List data, int offset) {
  var value = 0;
  for (var index = 0; index < 8; index++) {
    value = (value << 8) | data[offset + index];
  }
  return value;
}
