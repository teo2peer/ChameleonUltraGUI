import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/chameleon_keyboard.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  test('upload uses versioned big-endian messages and chunks at 128 bytes',
      () async {
    final communicator = _FakeKeyboardCommunicator();
    final program = Uint8List.fromList(List.generate(300, (index) => index));

    final committed = await communicator.keyboardUpload(program);

    expect(committed.commitId, 0x55667788);
    expect(committed.totalLength, 300);
    expect(committed.matchesProgram(program), isTrue);
    expect(committed.matchesProgram(Uint8List.fromList([...program]..[0] ^= 1)),
        isFalse);
    expect(communicator.commands, [
      ChameleonCommand.keyboardUploadBegin,
      ChameleonCommand.keyboardUploadChunk,
      ChameleonCommand.keyboardUploadChunk,
      ChameleonCommand.keyboardUploadChunk,
      ChameleonCommand.keyboardUploadCommit,
    ]);
    expect(communicator.payloads[0], hasLength(7));
    final begin = ByteData.sublistView(communicator.payloads[0]);
    expect(begin.getUint8(0), keyboardProtocolVersion);
    expect(begin.getUint16(1, Endian.big), 300);
    expect(begin.getUint32(3, Endian.big), keyboardProgramCrc32(program));
    expect(communicator.payloads.sublist(1, 4).map((data) => data.length),
        [135, 135, 51]);
    expect(
        communicator.payloads.sublist(1, 4).map((payload) =>
            ByteData.sublistView(payload).getUint16(5, Endian.big)),
        [0, 128, 256]);
  });

  test('parses the fixed status response', () async {
    final communicator = _FakeKeyboardCommunicator();

    final status = await communicator.keyboardStatus();

    expect(status.state, KeyboardPayloadState.ready);
    expect(status.commitId, 0x55667788);
    expect(status.length, 300);
    expect(status.crc32, 0x12345678);
  });

  test('run encodes output and validates the exact response length', () async {
    final communicator = _FakeKeyboardCommunicator();
    final result =
        await communicator.keyboardRun(0x55667788, KeyboardOutput.both);

    expect(result.runId, 0x11223344);
    expect(communicator.payloads.single, [1, 0x55, 0x66, 0x77, 0x88, 3]);

    communicator.overrideResponse = ChameleonMessage(
      command: ChameleonCommand.keyboardRun.value,
      status: chameleonStatusSuccess,
      data: Uint8List(0),
    );
    await expectLater(
      communicator.keyboardRun(1, KeyboardOutput.ble),
      throwsFormatException,
    );
  });

  test('temporary BLE name and armed run use strict versioned messages',
      () async {
    final communicator = _FakeKeyboardCommunicator();

    expect(await communicator.keyboardSetTemporaryBleName('Lab KB'), 'Lab KB');
    expect(communicator.payloads.single, [1, 6, 76, 97, 98, 32, 75, 66]);

    communicator.commands.clear();
    communicator.payloads.clear();
    final armed = await communicator.keyboardArmBle(0x55667788);
    expect(armed.runId, 0xAABBCCDD);
    expect(communicator.payloads.single, [1, 0x55, 0x66, 0x77, 0x88]);

    await expectLater(
      communicator.keyboardSetTemporaryBleName('é' * 14),
      throwsArgumentError,
    );
    await expectLater(
      communicator.keyboardSetTemporaryBleName('bad\nname'),
      throwsArgumentError,
    );
  });

  test('parses armed status without extending the fixed response', () async {
    final communicator = _FakeKeyboardCommunicator()
      ..overrideResponse = _response(
        ChameleonCommand.keyboardGetStatus,
        _statusBytes(KeyboardPayloadState.armed),
      );

    final status = await communicator.keyboardStatus();

    expect(status.state, KeyboardPayloadState.armed);
    expect(status.outputs, KeyboardOutput.ble.value);
  });

  test('throws typed command errors before parsing failed responses', () async {
    final communicator = _FakeKeyboardCommunicator()
      ..overrideResponse = ChameleonMessage(
        command: ChameleonCommand.keyboardClear.value,
        status: 0x60,
        data: Uint8List(0),
      );

    await expectLater(communicator.keyboardClear(),
        throwsA(isA<ChameleonCommandException>()));
  });

  test('rejects inconsistent status metadata', () async {
    final data = _statusBytes()..[2] = 14;
    final communicator = _FakeKeyboardCommunicator()
      ..overrideResponse = ChameleonMessage(
        command: ChameleonCommand.keyboardGetStatus.value,
        status: chameleonStatusSuccess,
        data: data,
      );

    await expectLater(communicator.keyboardStatus(), throwsFormatException);
  });
}

class _FakeKeyboardCommunicator extends ChameleonCommunicator {
  final List<ChameleonCommand> commands = [];
  final List<Uint8List> payloads = [];
  ChameleonMessage? overrideResponse;
  int crc32 = 0;

  _FakeKeyboardCommunicator() : super(Logger(level: Level.off));

  @override
  Future<ChameleonMessage?> sendCmd(ChameleonCommand cmd,
      {Uint8List? data,
      Duration timeout = const Duration(seconds: 5),
      bool skipReceive = false,
      bool firstRun = false}) async {
    commands.add(cmd);
    payloads.add(Uint8List.fromList(data ?? const []));
    if (overrideResponse != null) return overrideResponse;

    switch (cmd) {
      case ChameleonCommand.keyboardUploadBegin:
        crc32 = ByteData.sublistView(data!).getUint32(3, Endian.big);
        return _response(cmd, _beginBytes());
      case ChameleonCommand.keyboardUploadChunk:
        final request = ByteData.sublistView(data!);
        return _response(
            cmd,
            _chunkBytes(request.getUint32(1, Endian.big),
                request.getUint16(5, Endian.big) + data.length - 7));
      case ChameleonCommand.keyboardUploadCommit:
        return _response(cmd, _commitBytes(crc32));
      case ChameleonCommand.keyboardGetStatus:
        return _response(cmd, _statusBytes());
      case ChameleonCommand.keyboardRun:
        return _response(cmd, _u32(0x11223344));
      case ChameleonCommand.keyboardSetTemporaryBleName:
        return _response(cmd, Uint8List.fromList(data!));
      case ChameleonCommand.keyboardArmBle:
        return _response(cmd, _u32(0xAABBCCDD));
      case ChameleonCommand.keyboardCancel:
      case ChameleonCommand.keyboardClear:
        return _response(cmd, Uint8List(0));
      default:
        throw StateError('Unexpected command $cmd');
    }
  }
}

ChameleonMessage _response(ChameleonCommand command, Uint8List data) =>
    ChameleonMessage(
      command: command.value,
      status: chameleonStatusSuccess,
      data: data,
    );

Uint8List _beginBytes() {
  final bytes = Uint8List(9);
  final data = ByteData.sublistView(bytes);
  data.setUint8(0, keyboardProtocolVersion);
  data.setUint32(1, 0x10203040, Endian.big);
  data.setUint16(5, 0, Endian.big);
  data.setUint16(7, 4089, Endian.big);
  return bytes;
}

Uint8List _chunkBytes(int uploadId, int nextOffset) {
  final bytes = Uint8List(6);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, uploadId, Endian.big);
  data.setUint16(4, nextOffset, Endian.big);
  return bytes;
}

Uint8List _commitBytes(int crc32) {
  final bytes = Uint8List(10);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x55667788, Endian.big);
  data.setUint16(4, 300, Endian.big);
  data.setUint32(6, crc32, Endian.big);
  return bytes;
}

Uint8List _statusBytes(
    [KeyboardPayloadState state = KeyboardPayloadState.ready]) {
  final bytes = Uint8List(28);
  final data = ByteData.sublistView(bytes);
  data.setUint8(0, keyboardProtocolVersion);
  data.setUint8(1, state.index);
  data.setUint8(2, 0);
  data.setUint8(
      3,
      state == KeyboardPayloadState.armed
          ? KeyboardOutput.ble.value
          : KeyboardOutput.usb.value);
  data.setUint32(4, 0x10203040, Endian.big);
  data.setUint32(8, 0x55667788, Endian.big);
  data.setUint32(12, 0, Endian.big);
  data.setUint16(16, 300, Endian.big);
  data.setUint16(18, 300, Endian.big);
  data.setUint16(20, 0, Endian.big);
  data.setUint16(22, 300, Endian.big);
  data.setUint32(24, 0x12345678, Endian.big);
  return bytes;
}

Uint8List _u32(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value, Endian.big);
  return bytes;
}
