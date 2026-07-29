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

  test(
    'monitor aborts baseline, saves changes, and never sends command 1009',
    () async {
      final fixture = await _fixture();
      fixture.state.emulationMonitorInterval = const Duration(milliseconds: 30);
      fixture.state.startEmulationChangeMonitor();

      await _waitFor(() => fixture.serial.abortCount == 1);
      fixture.serial.memory[17] = 0x5A;
      await fixture.serial.saveStarted.future;

      expect(fixture.preferences.getEmulationChangeHistory(), isEmpty);
      expect(fixture.state.latestEmulationChange, isNull);
      expect(fixture.serial.commands, isNot(contains(1009)));

      fixture.serial.saveGate.complete();
      await _waitFor(
        () => fixture.preferences.getEmulationChangeHistory().length == 1,
      );
      fixture.state.stopEmulationChangeMonitor();

      expect(fixture.serial.snapshotOperations.take(4), [0, 2, 0, 1]);
      expect(fixture.serial.saveCount, 1);
      expect(fixture.state.latestEmulationChange!.changes.single.block, 1);
      expect(fixture.serial.commands, isNot(contains(1009)));
      fixture.state.dispose();
    },
  );

  test(
    'random anticollision UID changes do not replace stable snapshot owner',
    () async {
      final fixture = await _fixture(randomUid: true);
      fixture.state.emulationMonitorInterval = const Duration(milliseconds: 30);
      fixture.state.startEmulationChangeMonitor();

      await _waitFor(() => fixture.serial.abortCount == 1);
      fixture.serial.memory[32] = 0x6B;
      await fixture.serial.saveStarted.future;
      fixture.serial.saveGate.complete();
      await _waitFor(
        () => fixture.preferences.getEmulationChangeHistory().length == 1,
      );
      fixture.state.stopEmulationChangeMonitor();

      expect(fixture.serial.antiCollCount, greaterThanOrEqualTo(2));
      expect(fixture.serial.saveCount, 1);
      expect(fixture.state.latestEmulationChange!.changes.single.block, 2);
      fixture.state.dispose();
    },
  );

  test(
    'monitor best-effort aborts a snapshot cancelled during reads',
    () async {
      final fixture = await _fixture(blockFirstRead: true);
      fixture.state.emulationMonitorInterval = const Duration(seconds: 1);
      fixture.state.startEmulationChangeMonitor();
      await fixture.serial.readStarted.future;

      await fixture.state.setEmulationChangeMonitoring(false);
      fixture.serial.readGate.complete();
      await _waitFor(() => fixture.serial.abortCount == 1);

      expect(fixture.serial.snapshotOperations, [0, 2]);
      expect(fixture.serial.chunkReadCount, 1);
      expect(fixture.serial.saveCount, 0);
      expect(fixture.preferences.getEmulationChangeHistory(), isEmpty);
      expect(fixture.serial.commands, isNot(contains(1009)));
      fixture.state.dispose();
    },
  );

  test('cancellation during anticollision stops all chunk reads', () async {
    final fixture = await _fixture(blockAntiColl: true);
    fixture.state.emulationMonitorInterval = const Duration(seconds: 1);
    fixture.state.startEmulationChangeMonitor();
    await fixture.serial.antiCollStarted.future;

    await fixture.state.setEmulationChangeMonitoring(false);
    fixture.serial.antiCollGate.complete();
    await _waitFor(() => fixture.serial.abortCount == 1);

    expect(fixture.serial.chunkReadCount, 0);
    expect(fixture.serial.snapshotOperations, [0, 2]);
    fixture.state.dispose();
  });

  test('failed SAVE_RELEASE is aborted and does not advance history', () async {
    final fixture = await _fixture(failSave: true);
    fixture.state.emulationMonitorInterval = const Duration(milliseconds: 30);
    fixture.state.startEmulationChangeMonitor();

    await _waitFor(() => fixture.serial.abortCount == 1);
    fixture.serial.memory[0] = 0xA5;
    await fixture.serial.saveStarted.future;
    fixture.serial.saveGate.complete();
    await _waitFor(() => fixture.serial.abortCount == 2);
    await fixture.state.setEmulationChangeMonitoring(false);

    expect(fixture.serial.snapshotOperations.take(5), [0, 2, 0, 1, 2]);
    expect(fixture.preferences.getEmulationChangeHistory(), isEmpty);
    expect(fixture.state.latestEmulationChange, isNull);
    fixture.state.dispose();
  });

  test(
    'history failure stays pending and retries without another device save',
    () async {
      final fixture = await _fixture();
      var persistenceAttempts = 0;
      fixture.preferences.debugEmulationChangeWriteInterceptor = (_) async {
        persistenceAttempts++;
        return false;
      };
      fixture.state.emulationMonitorInterval = const Duration(milliseconds: 40);
      fixture.state.startEmulationChangeMonitor();

      await _waitFor(() => fixture.serial.abortCount == 1);
      fixture.serial.memory[48] = 0x9C;
      await fixture.serial.saveStarted.future;
      fixture.serial.saveGate.complete();
      await _waitFor(() => persistenceAttempts == 1);

      expect(fixture.serial.saveCount, 1);
      expect(fixture.preferences.getEmulationChangeHistory(), isEmpty);
      expect(fixture.state.latestEmulationChange, isNull);
      expect(fixture.state.emulationChangeSequence, 0);

      fixture.preferences.debugEmulationChangeWriteInterceptor = null;
      await _waitFor(
        () => fixture.preferences.getEmulationChangeHistory().length == 1,
      );
      fixture.state.stopEmulationChangeMonitor();

      expect(fixture.serial.saveCount, 1);
      expect(fixture.state.latestEmulationChange, isNotNull);
      expect(fixture.state.emulationChangeSequence, 1);
      fixture.state.dispose();
    },
  );

  test('legacy capability mode never starts the automatic monitor', () async {
    final fixture = await _fixture(legacyCapabilities: true);
    fixture.state.emulationMonitorInterval = const Duration(milliseconds: 1);
    fixture.state.startEmulationChangeMonitor();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fixture.serial.snapshotOperations, isEmpty);
    fixture.state.dispose();
  });
}

Future<_SnapshotFixture> _fixture({
  bool blockFirstRead = false,
  bool blockAntiColl = false,
  bool randomUid = false,
  bool advertiseSnapshot = true,
  bool failSave = false,
  bool legacyCapabilities = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'emulation_change_monitoring': true,
    'auto_scan_enabled': false,
  });
  final preferences = SharedPreferencesProvider();
  await preferences.load();
  preferences.debugEmulationChangeWriteInterceptor = null;
  final serial =
      _SnapshotSerial(
          blockFirstRead: blockFirstRead,
          blockAntiColl: blockAntiColl,
          randomUid: randomUid,
          advertiseSnapshot: advertiseSnapshot,
          failSave: failSave,
          legacyCapabilities: legacyCapabilities,
        )
        ..connected = true
        ..connectionType = ConnectionType.usb;
  final communicator = ChameleonCommunicator(
    Logger(level: Level.off),
    port: serial,
  );
  await communicator.initializeCapabilities();
  final state = ChameleonGUIState(preferences)
    ..log = Logger(level: Level.off)
    ..connector = serial
    ..communicator = communicator;
  return _SnapshotFixture(state, serial, preferences);
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for snapshot monitor');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _SnapshotFixture {
  const _SnapshotFixture(this.state, this.serial, this.preferences);

  final ChameleonGUIState state;
  final _SnapshotSerial serial;
  final SharedPreferencesProvider preferences;
}

class _SnapshotSerial extends AbstractSerial {
  _SnapshotSerial({
    required this.blockFirstRead,
    required this.blockAntiColl,
    required this.randomUid,
    required this.advertiseSnapshot,
    required this.failSave,
    required this.legacyCapabilities,
  }) : super(log: Logger(level: Level.off));

  final bool blockFirstRead;
  final bool blockAntiColl;
  final bool randomUid;
  final bool advertiseSnapshot;
  final bool failSave;
  final bool legacyCapabilities;
  final Uint8List memory = Uint8List(64 * 16);
  final List<int> commands = [];
  final List<int> snapshotOperations = [];
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> readGate = Completer<void>();
  final Completer<void> antiCollStarted = Completer<void>();
  final Completer<void> antiCollGate = Completer<void>();
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> saveGate = Completer<void>();
  int abortCount = 0;
  int saveCount = 0;
  int chunkReadCount = 0;
  int antiCollCount = 0;
  int _revision = 0;
  bool _didBlockRead = false;

  @override
  Future<void> open() async {
    isOpen = true;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final id = (command[2] << 8) | command[3];
    final length = (command[6] << 8) | command[7];
    final data = command.sublist(9, 9 + length);
    commands.add(id);

    if (id == ChameleonCommand.getDeviceCapabilities.value) {
      if (legacyCapabilities) {
        await _emit(id, const [], status: 0x67);
        return true;
      }
      final capabilities = <int>[
        ChameleonCommand.getDeviceCapabilities.value,
        ChameleonCommand.mf1GetBlockData.value,
        ChameleonCommand.mf1GetAntiCollData.value,
        if (advertiseSnapshot) ChameleonCommand.activeSlotSnapshot.value,
      ];
      await _emit(id, [
        for (final capability in capabilities) ...[
          capability >> 8,
          capability & 0xFF,
        ],
      ]);
      return true;
    }

    if (id == ChameleonCommand.activeSlotSnapshot.value) {
      final operation = data[1];
      snapshotOperations.add(operation);
      if (operation == 0) {
        _revision++;
        await _emit(id, [2, 0, 0, 0x03, 0xE9, 0, 0, 0, 42, ..._u32(_revision)]);
      } else if (operation == 1) {
        if (!saveStarted.isCompleted) saveStarted.complete();
        await saveGate.future;
        saveCount++;
        await _emit(id, data, status: failSave ? 0x70 : chameleonStatusSuccess);
      } else {
        abortCount++;
        await _emit(id, data);
      }
      return true;
    }

    if (id == ChameleonCommand.mf1GetAntiCollData.value) {
      antiCollCount++;
      if (blockAntiColl && antiCollCount == 1) {
        antiCollStarted.complete();
        await antiCollGate.future;
      }
      final uidLastByte = randomUid ? antiCollCount : 4;
      await _emit(id, [4, 1, 2, 3, uidLastByte, 0x04, 0x00, 0x08, 0]);
      return true;
    }

    if (id == ChameleonCommand.mf1GetBlockData.value) {
      chunkReadCount++;
      if (blockFirstRead && !_didBlockRead) {
        _didBlockRead = true;
        readStarted.complete();
        await readGate.future;
      }
      final start = data[0] * 16;
      final end = start + data[1] * 16;
      await _emit(id, memory.sublist(start, end));
      return true;
    }

    throw StateError('Unexpected monitor command $id');
  }

  List<int> _u32(int value) => [
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

  Future<void> _emit(
    int id,
    List<int> data, {
    int status = chameleonStatusSuccess,
  }) async {
    final frame = <int>[
      0x11,
      0xEF,
      id >> 8,
      id & 0xFF,
      status >> 8,
      status & 0xFF,
      data.length >> 8,
      data.length & 0xFF,
    ];
    frame.add(_lrc(frame.sublist(2, 8)));
    frame.addAll(data);
    frame.add(_lrc(frame));
    await messageCallback(frame);
  }

  int _lrc(List<int> data) {
    var sum = 0;
    for (final byte in data) {
      sum = (sum + byte) & 0xFF;
    }
    return (0x100 - sum) & 0xFF;
  }

  @override
  Future<bool> performDisconnect() async {
    connected = false;
    isOpen = false;
    return true;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => false;

  @override
  bool isManualConnectionSupported() => false;
}
