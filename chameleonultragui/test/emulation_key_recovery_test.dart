import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/emulation_key_recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'HF emulation recovers successive sectors and restores temporary trailers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesProvider();
      await preferences.load();
      final communicator = _EmulationRecoveryCommunicator();
      final controller = Mf1EmulationKeyRecoveryController(
        preferences,
        pollInterval: const Duration(days: 1),
        solver: (request) async =>
            request.nt0 < 10 ? 0x010203040506 : 0xA0A1A2A3A4A5,
      );
      addTearDown(controller.dispose);

      await controller.start(
        communicator: communicator,
        slot: 0,
        tagType: TagType.mifare1K,
        runSlotOperation: (operation) => operation(),
      );

      expect(controller.active, isTrue);
      expect(communicator.detectionEnabled, isTrue);
      expect(communicator.animationEnabled, isTrue);

      communicator.records.addAll([
        _record(block: 4, nt: 1, nr: 11, ar: 21),
        _record(block: 5, nt: 2, nr: 12, ar: 22),
      ]);
      await controller.pollNow();

      expect(controller.capturedNonceCount, 2);
      expect(controller.recoveredKeyCount, 1);
      expect(controller.recoveredSectorCount, 1);
      expect(controller.recoveredResults.single.target.sector, 1);
      expect(communicator.reselectCount, 1);
      expect(communicator.blocks[7]!.sublist(0, 6), [1, 2, 3, 4, 5, 6]);

      communicator.records.addAll([
        _record(block: 8, nt: 10, nr: 20, ar: 30),
        _record(block: 9, nt: 11, nr: 21, ar: 31, successful: true),
      ]);
      await controller.pollNow();

      expect(controller.capturedNonceCount, 4);
      expect(controller.recoveredKeyCount, 2);
      expect(controller.recoveredSectorCount, 2);
      expect(controller.verifiedKeyCount, 1);
      expect(
        controller.recoveredResults.map((result) => result.target.sector),
        [1, 2],
      );
      expect(communicator.reselectCount, 2);
      expect(communicator.blocks[11]!.sublist(0, 6), [
        0xA0,
        0xA1,
        0xA2,
        0xA3,
        0xA4,
        0xA5,
      ]);

      final dictionary = preferences
          .getDictionaries(keyLength: 12)
          .singleWhere((entry) => entry.id == 'hf-emulation-11223344');
      expect(dictionary.keys.map(bytesToHex).toSet(), {
        '010203040506',
        'a0a1a2a3a4a5',
      });

      await controller.stop(communicator: communicator);

      expect(controller.active, isFalse);
      expect(communicator.detectionEnabled, isFalse);
      expect(communicator.animationEnabled, isFalse);
      expect(communicator.blocks[7], communicator.originalBlocks[7]);
      expect(communicator.blocks[11], communicator.originalBlocks[11]);
    },
  );

  test('stop waits for an in-flight start and performs cleanup once', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _EmulationRecoveryCommunicator();
    final enableGate = Completer<void>();
    communicator.detectionEnableGate = enableGate;
    final controller = Mf1EmulationKeyRecoveryController(
      preferences,
      pollInterval: const Duration(days: 1),
      solver: (_) async => null,
    );
    addTearDown(controller.dispose);

    final start = controller.start(
      communicator: communicator,
      slot: 0,
      tagType: TagType.mifare1K,
      runSlotOperation: (operation) => operation(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(communicator.detectionEnableCalls, 1);

    final firstStop = controller.stop(communicator: communicator);
    final secondStop = controller.stop(communicator: communicator);
    expect(identical(firstStop, secondStop), isTrue);
    enableGate.complete();

    await start;
    await firstStop;
    expect(controller.active, isFalse);
    expect(controller.cleanupPending, isFalse);
    expect(communicator.detectionEnabled, isFalse);
    expect(communicator.detectionDisableCalls, 1);
    expect(communicator.animationEnabled, isFalse);
  });

  test(
    'failed in-flight start does not leave the controller stopping',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesProvider();
      await preferences.load();
      final communicator = _EmulationRecoveryCommunicator();
      final enableGate = Completer<void>();
      communicator
        ..detectionEnableGate = enableGate
        ..failDetectionEnable = true;
      final controller = Mf1EmulationKeyRecoveryController(
        preferences,
        pollInterval: const Duration(days: 1),
        solver: (_) async => null,
      );
      addTearDown(controller.dispose);

      final start = controller.start(
        communicator: communicator,
        slot: 0,
        tagType: TagType.mifare1K,
        runSlotOperation: (operation) => operation(),
      );
      final startFailure = expectLater(start, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final stop = controller.stop(communicator: communicator);
      enableGate.complete();

      await startFailure;
      await stop;
      expect(controller.isStopping, isFalse);
      expect(controller.cleanupPending, isFalse);
      expect(controller.active, isFalse);
    },
  );

  test('failed trailer rollback remains retryable', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _EmulationRecoveryCommunicator();
    final controller = Mf1EmulationKeyRecoveryController(
      preferences,
      pollInterval: const Duration(days: 1),
      solver: (_) async => 0x010203040506,
    );
    addTearDown(controller.dispose);

    await controller.start(
      communicator: communicator,
      slot: 0,
      tagType: TagType.mifare1K,
      runSlotOperation: (operation) => operation(),
    );
    communicator.records.addAll([
      _record(block: 4, nt: 1, nr: 11, ar: 21),
      _record(block: 5, nt: 2, nr: 12, ar: 22),
    ]);
    await controller.pollNow();
    expect(communicator.blocks[7], isNot(communicator.originalBlocks[7]));

    communicator.failNextBlockWrite = true;
    await expectLater(
      controller.stop(communicator: communicator),
      throwsStateError,
    );
    expect(controller.cleanupPending, isTrue);
    expect(communicator.blocks[7], isNot(communicator.originalBlocks[7]));
    expect(
      () => controller.start(
        communicator: communicator,
        slot: 0,
        tagType: TagType.mifare1K,
        runSlotOperation: (operation) => operation(),
      ),
      throwsStateError,
    );

    await controller.stop(communicator: communicator);
    expect(controller.cleanupPending, isFalse);
    expect(communicator.blocks[7], communicator.originalBlocks[7]);
  });

  test('full detection logs are frozen, drained, and rearmed', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _EmulationRecoveryCommunicator()
      ..clearRecordsOnEnable = true;
    final controller = Mf1EmulationKeyRecoveryController(
      preferences,
      pollInterval: const Duration(days: 1),
      solver: (_) async => 0x010203040506,
    );
    addTearDown(controller.dispose);

    await controller.start(
      communicator: communicator,
      slot: 0,
      tagType: TagType.mifare1K,
      runSlotOperation: (operation) => operation(),
    );
    communicator.records.addAll(
      List.generate(
        1000,
        (index) => _record(
          block: 4,
          nt: index + 1,
          nr: index + 1001,
          ar: index + 2001,
        ),
      ),
    );

    await controller.pollNow();

    expect(controller.capturedNonceCount, 1000);
    expect(controller.recoveredKeyCount, 1);
    expect(communicator.records, isEmpty);
    expect(communicator.detectionEnableCalls, 2);
    expect(communicator.detectionDisableCalls, 1);
    expect(communicator.detectionEnabled, isTrue);

    await controller.stop(communicator: communicator);
  });

  test(
    'failed final recovery remains retryable after hardware cleanup',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesProvider();
      await preferences.load();
      final communicator = _EmulationRecoveryCommunicator();
      var solverCalls = 0;
      final controller = Mf1EmulationKeyRecoveryController(
        preferences,
        pollInterval: const Duration(days: 1),
        solver: (_) async {
          if (solverCalls++ == 0) throw StateError('Simulated solver failure');
          return 0x010203040506;
        },
      );
      addTearDown(controller.dispose);

      await controller.start(
        communicator: communicator,
        slot: 0,
        tagType: TagType.mifare1K,
        runSlotOperation: (operation) => operation(),
      );
      communicator.records.addAll([
        _record(block: 4, nt: 1, nr: 11, ar: 21),
        _record(block: 5, nt: 2, nr: 12, ar: 22),
      ]);

      await expectLater(
        controller.stop(communicator: communicator),
        throwsStateError,
      );
      expect(controller.cleanupPending, isTrue);
      expect(communicator.detectionEnabled, isFalse);

      await controller.stop(communicator: communicator);
      expect(controller.cleanupPending, isFalse);
      expect(controller.recoveredKeyCount, 1);
      expect(solverCalls, 2);
    },
  );

  test('stale cleanup can be abandoned after a connection change', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final communicator = _EmulationRecoveryCommunicator()
      ..failDetectionDisableOnce = true;
    final controller = Mf1EmulationKeyRecoveryController(
      preferences,
      pollInterval: const Duration(days: 1),
      solver: (_) async => null,
    );
    addTearDown(controller.dispose);

    await controller.start(
      communicator: communicator,
      slot: 0,
      tagType: TagType.mifare1K,
      runSlotOperation: (operation) => operation(),
    );
    await expectLater(
      controller.stop(communicator: communicator),
      throwsStateError,
    );
    expect(controller.cleanupPending, isTrue);

    controller.abandon(communicator);
    expect(controller.cleanupPending, isFalse);
    expect(controller.error, contains('connection changed'));
  });
}

DetectionResult _record({
  required int block,
  required int nt,
  required int nr,
  required int ar,
  bool successful = false,
}) => DetectionResult(
  block: block,
  type: 0x60,
  isNested: false,
  isSuccessful: successful,
  uid: 0x11223344,
  nt: nt,
  nr: nr,
  ar: ar,
);

class _EmulationRecoveryCommunicator extends ChameleonCommunicator {
  _EmulationRecoveryCommunicator() : super(Logger(level: Level.off)) {
    for (final block in [7, 11]) {
      final trailer = Uint8List.fromList([
        ...List.filled(6, 0xFF),
        0xFF,
        0x07,
        0x80,
        0x69,
        ...List.filled(6, 0xFF),
      ]);
      originalBlocks[block] = Uint8List.fromList(trailer);
      blocks[block] = Uint8List.fromList(trailer);
    }
  }

  final List<DetectionResult> records = [];
  final Map<int, Uint8List> originalBlocks = {};
  final Map<int, Uint8List> blocks = {};
  bool detectionEnabled = false;
  bool animationEnabled = false;
  bool clearRecordsOnEnable = false;
  bool failDetectionEnable = false;
  bool failDetectionDisableOnce = false;
  bool failNextBlockWrite = false;
  Completer<void>? detectionEnableGate;
  int detectionEnableCalls = 0;
  int detectionDisableCalls = 0;
  int reselectCount = 0;

  @override
  bool? supportsCommandSync(ChameleonCommand command) => switch (command) {
    ChameleonCommand.mf1SetReaderKeysAnim ||
    ChameleonCommand.mf1ReaderKeysReselect => true,
    _ => super.supportsCommandSync(command),
  };

  @override
  Future<void> setMf1DetectionStatus(bool status) async {
    if (status) {
      detectionEnableCalls++;
      final gate = detectionEnableGate;
      detectionEnableGate = null;
      if (gate != null) await gate.future;
      if (failDetectionEnable) {
        failDetectionEnable = false;
        throw StateError('Simulated detection enable failure');
      }
      if (clearRecordsOnEnable) records.clear();
    } else {
      detectionDisableCalls++;
      if (failDetectionDisableOnce) {
        failDetectionDisableOnce = false;
        throw StateError('Simulated detection disable failure');
      }
    }
    detectionEnabled = status;
  }

  @override
  Future<void> setMf1ReaderKeysAnim(bool enabled) async {
    animationEnabled = enabled;
  }

  @override
  Future<int> getMf1DetectionCount() async => records.length;

  @override
  Future<List<DetectionResult>> getMf1DetectionRecords(
    int count, {
    int startIndex = 0,
  }) async => List<DetectionResult>.from(records.sublist(startIndex, count));

  @override
  Future<int> getActiveSlot() async => 0;

  @override
  Future<Uint8List> mf1GetEmulatorBlock(int block, int count) async =>
      Uint8List.fromList(blocks[block]!);

  @override
  Future<void> setMf1BlockData(int startBlock, Uint8List data) async {
    if (failNextBlockWrite) {
      failNextBlockWrite = false;
      throw StateError('Simulated trailer write failure');
    }
    blocks[startBlock] = Uint8List.fromList(data);
  }

  @override
  Future<void> reselectMf1ReaderKeys({int muteMs = 150}) async {
    reselectCount++;
  }
}
