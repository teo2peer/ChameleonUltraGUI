import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/pm3_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  test('bootstraps capabilities once and serializes commands', () async {
    final serial = _FakeSerial();
    final communicator = _communicator(serial);

    await Future.wait([
      communicator.sendCmd(ChameleonCommand.getAppVersion),
      communicator.sendCmd(ChameleonCommand.getDeviceMode),
    ]);

    expect(serial.maxConcurrentWrites, 1);
    expect(serial.commands, [
      ChameleonCommand.getDeviceCapabilities.value,
      ChameleonCommand.getAppVersion.value,
      ChameleonCommand.getDeviceMode.value,
    ]);
  });

  test('rejects commands absent from the advertised capabilities', () async {
    final serial = _FakeSerial(
      capabilities: {
        ChameleonCommand.getDeviceCapabilities.value,
        ChameleonCommand.getAppVersion.value,
      },
    );
    final communicator = _communicator(serial);

    await expectLater(
      communicator.sendCmd(ChameleonCommand.getDeviceMode),
      throwsA(isA<ChameleonUnsupportedCommandException>()),
    );
    expect(serial.commands, [ChameleonCommand.getDeviceCapabilities.value]);
  });

  test('caches capability reads', () async {
    final serial = _FakeSerial();
    final communicator = _communicator(serial);

    expect(
      await communicator.supportsCommand(ChameleonCommand.getAppVersion),
      isTrue,
    );
    expect(
      await communicator.supportsCommand(ChameleonCommand.getDeviceMode),
      isTrue,
    );
    expect(await communicator.getDeviceCapabilities(), isNotEmpty);

    expect(
      serial.commands.where(
        (id) => id == ChameleonCommand.getDeviceCapabilities.value,
      ),
      hasLength(1),
    );
  });

  for (final legacyStatus in [0x67, 0x69]) {
    test(
      'allows optimistic commands for legacy status 0x${legacyStatus.toRadixString(16)}',
      () async {
        final serial = _FakeSerial(capabilityStatus: legacyStatus);
        final communicator = _communicator(serial);

        await communicator.sendCmd(ChameleonCommand.getAppVersion);

        expect(
          await communicator.supportsCommand(ChameleonCommand.getDeviceMode),
          isNull,
        );
        expect(serial.commands, [
          ChameleonCommand.getDeviceCapabilities.value,
          ChameleonCommand.getAppVersion.value,
        ]);
      },
    );
  }

  test('rejects malformed capability payloads', () async {
    final serial = _FakeSerial(capabilityPayload: Uint8List.fromList([0x01]));
    final communicator = _communicator(serial);

    await expectLater(
      communicator.initializeCapabilities(),
      throwsFormatException,
    );
    expect(serial.commands, [ChameleonCommand.getDeviceCapabilities.value]);
  });

  test('parses the complete v6 device settings payload', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.getDeviceSettings.value) {
          await serial.emit(
            id,
            data: [6, 3, 1, 2, 4, 5, 1, ...'654321'.codeUnits, 42],
          );
        }
      },
    );
    final settings = await _communicator(serial).getDeviceSettings();

    expect(settings.key, '654321');
    expect(settings.pairingEnabled, isTrue);
    expect(settings.wakeTimeSeconds, 42);
  });

  test(
    'keeps compatibility with the legacy 13-byte v6 settings payload',
    () async {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == ChameleonCommand.getDeviceSettings.value) {
            await serial.emit(
              id,
              data: [6, 3, 1, 2, 4, 5, 0, ...'123456'.codeUnits],
            );
          }
        },
      );
      final settings = await _communicator(serial).getDeviceSettings();

      expect(settings.key, '123456');
      expect(settings.pairingEnabled, isFalse);
      expect(settings.wakeTimeSeconds, isNull);
    },
  );

  test(
    'keeps compatibility with the legacy 13-byte v5 settings payload',
    () async {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == ChameleonCommand.getDeviceSettings.value) {
            await serial.emit(
              id,
              data: [5, 3, 1, 2, 4, 5, 0, ...'123456'.codeUnits],
            );
          }
        },
      );
      final settings = await _communicator(serial).getDeviceSettings();

      expect(settings.key, '123456');
      expect(settings.pairingEnabled, isFalse);
      expect(settings.wakeTimeSeconds, isNull);
    },
  );

  test('saveSlotData surfaces flash write failures', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.saveSlotNicks.value) {
          await serial.emit(id, status: 0x77);
        }
      },
    );

    await expectLater(
      _communicator(serial).saveSlotData(),
      throwsA(isA<ChameleonCommandException>()),
    );
  });

  test(
    'active-slot snapshot uses exact versioned big-endian wire contract',
    () async {
      const revision = 0x10203040;
      const ownerGeneration = 0x50607080;
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == ChameleonCommand.activeSlotSnapshot.value) {
            final request = serial.commandData[id]!;
            if (request[1] == 0) {
              await serial.emit(
                id,
                data: [
                  2,
                  0,
                  2,
                  0x03,
                  0xE9,
                  0x50,
                  0x60,
                  0x70,
                  0x80,
                  0x10,
                  0x20,
                  0x30,
                  0x40,
                ],
              );
            } else {
              await serial.emit(id, data: request);
            }
          } else if (id == ChameleonCommand.mf1GetAntiCollData.value) {
            await serial.emit(id, data: [4, 1, 2, 3, 4, 0x04, 0x00, 0x08, 0]);
          } else if (id == ChameleonCommand.mf1GetBlockData.value) {
            await serial.emit(id, data: List.filled(32, 0xA5));
          }
        },
      );
      final communicator = _communicator(serial);

      final snapshot = await communicator.beginActiveSlotSnapshot();
      final card = await communicator.mf1GetSnapshotAntiColl(snapshot);
      final blocks = await communicator.mf1GetSnapshotBlocks(snapshot, 4, 2);
      await communicator.saveReleaseActiveSlotSnapshot(snapshot);

      expect(snapshot.slot, 2);
      expect(snapshot.tagType, TagType.mifare1K);
      expect(snapshot.ownerGeneration, ownerGeneration);
      expect(snapshot.revision, revision);
      expect(card.uid, [1, 2, 3, 4]);
      expect(blocks, List.filled(32, 0xA5));
      expect(
        serial.commandPayloads
            .where(
              (entry) => entry.$1 == ChameleonCommand.activeSlotSnapshot.value,
            )
            .map((entry) => entry.$2),
        [
          [2, 0],
          [2, 1, 0x10, 0x20, 0x30, 0x40],
        ],
      );
      expect(
        activeSlotSnapshotSaveTimeout.inMilliseconds,
        greaterThan(activeSlotSnapshotCommitMaxMilliseconds),
      );
    },
  );

  test(
    'active-slot snapshot requires explicit advertised capability',
    () async {
      final capabilities =
          ChameleonCommand.values.map((command) => command.value).toSet()
            ..remove(ChameleonCommand.activeSlotSnapshot.value);
      final serial = _FakeSerial(capabilities: capabilities);

      await expectLater(
        _communicator(serial).beginActiveSlotSnapshot(),
        throwsA(isA<ChameleonUnsupportedCommandException>()),
      );
      expect(serial.commands, [ChameleonCommand.getDeviceCapabilities.value]);
    },
  );

  test('malformed BEGIN with a revision sends best-effort ABORT', () async {
    var snapshotCalls = 0;
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (snapshotCalls++ == 0) {
          await serial.emit(
            id,
            data: [2, 0, 8, 0x03, 0xE9, 0, 0, 0, 7, 0, 0, 0, 9],
          );
        } else {
          await serial.emit(id, data: serial.commandData[id]!);
        }
      },
    );

    await expectLater(
      _communicator(serial).beginActiveSlotSnapshot(),
      throwsFormatException,
    );
    expect(
      serial.commandPayloads
          .where(
            (entry) => entry.$1 == ChameleonCommand.activeSlotSnapshot.value,
          )
          .map((entry) => entry.$2),
      [
        [2, 0],
        [2, 2, 0, 0, 0, 9],
      ],
    );
    expect(serial.disconnected, isFalse);
  });

  test('v1 or truncated successful BEGIN poisons the connection', () async {
    for (final payload in <List<int>>[
      [],
      [1, 0, 0, 0x03, 0xE9, 0, 0, 0, 1],
      [2, 0, 0, 0x03, 0xE9, 0, 0, 0, 7, 0, 0, 0],
    ]) {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else {
            await serial.emit(id, data: payload);
          }
        },
      );
      final communicator = _communicator(serial);
      await expectLater(
        communicator.beginActiveSlotSnapshot(),
        throwsFormatException,
      );
      expect(serial.disconnected, isTrue);
      await expectLater(
        communicator.getFirmwareVersion(),
        throwsA(isA<ChameleonCommunicatorClosedException>()),
      );
    }
  });

  test(
    'active-slot snapshot rejects malformed successful end responses',
    () async {
      const transaction = MifareClassicActiveSlotSnapshot(
        slot: 0,
        tagType: TagType.mifare1K,
        ownerGeneration: 1,
        revision: 1,
      );
      for (final payload in <List<int>>[
        [],
        [2, 2, 0, 0, 0, 1],
        [2, 1, 0, 0, 0, 2],
        [2, 1, 0, 0, 0, 1, 0],
      ]) {
        final serial = _FakeSerial(
          onCommand: (serial, id) async {
            if (id == ChameleonCommand.getDeviceCapabilities.value) {
              await serial.emitCapabilities();
            } else {
              await serial.emit(id, data: payload);
            }
          },
        );
        await expectLater(
          _communicator(serial).saveReleaseActiveSlotSnapshot(transaction),
          throwsFormatException,
        );
        expect(serial.disconnected, isTrue);
      }
    },
  );

  test(
    'SAVE_RELEASE response timeout poisons instead of quarantining',
    () async {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          }
        },
      );
      final communicator = _communicator(
        serial,
        snapshotSaveTimeout: const Duration(milliseconds: 10),
      );
      const transaction = MifareClassicActiveSlotSnapshot(
        slot: 0,
        tagType: TagType.mifare1K,
        ownerGeneration: 1,
        revision: 1,
      );

      await expectLater(
        communicator.saveReleaseActiveSlotSnapshot(transaction),
        throwsA(isA<ChameleonResponseTimeoutException>()),
      );
      expect(serial.disconnected, isTrue);
      await expectLater(
        communicator.getFirmwareVersion(),
        throwsA(isA<ChameleonCommunicatorClosedException>()),
      );
    },
  );

  test('frozen MIFARE reads enforce range, status, and exact length', () async {
    const snapshot = MifareClassicActiveSlotSnapshot(
      slot: 0,
      tagType: TagType.mifare1K,
      ownerGeneration: 1,
      revision: 1,
    );
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.mf1GetBlockData.value) {
          await serial.emit(id, data: List.filled(15, 0));
        }
      },
    );
    final communicator = _communicator(serial);

    await expectLater(
      communicator.mf1GetSnapshotBlocks(snapshot, 64, 1),
      throwsRangeError,
    );
    await expectLater(
      communicator.mf1GetSnapshotBlocks(snapshot, 0, 1),
      throwsFormatException,
    );

    final failedSerial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else {
          await serial.emit(id, status: 0x70);
        }
      },
    );
    await expectLater(
      _communicator(failedSerial).mf1GetSnapshotBlocks(snapshot, 0, 1),
      throwsA(isA<ChameleonCommandException>()),
    );
  });

  test('write timeout invalidates the communicator and disconnects', () async {
    final command = ChameleonCommand.getAppVersion;
    final serial = _FakeSerial(hangingCommands: {command.value});
    final communicator = _communicator(
      serial,
      writeTimeout: const Duration(milliseconds: 10),
    );

    await communicator.initializeCapabilities();
    await expectLater(
      communicator.sendCmd(command),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(serial.disconnected, isTrue);
    await expectLater(
      communicator.sendCmd(ChameleonCommand.getDeviceMode),
      throwsA(isA<ChameleonCommunicatorClosedException>()),
    );
    expect(serial.commands, [
      ChameleonCommand.getDeviceCapabilities.value,
      command.value,
    ]);
  });

  test('non-timeout write failures invalidate and disconnect', () async {
    final command = ChameleonCommand.getAppVersion;
    final serial = _FakeSerial(failingCommands: {command.value});
    final communicator = _communicator(serial);
    await communicator.initializeCapabilities();

    await expectLater(communicator.sendCmd(command), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(serial.disconnected, isTrue);
    await expectLater(
      communicator.sendCmd(ChameleonCommand.getDeviceMode),
      throwsA(isA<ChameleonCommunicatorClosedException>()),
    );
  });

  test('partial response timeout invalidates the stream', () async {
    final command = ChameleonCommand.getAppVersion;
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == command.value) {
          final frame = serial.responseFrame(id, data: List.filled(10, 0));
          await serial.messageCallback(Uint8List.fromList(frame.sublist(0, 9)));
        }
      },
    );
    final communicator = _communicator(serial);

    await expectLater(
      communicator.sendCmd(command, timeout: const Duration(milliseconds: 10)),
      throwsA(isA<ChameleonResponseTimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(serial.disconnected, isTrue);
  });

  test('mutating wrappers surface firmware failures', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else {
          await serial.emit(id, status: 0x77);
        }
      },
    );

    await expectLater(
      _communicator(serial).setMf1BlockData(0, Uint8List(16)),
      throwsA(isA<ChameleonCommandException>()),
    );
  });

  test('reads one work-slot trailer with strict framing', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.mf1GetBlockData.value) {
          await serial.emit(id, data: List.generate(16, (index) => index));
        }
      },
    );

    final trailer = await _communicator(serial).mf1GetEmulatorBlock(3, 1);

    expect(trailer, List.generate(16, (index) => index));
    expect(serial.commandData[ChameleonCommand.mf1GetBlockData.value], [3, 1]);
  });

  test('rejects malformed work-slot block reads', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.mf1GetBlockData.value) {
          await serial.emit(id, data: List.filled(15, 0));
        }
      },
    );

    await expectLater(
      _communicator(serial).mf1GetEmulatorBlock(3, 1),
      throwsFormatException,
    );
  });

  test(
    'T55xx writer sends new password once and validates LF status',
    () async {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else {
            await serial.emit(id, status: 0x40);
          }
        },
      );
      final communicator = _communicator(serial);
      await communicator.writeEM410XtoT55XX(
        Uint8List.fromList([1, 2, 3, 4, 5]),
        Uint8List.fromList([6, 7, 8, 9]),
        [
          Uint8List.fromList([10, 11, 12, 13]),
        ],
      );

      expect(serial.commandData[ChameleonCommand.writeEM410XtoT5577.value], [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
      ]);
    },
  );

  test(
    'quarantines a timed-out command until its late response is discarded',
    () async {
      final command = ChameleonCommand.getAppVersion;
      var respond = false;
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (respond) {
            await serial.emit(id, data: [0x22]);
          }
        },
      );
      final communicator = _communicator(serial);
      await communicator.initializeCapabilities();

      await expectLater(
        communicator.sendCmd(
          command,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<ChameleonResponseTimeoutException>()),
      );
      await expectLater(
        communicator.sendCmd(command),
        throwsA(isA<ChameleonCommandResponseUncertainException>()),
      );
      expect(serial.commands.where((id) => id == command.value), hasLength(1));

      await serial.emit(command.value, data: [0x11]);
      respond = true;
      final response = await communicator.sendCmd(command);
      expect(response!.data, [0x22]);
    },
  );

  test(
    'discards a late response coalesced with another command response',
    () async {
      final timedOut = ChameleonCommand.getAppVersion;
      final next = ChameleonCommand.getDeviceMode;
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == next.value) {
            await serial.emitFrames([
              serial.responseFrame(timedOut.value, data: [0x11]),
              serial.responseFrame(next.value, data: [0x33]),
            ]);
          }
        },
      );
      final communicator = _communicator(serial);
      await communicator.initializeCapabilities();

      await expectLater(
        communicator.sendCmd(
          timedOut,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<ChameleonResponseTimeoutException>()),
      );
      final response = await communicator.sendCmd(next);
      expect(response!.data, [0x33]);
    },
  );

  test(
    'confirmed session reset clears an uncertain exchange quarantine',
    () async {
      final exchange = ChameleonCommand.hf14a4ReaderSessionExchange;
      final stop = ChameleonCommand.hf14a4ReaderSessionStop;
      var exchangeAttempts = 0;
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == exchange.value) {
            exchangeAttempts++;
            if (exchangeAttempts > 1) {
              await serial.emit(id, status: 0x00, data: [0x90, 0x00]);
            }
          } else if (id == stop.value) {
            await serial.emit(stop.value);
          }
        },
      );
      final communicator = _communicator(serial);
      await communicator.initializeCapabilities();

      await expectLater(
        communicator.sendCmd(
          exchange,
          data: Uint8List.fromList([0, 0, 0, 7, 0x00]),
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<ChameleonResponseTimeoutException>()),
      );
      await communicator.hf14a4ReaderSessionReset(7);

      expect(
        await communicator.hf14a4ReaderSessionExchange(
          8,
          Uint8List.fromList([0x00]),
        ),
        [0x90, 0x00],
      );
      expect(serial.disconnected, isFalse);
      expect(exchangeAttempts, 2);
    },
  );

  for (final resetStatus in [0x60, 0x66]) {
    test(
      'session reset accepts already-closed status 0x${resetStatus.toRadixString(16)}',
      () async {
        final exchange = ChameleonCommand.hf14a4ReaderSessionExchange;
        final stop = ChameleonCommand.hf14a4ReaderSessionStop;
        var exchangeAttempts = 0;
        final serial = _FakeSerial(
          onCommand: (serial, id) async {
            if (id == ChameleonCommand.getDeviceCapabilities.value) {
              await serial.emitCapabilities();
            } else if (id == exchange.value) {
              exchangeAttempts++;
              if (exchangeAttempts > 1) {
                await serial.emit(id, status: 0x00, data: [0x90, 0x00]);
              }
            } else if (id == stop.value) {
              await serial.emit(id, status: resetStatus);
            }
          },
        );
        final communicator = _communicator(serial);
        await communicator.initializeCapabilities();

        await expectLater(
          communicator.sendCmd(
            exchange,
            data: Uint8List.fromList([0, 0, 0, 7, 0x00]),
            timeout: const Duration(milliseconds: 10),
          ),
          throwsA(isA<ChameleonResponseTimeoutException>()),
        );
        await communicator.hf14a4ReaderSessionReset(7);
        expect(
          await communicator.hf14a4ReaderSessionExchange(
            8,
            Uint8List.fromList([0x00]),
          ),
          [0x90, 0x00],
        );
      },
    );
  }

  test(
    'failed session reset retains the uncertain exchange quarantine',
    () async {
      final exchange = ChameleonCommand.hf14a4ReaderSessionExchange;
      final stop = ChameleonCommand.hf14a4ReaderSessionStop;
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == stop.value) {
            await serial.emit(id, status: 0x75);
          }
        },
      );
      final communicator = _communicator(serial);
      await communicator.initializeCapabilities();

      await expectLater(
        communicator.sendCmd(
          exchange,
          data: Uint8List.fromList([0, 0, 0, 7, 0x00]),
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<ChameleonResponseTimeoutException>()),
      );
      await expectLater(
        communicator.hf14a4ReaderSessionReset(7),
        throwsA(isA<ChameleonCommandException>()),
      );
      await expectLater(
        communicator.hf14a4ReaderSessionExchange(8, Uint8List.fromList([0x00])),
        throwsA(isA<ChameleonCommandResponseUncertainException>()),
      );
    },
  );

  test('handles a synchronous response emitted during write', () async {
    final serial = _FakeSerial(synchronousResponses: true);
    final communicator = _communicator(serial);

    final response = await communicator.sendCmd(ChameleonCommand.getAppVersion);

    expect(response, isNotNull);
  });

  test('skipReceive does not leak serializer state', () async {
    final serial = _FakeSerial(respondToCommands: false);
    final communicator = _communicator(serial);
    await communicator.initializeCapabilities();

    await communicator.sendCmd(
      ChameleonCommand.enterBootloader,
      skipReceive: true,
    );

    expect(communicator.commandQueue, isEmpty);
  });

  test('keeps ISO-DEP reader session identity across APDU exchanges', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.hf14a4ReaderSessionStart.value) {
          await serial.emit(
            id,
            status: 0x00,
            data: [
              0x10,
              0x20,
              0x30,
              0x40,
              0x04,
              0x01,
              0x02,
              0x03,
              0x04,
              0x04,
              0x00,
              0x20,
              0x02,
              0x02,
              0x08,
            ],
          );
        } else if (id == ChameleonCommand.hf14a4ReaderSessionExchange.value) {
          await serial.emit(id, status: 0x00, data: [0x90, 0x00]);
        } else {
          await serial.emit(id);
        }
      },
    );
    final communicator = _communicator(serial);

    final session = await communicator.hf14a4ReaderSessionStart();
    final response = await communicator.hf14a4ReaderSessionExchange(
      session.sessionId,
      Uint8List.fromList([0x00, 0xA4, 0x04, 0x00]),
    );
    await communicator.hf14a4ReaderSessionStop(session.sessionId);

    expect(session.sessionId, 0x10203040);
    expect(session.card.uid, [1, 2, 3, 4]);
    expect(response, [0x90, 0x00]);
    expect(
      serial.commandData[ChameleonCommand.hf14a4ReaderSessionExchange.value],
      [0x10, 0x20, 0x30, 0x40, 0x00, 0xA4, 0x04, 0x00],
    );
    expect(serial.commandData[ChameleonCommand.hf14a4ReaderSessionStop.value], [
      0x10,
      0x20,
      0x30,
      0x40,
    ]);
  });

  test(
    'opens Apple Transit ISO-DEP session with command 6014 and no payload',
    () async {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id ==
              ChameleonCommand.hf14a4ReaderSessionStartAppleTransit.value) {
            await serial.emit(
              id,
              status: 0x00,
              data: [
                0x10,
                0x20,
                0x30,
                0x41,
                0x04,
                0x01,
                0x02,
                0x03,
                0x04,
                0x04,
                0x00,
                0x20,
                0x02,
                0x02,
                0x08,
              ],
            );
          }
        },
      );
      final communicator = _communicator(serial);

      final session = await communicator.hf14a4ReaderSessionStartAppleTransit();

      expect(session.sessionId, 0x10203041);
      expect(
        serial.commandData[ChameleonCommand
            .hf14a4ReaderSessionStartAppleTransit
            .value],
        isEmpty,
      );
    },
  );

  test('gates Apple Transit START on advertised command 6014', () async {
    final capabilities =
        ChameleonCommand.values.map((command) => command.value).toSet()
          ..remove(ChameleonCommand.hf14a4ReaderSessionStartAppleTransit.value);
    final serial = _FakeSerial(capabilities: capabilities);
    final communicator = _communicator(serial);

    await expectLater(
      communicator.hf14a4ReaderSessionStartAppleTransit(),
      throwsA(isA<ChameleonUnsupportedCommandException>()),
    );
    expect(serial.commands, [ChameleonCommand.getDeviceCapabilities.value]);
  });

  test('retains command 6014 on Apple Transit START failure', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id ==
            ChameleonCommand.hf14a4ReaderSessionStartAppleTransit.value) {
          await serial.emit(id, status: 0x01, data: [0x01, 0x01]);
        }
      },
    );
    final communicator = _communicator(serial);

    await expectLater(
      communicator.hf14a4ReaderSessionStartAppleTransit(),
      throwsA(
        isA<ChameleonCommandException>().having(
          (error) => error.command,
          'command',
          ChameleonCommand.hf14a4ReaderSessionStartAppleTransit,
        ),
      ),
    );
  });

  test(
    'stops a firmware session after malformed successful START metadata',
    () async {
      var starts = 0;
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == ChameleonCommand.hf14a4ReaderSessionStart.value) {
            starts++;
            await serial.emit(
              id,
              status: 0x00,
              data: starts == 1
                  ? [0x10, 0x20, 0x30, 0x42]
                  : [
                      0x10,
                      0x20,
                      0x30,
                      0x44,
                      0x04,
                      0x01,
                      0x02,
                      0x03,
                      0x04,
                      0x04,
                      0x00,
                      0x20,
                      0x02,
                      0x02,
                      0x08,
                    ],
            );
          } else if (id == ChameleonCommand.hf14a4ReaderSessionStop.value) {
            await serial.emit(id, status: chameleonStatusSuccess);
          }
        },
      );
      final communicator = _communicator(serial);

      await expectLater(
        communicator.hf14a4ReaderSessionStart(),
        throwsA(
          isA<IsoDepReaderSessionStartMetadataException>()
              .having((error) => error.sessionId, 'sessionId', 0x10203042)
              .having(
                (error) => error.cleanupConfirmed,
                'cleanupConfirmed',
                true,
              )
              .having(
                (error) => error.sessionStateUncertain,
                'uncertain',
                false,
              ),
        ),
      );
      expect(
        serial.commandData[ChameleonCommand.hf14a4ReaderSessionStop.value],
        [0x10, 0x20, 0x30, 0x42],
      );
      expect(
        (await communicator.hf14a4ReaderSessionStart()).sessionId,
        0x10203044,
      );
    },
  );

  test(
    'disconnects after malformed START without an extractable session ID',
    () async {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == ChameleonCommand.hf14a4ReaderSessionStart.value) {
            await serial.emit(id, status: 0x00, data: [0x10, 0x20, 0x30]);
          }
        },
      );
      final communicator = _communicator(serial);

      await expectLater(
        communicator.hf14a4ReaderSessionStart(),
        throwsA(
          isA<IsoDepReaderSessionStartMetadataException>()
              .having((error) => error.sessionId, 'sessionId', isNull)
              .having(
                (error) => error.cleanupConfirmed,
                'cleanupConfirmed',
                false,
              )
              .having(
                (error) => error.sessionStateUncertain,
                'uncertain',
                true,
              ),
        ),
      );
      await expectLater(
        communicator.hf14a4ReaderSessionStart(),
        throwsA(isA<ChameleonCommunicatorClosedException>()),
      );
      expect(
        serial.commands.where(
          (id) => id == ChameleonCommand.hf14a4ReaderSessionStart.value,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'disconnects when malformed START session cleanup is not confirmed',
    () async {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == ChameleonCommand.hf14a4ReaderSessionStart.value) {
            await serial.emit(id, status: 0x00, data: [0x10, 0x20, 0x30, 0x43]);
          } else if (id == ChameleonCommand.hf14a4ReaderSessionStop.value) {
            await serial.emit(id, status: 0x01);
          }
        },
      );
      final communicator = _communicator(serial);

      await expectLater(
        communicator.hf14a4ReaderSessionStart(),
        throwsA(
          isA<IsoDepReaderSessionStartMetadataException>()
              .having((error) => error.sessionId, 'sessionId', 0x10203043)
              .having(
                (error) => error.cleanupConfirmed,
                'cleanupConfirmed',
                false,
              )
              .having(
                (error) => error.cleanupError,
                'cleanupError',
                isA<ChameleonCommandException>(),
              ),
        ),
      );
      await expectLater(
        communicator.hf14a4ReaderSessionStart(),
        throwsA(isA<ChameleonCommunicatorClosedException>()),
      );
    },
  );

  test('retains ISO-DEP session failure diagnostics', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.hf14a4ReaderSessionExchange.value) {
          await serial.emit(id, status: 0x01, data: [7, 1, 10]);
        }
      },
    );
    final communicator = _communicator(serial);

    await expectLater(
      communicator.hf14a4ReaderSessionExchange(
        12,
        Uint8List.fromList([0x80, 0xCA, 0x9F, 0x36, 0x00]),
      ),
      throwsA(
        isA<IsoDepReaderSessionExchangeException>()
            .having((error) => error.isoDepError, 'ISO-DEP error', 7)
            .having((error) => error.rfStatus, 'RF status', 1)
            .having((error) => error.wtxCount, 'WTX count', 10)
            .having(
              (error) => error.firmwareSessionClosed,
              'firmware session closed',
              isTrue,
            )
            .having(
              (error) => error.toString(),
              'message',
              contains('RF timeout'),
            ),
      ),
    );
  });

  test(
    'ambiguous exchange statuses still require an ordered session reset',
    () {
      expect(
        const IsoDepReaderSessionExchangeException(0x60).firmwareSessionClosed,
        isFalse,
      );
      expect(
        const IsoDepReaderSessionExchangeException(0x66).firmwareSessionClosed,
        isFalse,
      );
    },
  );

  test('parses complete MF1 reader-key detection records', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.mf1GetDetectionCount.value) {
          await serial.emit(id, data: [0, 0, 0, 2]);
        } else if (id == ChameleonCommand.mf1GetDetectionResult.value) {
          await serial.emit(
            id,
            data: [
              ..._detectionRecord(4, 0, 0x11223344, 1, 2, 3),
              ..._detectionRecord(5, 3, 0x11223344, 4, 5, 6),
            ],
          );
        }
      },
    );
    final communicator = _communicator(serial);

    final count = await communicator.getMf1DetectionCount();
    final records = await communicator.getMf1DetectionRecords(count);

    expect(records, hasLength(2));
    expect(records.first.block, 4);
    expect(records.first.type, 0x60);
    expect(records.last.type, 0x61);
    expect(records.last.isNested, isTrue);
    expect(records.last.uid, 0x11223344);
  });

  test('downloads every paged MF1 reader-key detection record', () async {
    var page = 0;
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.mf1GetDetectionResult.value) {
          final count = page++ == 0 ? 227 : 1;
          await serial.emit(
            id,
            data: [
              for (var index = 0; index < count; index++)
                ..._detectionRecord(
                  index % 64,
                  index & 1,
                  0x11223344,
                  index + 1,
                  index + 2,
                  index + 3,
                ),
            ],
          );
        }
      },
    );

    final records = await _communicator(serial).getMf1DetectionRecords(228);

    expect(records, hasLength(228));
    expect(page, 2);
    expect(serial.commandData[ChameleonCommand.mf1GetDetectionResult.value], [
      0,
      0,
      0,
      227,
    ]);
  });

  test('rejects malformed MF1 reader-key detection pages', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.mf1GetDetectionResult.value) {
          await serial.emit(id, data: List.filled(17, 0));
        }
      },
    );
    final communicator = _communicator(serial);

    await expectLater(
      communicator.getMf1DetectionRecords(1),
      throwsFormatException,
    );
  });

  test('surfaces firmware errors for MF1 detection count', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.mf1GetDetectionCount.value) {
          await serial.emit(id, status: 0x60);
        }
      },
    );
    final communicator = _communicator(serial);

    await expectLater(
      communicator.getMf1DetectionCount(),
      throwsA(isA<ChameleonCommandException>()),
    );
  });

  test(
    'ISO scan wrappers distinguish no-card from firmware failures',
    () async {
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else {
            await serial.emit(id, status: 0x75);
          }
        },
      );
      final communicator = _communicator(serial);

      await expectLater(
        communicator.scan14443aTag(),
        throwsA(isA<ChameleonCommandException>()),
      );
      await expectLater(
        communicator.hf14a4EmvScan(),
        throwsA(isA<ChameleonCommandException>()),
      );
      await expectLater(
        communicator.hf14a4DesfireScan(),
        throwsA(isA<ChameleonCommandException>()),
      );
    },
  );

  test('PM3 raw bridge sends exact flags, timeout, and bit length', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.hf14ARawCommand.value) {
          await serial.emit(id, status: 0, data: [0x04, 0x00]);
        }
      },
    );
    final response = await _communicator(serial).hf14aRaw(
      Pm3Hf14aRawRequest(
        data: Uint8List.fromList([0x26]),
        bitLength: 7,
        responseTimeoutMs: 100,
        activateField: true,
        waitResponse: true,
        appendCrc: false,
        autoSelect: false,
        keepField: true,
        checkResponseCrc: false,
      ),
    );

    expect(serial.commandData[ChameleonCommand.hf14ARawCommand.value], [
      0xc8,
      0,
      100,
      0,
      7,
      0x26,
    ]);
    expect(response.status, 0);
    expect(response.data, [0x04, 0x00]);
  });

  test('PM3 persistent select validates and parses card metadata', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.hf14aScanKeep.value) {
          await serial.emit(
            id,
            status: 0,
            data: [4, 1, 2, 3, 4, 0x04, 0x00, 0x20, 2, 0x75, 0x77],
          );
        }
      },
    );

    final card = await _communicator(serial).scan14443aTagKeep();

    expect(card!.uid, [1, 2, 3, 4]);
    expect(card.atqa, [0, 4]);
    expect(card.sak, 0x20);
    expect(card.ats, [0x75, 0x77]);
  });

  test('PM3 HF config bridge preserves the four firmware enum bytes', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.hf14aGetConfig.value) {
          await serial.emit(id, data: [0, 1, 2, 0]);
        } else if (id == ChameleonCommand.hf14aSetConfig.value) {
          await serial.emit(id);
        }
      },
    );
    final communicator = _communicator(serial);

    final config = await communicator.getHf14aConfig();
    await communicator.setHf14aConfig(config);

    expect(config.uidCl2, 1);
    expect(config.uidCl3, 2);
    expect(serial.commandData[ChameleonCommand.hf14aSetConfig.value], [
      0,
      1,
      2,
      0,
    ]);
  });

  test('PM3 T55xx writer emits the documented 11-byte payload', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.writeT55xxBlock.value) {
          await serial.emit(id, status: 0x40);
        }
      },
    );

    await _communicator(serial).writeT55xxBlock(
      block: 3,
      word: 0x11223344,
      password: 0x20206666,
      page1: true,
    );

    expect(serial.commandData[ChameleonCommand.writeT55xxBlock.value], [
      3,
      0x11,
      0x22,
      0x33,
      0x44,
      1,
      0x20,
      0x20,
      0x66,
      0x66,
      1,
    ]);
  });

  test('PM3 Jablotron writer emits UID and password candidates', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.writeJablotronToT5577.value) {
          await serial.emit(id, status: 0x40);
        }
      },
    );

    await _communicator(serial).writeJablotronToT55XX(
      Uint8List.fromList([1, 2, 3, 4, 5]),
      Uint8List.fromList([0x11, 0x22, 0x33, 0x44]),
      [
        Uint8List.fromList([0, 0, 0, 0]),
        Uint8List.fromList([0x20, 0x20, 0x66, 0x66]),
      ],
    );

    expect(serial.commandData[ChameleonCommand.writeJablotronToT5577.value], [
      1,
      2,
      3,
      4,
      5,
      0x11,
      0x22,
      0x33,
      0x44,
      0,
      0,
      0,
      0,
      0x20,
      0x20,
      0x66,
      0x66,
    ]);
  });

  test('PM3 LF ADC and Jablotron bridges enforce firmware statuses', () async {
    final serial = _FakeSerial(
      onCommand: (serial, id) async {
        if (id == ChameleonCommand.getDeviceCapabilities.value) {
          await serial.emitCapabilities();
        } else if (id == ChameleonCommand.readLfAdc.value) {
          await serial.emit(id, status: 0x40, data: [0x10, 0x20, 0x30]);
        } else if (id == ChameleonCommand.scanJablotronTag.value) {
          await serial.emit(id, status: 0x40, data: [1, 2, 3, 4, 5]);
        }
      },
    );
    final communicator = _communicator(serial);

    expect(await communicator.readLfAdc(), [0x10, 0x20, 0x30]);
    expect(await communicator.readJablotron(), [1, 2, 3, 4, 5]);
  });

  test(
    'PM3 ioProx bridge parses fields and emits big-endian card number',
    () async {
      final response = [
        2,
        17,
        0x12,
        0x34,
        0x00,
        0xf0,
        17,
        2,
        0x12,
        0x34,
        0xaa,
        0xbb,
        0,
        0,
        0,
        0,
      ];
      final serial = _FakeSerial(
        onCommand: (serial, id) async {
          if (id == ChameleonCommand.getDeviceCapabilities.value) {
            await serial.emitCapabilities();
          } else if (id == ChameleonCommand.ioProxDecodeRaw.value ||
              id == ChameleonCommand.ioProxComposeId.value) {
            await serial.emit(id, data: response);
          }
        },
      );
      final communicator = _communicator(serial);

      final decoded = await communicator.decodeIoProxRaw(
        Uint8List.fromList(response.sublist(4, 12)),
      );
      final composed = await communicator.composeIoProxId(
        version: 2,
        facilityCode: 17,
        cardNumber: 0x1234,
      );

      expect(decoded.cardNumber, 0x1234);
      expect(composed.raw, response.sublist(4, 12));
      expect(serial.commandData[ChameleonCommand.ioProxDecodeRaw.value], [
        0x00,
        0xf0,
        17,
        2,
        0x12,
        0x34,
        0xaa,
        0xbb,
      ]);
      expect(serial.commandData[ChameleonCommand.ioProxComposeId.value], [
        2,
        17,
        0x12,
        0x34,
      ]);
    },
  );
}

List<int> _detectionRecord(
  int block,
  int flags,
  int uid,
  int nt,
  int nr,
  int ar,
) {
  List<int> u32(int value) => [
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];
  return [block, flags, ...u32(uid), ...u32(nt), ...u32(nr), ...u32(ar)];
}

ChameleonCommunicator _communicator(
  _FakeSerial serial, {
  Duration writeTimeout = const Duration(seconds: 1),
  Duration snapshotSaveTimeout = activeSlotSnapshotSaveTimeout,
}) => ChameleonCommunicator(
  Logger(level: Level.off),
  port: serial,
  writeTimeout: writeTimeout,
  snapshotSaveTimeout: snapshotSaveTimeout,
);

typedef _CommandHandler = Future<void> Function(_FakeSerial serial, int id);

class _FakeSerial extends AbstractSerial {
  final int capabilityStatus;
  final Uint8List? capabilityPayload;
  final Set<int> capabilities;
  final Set<int> hangingCommands;
  final Set<int> failingCommands;
  final bool respondToCommands;
  final bool synchronousResponses;
  final _CommandHandler? onCommand;
  final List<int> commands = [];
  final Map<int, List<int>> commandData = {};
  final List<(int, List<int>)> commandPayloads = [];
  int _activeWrites = 0;
  int maxConcurrentWrites = 0;
  bool disconnected = false;

  _FakeSerial({
    this.capabilityStatus = chameleonStatusSuccess,
    this.capabilityPayload,
    Set<int>? capabilities,
    this.hangingCommands = const <int>{},
    this.failingCommands = const <int>{},
    this.respondToCommands = true,
    this.synchronousResponses = false,
    this.onCommand,
  }) : capabilities =
           capabilities ??
           ChameleonCommand.values.map((command) => command.value).toSet(),
       super(log: Logger(level: Level.off));

  @override
  Future<void> open() async {
    isOpen = true;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final commandId = (command[2] << 8) | command[3];
    commands.add(commandId);
    final dataLength = (command[6] << 8) | command[7];
    commandData[commandId] = command.sublist(9, 9 + dataLength);
    commandPayloads.add((commandId, command.sublist(9, 9 + dataLength)));
    _activeWrites++;
    if (_activeWrites > maxConcurrentWrites) {
      maxConcurrentWrites = _activeWrites;
    }
    if (hangingCommands.contains(commandId)) {
      return Completer<bool>().future;
    }
    if (failingCommands.contains(commandId)) {
      throw StateError('simulated transport failure');
    }
    if (!synchronousResponses) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (onCommand != null) {
      await onCommand!(this, commandId);
    } else if (commandId == ChameleonCommand.getDeviceCapabilities.value) {
      await emitCapabilities();
    } else if (respondToCommands) {
      await emit(commandId);
    }
    _activeWrites--;
    return true;
  }

  Future<void> emitCapabilities() => emit(
    ChameleonCommand.getDeviceCapabilities.value,
    status: capabilityStatus,
    data: capabilityPayload ?? _capabilityBytes(capabilities),
  );

  Future<void> emit(
    int commandId, {
    int status = chameleonStatusSuccess,
    List<int> data = const [],
  }) async {
    await messageCallback(responseFrame(commandId, status: status, data: data));
  }

  Future<void> emitFrames(List<List<int>> frames) async {
    await messageCallback(frames.expand((frame) => frame).toList());
  }

  List<int> responseFrame(
    int commandId, {
    int status = chameleonStatusSuccess,
    List<int> data = const [],
  }) {
    final frame = <int>[
      0x11,
      _lrc([0x11]),
      commandId >> 8,
      commandId & 0xFF,
      status >> 8,
      status & 0xFF,
      data.length >> 8,
      data.length & 0xFF,
    ];
    frame.add(_lrc(frame.sublist(2, 8)));
    frame.addAll(data);
    frame.add(_lrc(frame));
    return frame;
  }

  Uint8List _capabilityBytes(Set<int> values) => Uint8List.fromList([
    for (final value in values) ...[value >> 8, value & 0xFF],
  ]);

  int _lrc(List<int> data) {
    var sum = 0;
    for (final byte in data) {
      sum = (sum + byte) & 0xFF;
    }
    return (0x100 - sum) & 0xFF;
  }

  @override
  Future<bool> performDisconnect() async {
    disconnected = true;
    isOpen = false;
    return true;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;

  @override
  bool isManualConnectionSupported() => false;
}
