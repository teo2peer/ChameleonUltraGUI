import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon_frame_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChameleonFrameDecoder', () {
    test('decodes empty and maximum payload frames', () {
      final decoder = ChameleonFrameDecoder();
      final empty = buildChameleonFrame(command: 0x1234, status: 0x68);
      final maximum = buildChameleonFrame(
        command: 0xabcd,
        status: 0x6075,
        data: Uint8List.fromList(List<int>.generate(4096, (index) => index)),
      );

      final result = decoder.add([...empty, ...maximum]);

      expect(result.errors, isEmpty);
      expect(result.frames, hasLength(2));
      expect(result.frames[0].command, 0x1234);
      expect(result.frames[0].status, 0x68);
      expect(result.frames[0].data, isEmpty);
      expect(result.frames[1].command, 0xabcd);
      expect(result.frames[1].status, 0x6075);
      expect(result.frames[1].data, hasLength(4096));
      expect(decoder.retainedByteCount, 0);
    });

    test('decodes a frame split at every byte boundary', () {
      final frame = buildChameleonFrame(
        command: 0x4321,
        status: 0x68,
        data: Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      for (var split = 0; split <= frame.length; split++) {
        final decoder = ChameleonFrameDecoder();
        final first = decoder.add(frame.sublist(0, split));
        final second = decoder.add(frame.sublist(split));
        expect(first.errors, isEmpty, reason: 'split $split');
        expect(second.errors, isEmpty, reason: 'split $split');
        expect([...first.frames, ...second.frames], hasLength(1),
            reason: 'split $split');
      }
    });

    test('decodes coalesced frames', () {
      final decoder = ChameleonFrameDecoder();
      final first = buildChameleonFrame(command: 1, status: 2);
      final second = buildChameleonFrame(
        command: 3,
        status: 4,
        data: Uint8List.fromList([5]),
      );

      final result = decoder.add([...first, ...second]);

      expect(result.errors, isEmpty);
      expect(result.frames.map((frame) => frame.command), [1, 3]);
    });

    test('discards garbage prefix and resumes at SOF', () {
      final decoder = ChameleonFrameDecoder();
      final valid = buildChameleonFrame(command: 0x1000, status: 0x68);

      final result = decoder.add([0x01, 0x02, 0x03, ...valid]);

      expect(result.errors.map((error) => error.kind),
          contains(ChameleonFrameErrorKind.discardedNoise));
      expect(result.frames.single.command, 0x1000);
    });

    for (final corruption in <String, void Function(Uint8List)>{
      'SOF LRC': (frame) => frame[1] ^= 1,
      'header LRC': (frame) => frame[8] ^= 1,
      'final LRC': (frame) => frame[frame.length - 1] ^= 1,
    }.entries) {
      test('recovers after invalid ${corruption.key}', () {
        final decoder = ChameleonFrameDecoder();
        final corrupt = buildChameleonFrame(
          command: 0x1111,
          status: 0x68,
          data: Uint8List.fromList([0x11, 0x22]),
        );
        corruption.value(corrupt);
        final valid = buildChameleonFrame(command: 0x2222, status: 0x68);

        final result = decoder.add([...corrupt, ...valid]);

        expect(result.errors, isNotEmpty);
        expect(result.frames.last.command, 0x2222);
      });
    }

    for (final advertisedLength in [0x1001, 0xffff]) {
      test(
          'rejects unsigned oversized length 0x${advertisedLength.toRadixString(16)}',
          () {
        final decoder = ChameleonFrameDecoder();
        final header =
            buildChameleonFrame(command: 0x1111, status: 0x68).sublist(0, 9);
        header[6] = advertisedLength >> 8;
        header[7] = advertisedLength & 0xff;
        header[8] = chameleonLrc(header.sublist(2, 8));
        final valid = buildChameleonFrame(command: 0x2222, status: 0x68);

        final result = decoder.add([...header, ...valid]);

        expect(
          result.errors
              .where((error) =>
                  error.kind == ChameleonFrameErrorKind.oversizedPayload)
              .single
              .advertisedLength,
          advertisedLength,
        );
        expect(result.frames.single.command, 0x2222);
      });
    }

    test('never retains more than one maximum frame', () {
      final decoder = ChameleonFrameDecoder();

      for (var iteration = 0; iteration < 100; iteration++) {
        decoder.add(List<int>.filled(1000, 0x55));
        expect(decoder.retainedByteCount,
            lessThanOrEqualTo(chameleonMaxFrameLength));
      }
    });

    test('does not resynchronize on SOF inside a valid payload', () {
      final decoder = ChameleonFrameDecoder();
      final frame = buildChameleonFrame(
        command: 7,
        status: 8,
        data: Uint8List.fromList([0x11, 0xee, 0x11]),
      );

      final result = decoder.add(frame);

      expect(result.errors, isEmpty);
      expect(result.frames.single.data, [0x11, 0xee, 0x11]);
    });

    test('reset discards an incomplete frame', () {
      final decoder = ChameleonFrameDecoder();
      final frame = buildChameleonFrame(command: 1, status: 2);
      decoder.add(frame.sublist(0, 5));
      expect(decoder.retainedByteCount, 5);

      decoder.reset();

      expect(decoder.retainedByteCount, 0);
      expect(decoder.add(frame).frames.single.command, 1);
    });
  });

  group('buildChameleonFrame', () {
    test('encodes unsigned fields and a 4096-byte payload', () {
      final frame = buildChameleonFrame(
        command: 0xffff,
        status: 0x8000,
        data: Uint8List(4096),
      );

      expect(frame, hasLength(chameleonMaxFrameLength));
      expect(frame.sublist(2, 8), [0xff, 0xff, 0x80, 0x00, 0x10, 0x00]);
    });

    test('rejects payloads larger than 4096 bytes', () {
      expect(
        () => buildChameleonFrame(
          command: 1,
          status: 0,
          data: Uint8List(4097),
        ),
        throwsRangeError,
      );
    });
  });
}
