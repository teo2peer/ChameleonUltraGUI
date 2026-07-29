import 'dart:typed_data';

import 'package:chameleonultragui/helpers/emv_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EMV trace request', () {
    test('encodes every v1 START field in network byte order', () {
      final request = EmvTraceRequest(
        maximumProcessing: true,
        includeRf: true,
        includeTiming: true,
        scanRecordGrid: true,
        readTransactionLogs: true,
        usePdolFallback: true,
        maxAids: 16,
        maxRecords: 64,
        maxApdus: 0x0123,
        budgetMs: 0x00001234,
        amount: _bytes('000000001234'),
        country: _bytes('0250'),
        currency: _bytes('0978'),
        date: _bytes('260710'),
        transactionType: 0x01,
        cryptogramType: 0x80,
      );

      expect(
        _hex(request.encode()),
        '013f1040012300001234000000001234025009782607100180',
      );
      expect(_hex(encodeEmvTraceSessionRequest(0x01020304)), '0101020304');
      expect(
        _hex(encodeEmvTraceGetRequest(0x01020304, 5, 4096)),
        '0101020304000000051000',
      );
    });

    test('encodes the Express Transit ECP2 option', () {
      final request = EmvTraceRequest.readOnly(expressTransit: true);
      expect(request.encode().length, 25);
      expect(request.encode()[1] & 0x40, 0x40);
    });

    test('encodes bounded and custom terminal profiles', () {
      final sweep = EmvTraceRequest.readOnly(
        expressTransit: true,
        terminalProfile: EmvTerminalProfile.compatibilitySweep,
      ).encode();
      expect(sweep.length, 30);
      expect(_hex(sweep.sublist(0, 2)), '01e6');
      expect(_hex(sweep.sublist(25)), 'ff00000000');

      final custom = EmvTraceRequest(
        terminalProfile: EmvTerminalProfile.custom,
        customTtq: const [0x12, 0x34, 0x56, 0x78],
        amount: Uint8List(6),
        country: Uint8List(2),
        currency: Uint8List(2),
        date: Uint8List(3),
      ).encode();
      expect(_hex(custom.sublist(25)), 'fe12345678');

      final adaptive = EmvTraceRequest(
        terminalProfile: EmvTerminalProfile.compatibilitySweep,
        pollingProfile: EmvPollingProfile.patient,
        directAidFallback: true,
        adaptiveProfiles: true,
        reacquireBetweenProfiles: true,
        amount: Uint8List(6),
        country: Uint8List(2),
        currency: Uint8List(2),
        date: Uint8List(3),
      ).encode();
      expect(adaptive.length, 35);
      expect(_hex(adaptive.sublist(25)), 'ff000000000307000000');
    });
  });

  group('EMV trace strict parsing', () {
    test('parses typed records and a complete page', () {
      final records = [
        _record(1, 0, 0, _bytes('0000100002aabb')),
        _record(2, 1, 0, _bytes('90000005000400a404000070009000')),
        _record(3, 2, 1, _bytes('05a00000000301')),
        _record(4, 0xff, 2, _bytes('000000030000000300000001')),
      ];
      final page = EmvTracePage.parse(_page(7, 0, records, flags: 0x02));

      expect(page.nextRecord, 4);
      expect(page.records.map((record) => record.type), [
        EmvTraceRecordType.rf,
        EmvTraceRecordType.apdu,
        EmvTraceRecordType.application,
        EmvTraceRecordType.summary,
      ]);
      final apdu = page.records[1].payload as EmvTraceApduPayload;
      expect(_hex(apdu.command), '00a4040000');
      expect(apdu.statusWord, 0x9000);
      expect(
          (page.records[2].payload as EmvTraceApplicationPayload).priority, 1);
    });

    test('parses META anti-collision and counters exactly', () {
      final record = _record(4, 0xff, 0, _bytes('000000000000000000000001'));
      final meta = EmvTraceMeta.parse(_meta(9, record));

      expect(meta.scanId, 9);
      expect(meta.storedRecords, 1);
      expect(_hex(meta.uid), '01020304');
      expect(_hex(meta.atqa), '4400');
      expect(meta.sak, 0x20);
      expect(_hex(meta.ats), '067577');
      expect(meta.isComplete, isTrue);
      expect(meta.isTruncated, isFalse);
    });

    test('rejects malformed record and page lengths', () {
      final malformedApdu = _record(
        2,
        1,
        0,
        _bytes('90000006000400a404000070009000'),
      );
      expect(() => EmvTraceRecord.parse(malformedApdu), throwsFormatException);

      final valid = _record(4, 0xff, 0, _bytes('000000000000000000000001'));
      final malformedPage = _page(3, 0, [valid], flags: 0x02);
      ByteData.sublistView(malformedPage)
          .setUint16(16, valid.length - 1, Endian.big);
      expect(() => EmvTracePage.parse(malformedPage), throwsFormatException);

      final malformedMeta = _meta(3, valid)..[42] = 10;
      expect(() => EmvTraceMeta.parse(malformedMeta), throwsFormatException);
    });
  });

  group('EMV trace assembly', () {
    test('assembles multiple pages and verifies cursor, count, and CRC', () {
      final first = _record(3, 2, 0, _bytes('05a00000000301'));
      final second = _record(
        2,
        4,
        1,
        _bytes('90000005000480a800000077009000'),
      );
      final stream = Uint8List.fromList([...first, ...second]);
      final meta = EmvTraceMeta.parse(_meta(11, stream, recordCount: 2));
      final pages = [
        EmvTracePage.parse(_page(11, 0, [first], flags: 0x01)),
        EmvTracePage.parse(_page(11, 1, [second], flags: 0x02)),
      ];

      final capture = EmvTraceCapture.assemble(meta, pages);

      expect(capture.records.length, 2);
      expect(capture.recordBytes, stream);
      expect(capture.toJson()['recordStreamHex'], _hex(stream));
    });

    test('rejects CRC corruption after otherwise valid paging', () {
      final record = _record(4, 0xff, 0, _bytes('000000000000000000000001'));
      final metaBytes = _meta(12, record);
      ByteData.sublistView(metaBytes).setUint32(32, 0x12345678, Endian.big);
      final meta = EmvTraceMeta.parse(metaBytes);
      final page = EmvTracePage.parse(_page(12, 0, [record], flags: 0x02));

      expect(
        () => EmvTraceCapture.assemble(meta, [page]),
        throwsA(isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('CRC-32'),
        )),
      );
    });

    test('rejects a page from another session or cursor', () {
      final record = _record(4, 0xff, 0, _bytes('000000000000000000000001'));
      final meta = EmvTraceMeta.parse(_meta(12, record));
      final wrongSession =
          EmvTracePage.parse(_page(13, 0, [record], flags: 0x02));

      expect(
        () => EmvTraceCapture.assemble(meta, [wrongSession]),
        throwsA(isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('session/cursor'),
        )),
      );
    });
  });
}

Uint8List _record(int type, int stage, int sequence, Uint8List payload) {
  final output = Uint8List(18 + payload.length);
  final data = ByteData.sublistView(output);
  data.setUint16(0, 16 + payload.length, Endian.big);
  output[2] = 1;
  output[3] = type;
  data.setUint32(4, sequence, Endian.big);
  output[8] = stage;
  output[9] = type == 3 ? 1 : 0;
  data.setUint16(12, 0, Endian.big);
  data.setUint32(14, sequence * 10, Endian.big);
  output.setRange(18, output.length, payload);
  return output;
}

Uint8List _page(
  int scanId,
  int start,
  List<Uint8List> records, {
  required int flags,
}) {
  final stream =
      Uint8List.fromList(records.expand((record) => record).toList());
  final output = Uint8List(18 + stream.length);
  final data = ByteData.sublistView(output);
  output[0] = 1;
  output[1] = flags;
  data.setUint32(2, scanId, Endian.big);
  data.setUint32(6, start, Endian.big);
  data.setUint32(10, start + records.length, Endian.big);
  data.setUint16(14, records.length, Endian.big);
  data.setUint16(16, stream.length, Endian.big);
  output.setRange(18, output.length, stream);
  return output;
}

Uint8List _meta(int scanId, Uint8List stream, {int recordCount = 1}) {
  final output = Uint8List(50);
  final data = ByteData.sublistView(output);
  output[0] = 1;
  output[1] = 2;
  data.setUint16(2, 0, Endian.big);
  data.setUint32(4, emvTraceFlagComplete, Endian.big);
  data.setUint32(8, scanId, Endian.big);
  data.setUint32(12, recordCount, Endian.big);
  data.setUint32(16, recordCount, Endian.big);
  data.setUint32(20, stream.length, Endian.big);
  data.setUint32(24, stream.length, Endian.big);
  data.setUint32(28, 0xffffffff, Endian.big);
  data.setUint32(32, emvTraceCrc32(stream), Endian.big);
  data.setUint16(36, 1, Endian.big);
  data.setUint32(38, 123, Endian.big);
  output[42] = 4;
  output.setRange(43, 47, [1, 2, 3, 4]);
  output.setRange(47, 49, [0x44, 0x00]);
  output[49] = 0x20;
  // Expand for atsLen + ATS after the fixed fields above.
  return Uint8List.fromList([...output, 3, 0x06, 0x75, 0x77]);
}

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ]);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
