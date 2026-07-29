import 'dart:typed_data';

const int chameleonFrameSof = 0x11;
const int chameleonMaxPayloadLength = 4096;
const int chameleonMaxFrameLength = chameleonMaxPayloadLength + 10;

enum ChameleonFrameErrorKind {
  discardedNoise,
  invalidSofLrc,
  invalidHeaderLrc,
  oversizedPayload,
  invalidFrameLrc,
}

class ChameleonFrameDecodeError {
  const ChameleonFrameDecodeError(
    this.kind, {
    required this.discardedBytes,
    this.advertisedLength,
  });

  final ChameleonFrameErrorKind kind;
  final int discardedBytes;
  final int? advertisedLength;

  @override
  String toString() {
    final length = advertisedLength == null
        ? ''
        : ', advertised payload: $advertisedLength bytes';
    return '${kind.name} ($discardedBytes bytes discarded$length)';
  }
}

class ChameleonDecodedFrame {
  const ChameleonDecodedFrame({
    required this.command,
    required this.status,
    required this.data,
  });

  final int command;
  final int status;
  final Uint8List data;
}

class ChameleonFrameDecodeResult {
  const ChameleonFrameDecodeResult({
    required this.frames,
    required this.errors,
  });

  final List<ChameleonDecodedFrame> frames;
  final List<ChameleonFrameDecodeError> errors;
}

int chameleonLrc(Iterable<int> bytes) {
  var sum = 0;
  for (final byte in bytes) {
    sum = (sum + byte) & 0xff;
  }
  return (0x100 - sum) & 0xff;
}

Uint8List buildChameleonFrame({
  required int command,
  required int status,
  Uint8List? data,
}) {
  RangeError.checkValueInInterval(command, 0, 0xffff, 'command');
  RangeError.checkValueInInterval(status, 0, 0xffff, 'status');
  final payload = data ?? Uint8List(0);
  if (payload.length > chameleonMaxPayloadLength) {
    throw RangeError.range(
      payload.length,
      0,
      chameleonMaxPayloadLength,
      'data.length',
    );
  }

  final frame = Uint8List(payload.length + 10);
  final bytes = frame.buffer.asByteData();
  frame[0] = chameleonFrameSof;
  frame[1] = chameleonLrc(frame.sublist(0, 1));
  bytes.setUint16(2, command, Endian.big);
  bytes.setUint16(4, status, Endian.big);
  bytes.setUint16(6, payload.length, Endian.big);
  frame[8] = chameleonLrc(frame.sublist(2, 8));
  frame.setRange(9, 9 + payload.length, payload);
  frame[frame.length - 1] = chameleonLrc(frame.sublist(0, frame.length - 1));
  return frame;
}

class ChameleonFrameDecoder {
  final List<int> _buffer = <int>[];

  int get retainedByteCount => _buffer.length;

  void reset() => _buffer.clear();

  ChameleonFrameDecodeResult add(Iterable<int> bytes) {
    _buffer.addAll(bytes.map((byte) => byte & 0xff));
    final frames = <ChameleonDecodedFrame>[];
    final errors = <ChameleonFrameDecodeError>[];

    while (_buffer.isNotEmpty) {
      final sofIndex = _buffer.indexOf(chameleonFrameSof);
      if (sofIndex < 0) {
        errors.add(ChameleonFrameDecodeError(
          ChameleonFrameErrorKind.discardedNoise,
          discardedBytes: _buffer.length,
        ));
        _buffer.clear();
        break;
      }
      if (sofIndex > 0) {
        errors.add(ChameleonFrameDecodeError(
          ChameleonFrameErrorKind.discardedNoise,
          discardedBytes: sofIndex,
        ));
        _buffer.removeRange(0, sofIndex);
      }

      if (_buffer.length < 2) break;
      if (_buffer[1] != chameleonLrc(_buffer.sublist(0, 1))) {
        errors.add(const ChameleonFrameDecodeError(
          ChameleonFrameErrorKind.invalidSofLrc,
          discardedBytes: 1,
        ));
        _buffer.removeAt(0);
        continue;
      }

      if (_buffer.length < 9) break;
      if (_buffer[8] != chameleonLrc(_buffer.sublist(2, 8))) {
        errors.add(const ChameleonFrameDecodeError(
          ChameleonFrameErrorKind.invalidHeaderLrc,
          discardedBytes: 1,
        ));
        _buffer.removeAt(0);
        continue;
      }

      final command = (_buffer[2] << 8) | _buffer[3];
      final status = (_buffer[4] << 8) | _buffer[5];
      final payloadLength = (_buffer[6] << 8) | _buffer[7];
      if (payloadLength > chameleonMaxPayloadLength) {
        errors.add(ChameleonFrameDecodeError(
          ChameleonFrameErrorKind.oversizedPayload,
          discardedBytes: 1,
          advertisedLength: payloadLength,
        ));
        _buffer.removeAt(0);
        continue;
      }

      final frameLength = payloadLength + 10;
      if (_buffer.length < frameLength) break;
      if (_buffer[frameLength - 1] !=
          chameleonLrc(_buffer.sublist(0, frameLength - 1))) {
        errors.add(const ChameleonFrameDecodeError(
          ChameleonFrameErrorKind.invalidFrameLrc,
          discardedBytes: 1,
        ));
        _buffer.removeAt(0);
        continue;
      }

      frames.add(ChameleonDecodedFrame(
        command: command,
        status: status,
        data: Uint8List.fromList(_buffer.sublist(9, 9 + payloadLength)),
      ));
      _buffer.removeRange(0, frameLength);
    }

    assert(_buffer.length <= chameleonMaxFrameLength);
    return ChameleonFrameDecodeResult(frames: frames, errors: errors);
  }
}
