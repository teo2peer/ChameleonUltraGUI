import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/keyboard_script.dart';

const int keyboardProtocolVersion = 1;
const int keyboardUploadChunkBytes = 128;
const int keyboardWireMaximumChunkBytes = 4089;

enum KeyboardOutput {
  usb(0x01),
  ble(0x02),
  both(0x03);

  const KeyboardOutput(this.value);
  final int value;
}

enum KeyboardPayloadState {
  empty,
  uploading,
  ready,
  running,
  complete,
  cancelled,
  error,
  armed,
}

class KeyboardUploadBeginResult {
  final int uploadId;
  final int nextOffset;
  final int maximumChunkLength;

  const KeyboardUploadBeginResult({
    required this.uploadId,
    required this.nextOffset,
    required this.maximumChunkLength,
  });
}

class KeyboardUploadChunkResult {
  final int uploadId;
  final int nextOffset;

  const KeyboardUploadChunkResult({
    required this.uploadId,
    required this.nextOffset,
  });
}

class KeyboardUploadCommitResult {
  final int commitId;
  final int totalLength;
  final int crc32;

  const KeyboardUploadCommitResult({
    required this.commitId,
    required this.totalLength,
    required this.crc32,
  });

  bool matchesProgram(List<int> program) =>
      totalLength == program.length && crc32 == keyboardProgramCrc32(program);
}

class KeyboardRunResult {
  final int runId;

  const KeyboardRunResult(this.runId);
}

class KeyboardStatus {
  final KeyboardPayloadState state;
  final int error;
  final int outputs;
  final int uploadId;
  final int commitId;
  final int runId;
  final int expected;
  final int received;
  final int programCounter;
  final int length;
  final int crc32;

  const KeyboardStatus({
    required this.state,
    required this.error,
    required this.outputs,
    required this.uploadId,
    required this.commitId,
    required this.runId,
    required this.expected,
    required this.received,
    required this.programCounter,
    required this.length,
    required this.crc32,
  });
}

extension ChameleonKeyboard on ChameleonCommunicator {
  Future<KeyboardUploadBeginResult> keyboardUploadBegin(
      int totalLength, int crc32) async {
    _requireRange('totalLength', totalLength, 1, keyboardMaxProgramBytes);
    _requireRange('crc32', crc32, 0, 0xFFFFFFFF);
    final request = Uint8List(7);
    final data = ByteData.sublistView(request);
    data.setUint8(0, keyboardProtocolVersion);
    data.setUint16(1, totalLength, Endian.big);
    data.setUint32(3, crc32, Endian.big);

    final response = _requireKeyboardResponse(
      ChameleonCommand.keyboardUploadBegin,
      await sendCmd(ChameleonCommand.keyboardUploadBegin, data: request),
      9,
    );
    final result = ByteData.sublistView(response.data);
    if (result.getUint8(0) != keyboardProtocolVersion) {
      throw const FormatException(
          'Keyboard upload-begin response has an unsupported version');
    }
    final uploadId = result.getUint32(1, Endian.big);
    final nextOffset = result.getUint16(5, Endian.big);
    final maximumChunkLength = result.getUint16(7, Endian.big);
    if (uploadId == 0 ||
        nextOffset > totalLength ||
        maximumChunkLength != keyboardWireMaximumChunkBytes) {
      throw const FormatException(
          'Keyboard upload-begin response contains invalid metadata');
    }
    return KeyboardUploadBeginResult(
      uploadId: uploadId,
      nextOffset: nextOffset,
      maximumChunkLength: maximumChunkLength,
    );
  }

  Future<KeyboardUploadChunkResult> keyboardUploadChunk(
      int uploadId, int offset, Uint8List chunk) async {
    _requireRange('uploadId', uploadId, 1, 0xFFFFFFFF);
    _requireRange('offset', offset, 0, keyboardMaxProgramBytes - 1);
    if (chunk.isEmpty || chunk.length > keyboardWireMaximumChunkBytes) {
      throw ArgumentError.value(chunk.length, 'chunk',
          'length must be 1..$keyboardWireMaximumChunkBytes');
    }
    if (offset + chunk.length > keyboardMaxProgramBytes) {
      throw ArgumentError('chunk extends beyond the keyboard program limit');
    }

    final request = Uint8List(7 + chunk.length);
    final data = ByteData.sublistView(request);
    data.setUint8(0, keyboardProtocolVersion);
    data.setUint32(1, uploadId, Endian.big);
    data.setUint16(5, offset, Endian.big);
    request.setRange(7, request.length, chunk);
    final response = _requireKeyboardResponse(
      ChameleonCommand.keyboardUploadChunk,
      await sendCmd(ChameleonCommand.keyboardUploadChunk, data: request),
      6,
    );
    final result = ByteData.sublistView(response.data);
    final acknowledgedUploadId = result.getUint32(0, Endian.big);
    final nextOffset = result.getUint16(4, Endian.big);
    if (acknowledgedUploadId != uploadId ||
        nextOffset != offset + chunk.length) {
      throw const FormatException(
          'Keyboard upload-chunk response does not match the request');
    }
    return KeyboardUploadChunkResult(
      uploadId: acknowledgedUploadId,
      nextOffset: nextOffset,
    );
  }

  Future<KeyboardUploadCommitResult> keyboardUploadCommit(int uploadId) async {
    _requireRange('uploadId', uploadId, 1, 0xFFFFFFFF);
    final request = Uint8List(5);
    final data = ByteData.sublistView(request);
    data.setUint8(0, keyboardProtocolVersion);
    data.setUint32(1, uploadId, Endian.big);
    final response = _requireKeyboardResponse(
      ChameleonCommand.keyboardUploadCommit,
      await sendCmd(ChameleonCommand.keyboardUploadCommit, data: request),
      10,
    );
    final result = ByteData.sublistView(response.data);
    final commitId = result.getUint32(0, Endian.big);
    final totalLength = result.getUint16(4, Endian.big);
    if (commitId == 0 ||
        totalLength < 1 ||
        totalLength > keyboardMaxProgramBytes) {
      throw const FormatException(
          'Keyboard upload-commit response contains invalid metadata');
    }
    return KeyboardUploadCommitResult(
      commitId: commitId,
      totalLength: totalLength,
      crc32: result.getUint32(6, Endian.big),
    );
  }

  Future<KeyboardRunResult> keyboardRun(
      int commitId, KeyboardOutput output) async {
    _requireRange('commitId', commitId, 1, 0xFFFFFFFF);
    final request = Uint8List(6);
    final data = ByteData.sublistView(request);
    data.setUint8(0, keyboardProtocolVersion);
    data.setUint32(1, commitId, Endian.big);
    data.setUint8(5, output.value);
    final response = _requireKeyboardResponse(
      ChameleonCommand.keyboardRun,
      await sendCmd(ChameleonCommand.keyboardRun, data: request),
      4,
    );
    final runId = ByteData.sublistView(response.data).getUint32(0, Endian.big);
    if (runId == 0) {
      throw const FormatException(
          'Keyboard run response has an invalid run ID');
    }
    return KeyboardRunResult(runId);
  }

  Future<String> keyboardSetTemporaryBleName([String? name]) async {
    final encoded = name == null ? const <int>[] : utf8.encode(name);
    if (encoded.length > 26 ||
        encoded.any((byte) => byte < 0x20 || byte == 0x7F)) {
      throw ArgumentError.value(name, 'name',
          'must encode to at most 26 UTF-8 bytes without controls');
    }
    final request = Uint8List.fromList([
      keyboardProtocolVersion,
      encoded.length,
      ...encoded,
    ]);
    final response = await sendCmd(
      ChameleonCommand.keyboardSetTemporaryBleName,
      data: request,
    );
    if (response == null) {
      throw StateError('Keyboard BLE-name command returned no response');
    }
    if (response.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(
          ChameleonCommand.keyboardSetTemporaryBleName, response.status);
    }
    if (response.data.length < 2 ||
        response.data[0] != keyboardProtocolVersion ||
        response.data[1] != response.data.length - 2) {
      throw const FormatException(
          'Keyboard BLE-name response contains invalid metadata');
    }
    try {
      return utf8.decode(response.data.sublist(2), allowMalformed: false);
    } on FormatException {
      throw const FormatException(
          'Keyboard BLE-name response contains invalid UTF-8');
    }
  }

  Future<KeyboardRunResult> keyboardArmBle(int commitId) async {
    _requireRange('commitId', commitId, 1, 0xFFFFFFFF);
    final request = Uint8List(5);
    final data = ByteData.sublistView(request);
    data.setUint8(0, keyboardProtocolVersion);
    data.setUint32(1, commitId, Endian.big);
    final response = _requireKeyboardResponse(
      ChameleonCommand.keyboardArmBle,
      await sendCmd(ChameleonCommand.keyboardArmBle, data: request),
      4,
    );
    final runId = ByteData.sublistView(response.data).getUint32(0, Endian.big);
    if (runId == 0) {
      throw const FormatException(
          'Keyboard arm response has an invalid run ID');
    }
    return KeyboardRunResult(runId);
  }

  Future<void> keyboardCancel() async {
    _requireKeyboardResponse(
      ChameleonCommand.keyboardCancel,
      await sendCmd(ChameleonCommand.keyboardCancel),
      0,
    );
  }

  Future<KeyboardStatus> keyboardStatus() async {
    final response = _requireKeyboardResponse(
      ChameleonCommand.keyboardGetStatus,
      await sendCmd(ChameleonCommand.keyboardGetStatus),
      28,
    );
    final data = ByteData.sublistView(response.data);
    if (data.getUint8(0) != keyboardProtocolVersion) {
      throw const FormatException(
          'Keyboard status response has an unsupported version');
    }
    final stateValue = data.getUint8(1);
    final error = data.getUint8(2);
    final outputs = data.getUint8(3);
    final expected = data.getUint16(16, Endian.big);
    final received = data.getUint16(18, Endian.big);
    final programCounter = data.getUint16(20, Endian.big);
    final length = data.getUint16(22, Endian.big);
    if (stateValue >= KeyboardPayloadState.values.length ||
        error > 13 ||
        outputs & ~0x03 != 0 ||
        expected > keyboardMaxProgramBytes ||
        received > expected ||
        length > keyboardMaxProgramBytes ||
        programCounter > length) {
      throw const FormatException(
          'Keyboard status response contains invalid metadata');
    }
    return KeyboardStatus(
      state: KeyboardPayloadState.values[stateValue],
      error: error,
      outputs: outputs,
      uploadId: data.getUint32(4, Endian.big),
      commitId: data.getUint32(8, Endian.big),
      runId: data.getUint32(12, Endian.big),
      expected: expected,
      received: received,
      programCounter: programCounter,
      length: length,
      crc32: data.getUint32(24, Endian.big),
    );
  }

  Future<void> keyboardClear() async {
    _requireKeyboardResponse(
      ChameleonCommand.keyboardClear,
      await sendCmd(ChameleonCommand.keyboardClear),
      0,
    );
  }

  Future<KeyboardUploadCommitResult> keyboardUpload(Uint8List program) async {
    if (program.isEmpty || program.length > keyboardMaxProgramBytes) {
      throw ArgumentError.value(program.length, 'program',
          'length must be 1..$keyboardMaxProgramBytes');
    }
    final crc32 = keyboardProgramCrc32(program);
    final begun = await keyboardUploadBegin(program.length, crc32);
    if (begun.nextOffset != 0) {
      throw const FormatException(
          'Keyboard upload-begin response did not start at offset zero');
    }

    final chunkLength = begun.maximumChunkLength < keyboardUploadChunkBytes
        ? begun.maximumChunkLength
        : keyboardUploadChunkBytes;
    var offset = 0;
    while (offset < program.length) {
      final end = (offset + chunkLength < program.length)
          ? offset + chunkLength
          : program.length;
      final acknowledged = await keyboardUploadChunk(
          begun.uploadId, offset, Uint8List.sublistView(program, offset, end));
      offset = acknowledged.nextOffset;
    }

    final committed = await keyboardUploadCommit(begun.uploadId);
    if (committed.totalLength != program.length || committed.crc32 != crc32) {
      throw const FormatException(
          'Keyboard upload-commit response does not match the program');
    }
    return committed;
  }
}

ChameleonMessage _requireKeyboardResponse(
    ChameleonCommand command, ChameleonMessage? response, int exactDataLength) {
  if (response == null) {
    throw StateError('Keyboard command ${command.name} returned no response');
  }
  if (response.status != chameleonStatusSuccess) {
    throw ChameleonCommandException(command, response.status);
  }
  if (response.data.length != exactDataLength) {
    throw FormatException('Keyboard command ${command.name} returned '
        '${response.data.length} data bytes; expected exactly $exactDataLength');
  }
  return response;
}

void _requireRange(String name, int value, int minimum, int maximum) {
  if (value < minimum || value > maximum) {
    throw ArgumentError.value(value, name, 'must be $minimum..$maximum');
  }
}

int keyboardProgramCrc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xEDB88320 : 0);
    }
  }
  return (~crc) & 0xFFFFFFFF;
}
