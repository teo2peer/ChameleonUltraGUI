import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/emv_trace.dart';
import 'package:chameleonultragui/helpers/transit_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('transit amount', () {
    test('encodes GBP amount as EMV n12 BCD', () {
      expect(_hex(transitAmountBcd('0.10')), '000000000010');
      expect(_hex(transitAmountBcd('12,34')), '000000001234');
      expect(() => transitAmountBcd('invalid'), throwsFormatException);
    });
  });

  group('transit assessment', () {
    test('replays and CRC-validates an exported retained trace', () {
      final records = [
        _apduRecord(
          sequence: 0,
          stage: 1,
          application: 0,
          command: _bytes('00A404000E325041592E5359532E444446303100'),
          response: _bytes('9000'),
        ),
        _applicationRecord(1, _bytes('A0000000031010')),
      ];
      final stream = Uint8List.fromList(
          records.expand((record) => record.rawBytes).toList());
      final report = jsonEncode({
        'system': 'chameleon-transit-gate-lab',
        'assessment': {'transactionRequested': false},
        'trace': {
          'protocol': 'chameleon-emv-trace',
          'recordStreamHex': _hex(stream),
          'meta': {
            'uidHex': '01020304',
            'crc32': emvTraceCrc32(stream),
          },
          'records': [
            for (final record in records)
              {'rawRecordHex': _hex(record.rawBytes)},
          ],
        },
      });

      final replay = replayTransitReport(report);
      expect(replay.recordCount, 2);
      expect(replay.assessment.walletResponded, isTrue);
      expect(replay.assessment.applications.single.scheme, 'Visa');

      final streamHex = _hex(stream);
      final corrupted = report.replaceFirst(
        '"recordStreamHex":"$streamHex"',
        '"recordStreamHex":"${streamHex.substring(0, streamHex.length - 2)}00"',
      );
      expect(() => replayTransitReport(corrupted), throwsFormatException);
    });

    test('identifies schemes and accepts direct-AID discovery', () {
      expect(paymentSchemeForAid('A0000000031010'), 'Visa');
      expect(paymentSchemeForAid('A0000000041010'), 'Mastercard');
      expect(paymentSchemeForAid('A0000000043060'), 'Maestro');
      expect(paymentSchemeForAid('A00000002501'), 'American Express');
      expect(paymentSchemeForAid('A0000001523010'), 'Discover');
      expect(paymentSchemeForAid('A0000000651010'), 'JCB');
      expect(paymentSchemeForAid('A000000333010101'), 'UnionPay');
      expect(paymentSchemeForAid('A0000002771010'), 'Interac');
      expect(transitProfileOrder('Visa', adaptive: true).first,
          EmvTerminalProfile.appleTransit);
      expect(transitProfileOrder('Mastercard', adaptive: true).first,
          EmvTerminalProfile.broadMobile);
      expect(transitProfileOrder('JCB', adaptive: true).first,
          EmvTerminalProfile.qvsdcOnline);

      final assessment = assessTransitRecords(
        targetDetected: true,
        records: [_applicationRecord(1, _bytes('A0000000031010'))],
        transactionRequested: false,
      );
      expect(assessment.ppseSucceeded, isFalse);
      expect(assessment.walletResponded, isTrue);
      expect(assessment.outcome, TransitGateOutcome.discoveryReady);
      expect(assessment.applications.single.scheme, 'Visa');
    });

    test('distinguishes no target from locked-wallet discovery', () {
      final missing = assessTransitRecords(
        targetDetected: false,
        records: const [],
        transactionRequested: false,
      );
      expect(missing.outcome, TransitGateOutcome.noTarget);

      final discovery = assessTransitRecords(
        targetDetected: true,
        records: [
          _apduRecord(
            sequence: 0,
            stage: 1,
            application: 0,
            command: _bytes('00A404000E325041592E5359532E444446303100'),
            response: _bytes('9000'),
          ),
          _applicationRecord(1, _bytes('A0000000031010')),
        ],
        transactionRequested: false,
      );
      expect(discovery.outcome, TransitGateOutcome.discoveryReady);
      expect(discovery.walletResponded, isTrue);
      expect(discovery.applications.single.aid, 'A0000000031010');
    });

    test('reports GPO cryptogram evidence without claiming approval', () {
      final assessment = assessTransitRecords(
        targetDetected: true,
        records: [
          _apduRecord(
            sequence: 0,
            stage: 1,
            application: 0,
            command: _bytes('00A404000E325041592E5359532E444446303100'),
            response: _bytes('9000'),
          ),
          _applicationRecord(1, _bytes('A0000000041010')),
          _apduRecord(
            sequence: 2,
            stage: 4,
            application: 1,
            command: _bytes('80A8000002830000'),
            response:
                _bytes('77159F260811223344556677889F2701409F34031F03029000'),
          ),
        ],
        transactionRequested: true,
      );

      expect(assessment.outcome, TransitGateOutcome.transactionEvidence);
      expect(assessment.gpoSucceeded, isTrue);
      expect(assessment.hasTransactionEvidence, isTrue);
      expect(assessment.applications.single.cryptogramType,
          'TC (offline cryptogram)');
      expect(assessment.applications.single.cvmResults, '1F0302');
      expect(assessment.explanation, contains('not a payment approval'));
      expect(assessment.toJson()['lockStateVerifiedByNfc'], isFalse);
    });

    test('folds GPO 61xx and GET RESPONSE into logical success', () {
      final assessment = assessTransitRecords(
        targetDetected: true,
        records: [
          _apduRecord(
            sequence: 0,
            stage: 1,
            application: 0,
            command: _bytes('00A404000E325041592E5359532E444446303100'),
            response: _bytes('9000'),
          ),
          _applicationRecord(1, _bytes('A0000000031010')),
          _apduRecord(
            sequence: 2,
            stage: 4,
            application: 1,
            command: _bytes('80A8000002830000'),
            response: _bytes('770B9F26081122336108'),
          ),
          _apduRecord(
            sequence: 3,
            stage: 7,
            application: 1,
            command: _bytes('00C0000008'),
            response: _bytes('44556677889000'),
          ),
        ],
        transactionRequested: true,
      );

      expect(assessment.gpoSucceeded, isTrue);
      expect(assessment.applications.single.gpoStatusWord, 0x9000);
      expect(assessment.applications.single.cryptogram, '1122334455667788');
      expect(assessment.applications.single.gpoCommands, hasLength(1));
    });

    test('reports every profile attempt and the final successful GPO', () {
      final assessment = assessTransitRecords(
        targetDetected: true,
        records: [
          _apduRecord(
            sequence: 0,
            stage: 1,
            application: 0,
            command: _bytes('00A404000E325041592E5359532E444446303100'),
            response: _bytes('9000'),
          ),
          _applicationRecord(1, _bytes('A0000000031010')),
          _apduRecord(
            sequence: 2,
            stage: 4,
            application: 1,
            command: _bytes('80A800000683043380400000'),
            response: _bytes('6985'),
          ),
          _apduRecord(
            sequence: 3,
            stage: 4,
            application: 1,
            command: _bytes('80A800000683043280400000'),
            response: _bytes('770A820212349404112233449000'),
          ),
        ],
        transactionRequested: true,
      );

      final application = assessment.applications.single;
      expect(application.gpoCommands, hasLength(2));
      expect(application.gpoAttempts.first.ttq, '33804000');
      expect(application.gpoAttempts.last.ttq, '32804000');
      expect(application.gpoStatusWord, 0x9000);
      expect(application.gpoSucceeded, isTrue);
    });

    test('reports the final GPO rejection status', () {
      final assessment = assessTransitRecords(
        targetDetected: true,
        records: [
          _apduRecord(
            sequence: 0,
            stage: 1,
            application: 0,
            command: _bytes('00A404000E325041592E5359532E444446303100'),
            response: _bytes('9000'),
          ),
          _applicationRecord(1, _bytes('A0000000031010')),
          _apduRecord(
            sequence: 2,
            stage: 4,
            application: 1,
            command: _bytes('80A8000002830000'),
            response: _bytes('6986'),
          ),
        ],
        transactionRequested: true,
      );

      expect(assessment.outcome, TransitGateOutcome.gpoNotCompleted);
      expect(assessment.applications.single.gpoStatusWord, 0x6986);
      expect(assessment.explanation, contains('SW 6986'));
    });

    test('decodes known APDU fields and cryptogram structure', () {
      final decoded = decodeTransitTrace([
        _applicationRecord(1, _bytes('A0000000041010')),
        _apduRecord(
          sequence: 2,
          stage: 4,
          application: 1,
          command: _bytes('80A8000002830000'),
          response:
              _bytes('77159F260811223344556677889F2701809F34031F03029000'),
        ),
      ]);

      expect(decoded, hasLength(1));
      expect(decoded.single.applicationIndex, 1);
      expect(decoded.single.fields['Cryptogram'], '1122334455667788');
      expect(decoded.single.cryptogram['Cryptogram type'],
          contains('online authorisation'));
      expect(decoded.single.apdus.single.statusWord, 0x9000);
    });

    test('identifies the known ECP2 transit polling frame', () {
      final record = _rfRecord(
        sequence: 0,
        stage: 0,
        readerToCard: true,
        data: _bytes('6A02C801000300027900000000C2D8'),
      );

      final decoded = decodeTransitRfFrame(record);
      expect(decoded.first, contains('ECP2'));
      expect(decoded, contains('Terminal profile: transit'));
      expect(decoded, contains('TCI: 030002'));
    });
  });
}

EmvTraceRecord _applicationRecord(int application, Uint8List aid) {
  return _record(
    type: 3,
    sequence: 1,
    stage: 2,
    application: application,
    payload: Uint8List.fromList([aid.length, ...aid, 1]),
  );
}

EmvTraceRecord _apduRecord({
  required int sequence,
  required int stage,
  required int application,
  required Uint8List command,
  required Uint8List response,
}) {
  final sw = response.length >= 2
      ? (response[response.length - 2] << 8) | response.last
      : 0xFFFF;
  final payload = Uint8List(6 + command.length + response.length);
  final payloadData = ByteData.sublistView(payload);
  payloadData.setUint16(0, sw, Endian.big);
  payloadData.setUint16(2, command.length, Endian.big);
  payloadData.setUint16(4, response.length, Endian.big);
  payload.setRange(6, 6 + command.length, command);
  payload.setRange(6 + command.length, payload.length, response);
  return _record(
    type: 2,
    sequence: sequence,
    stage: stage,
    application: application,
    payload: payload,
  );
}

EmvTraceRecord _rfRecord({
  required int sequence,
  required int stage,
  required bool readerToCard,
  required Uint8List data,
}) {
  final payload = Uint8List(5 + data.length);
  final payloadData = ByteData.sublistView(payload);
  payload[0] = readerToCard ? 0 : 1;
  payloadData.setUint16(1, data.length * 8, Endian.big);
  payloadData.setUint16(3, data.length, Endian.big);
  payload.setRange(5, payload.length, data);
  return _record(
    type: 1,
    sequence: sequence,
    stage: stage,
    application: 0,
    payload: payload,
  );
}

EmvTraceRecord _record({
  required int type,
  required int sequence,
  required int stage,
  required int application,
  required Uint8List payload,
}) {
  final bytes = Uint8List(18 + payload.length);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 16 + payload.length, Endian.big);
  bytes[2] = 1;
  bytes[3] = type;
  data.setUint32(4, sequence, Endian.big);
  bytes[8] = stage;
  bytes[9] = application;
  data.setUint16(12, 0, Endian.big);
  data.setUint32(14, sequence * 10, Endian.big);
  bytes.setRange(18, bytes.length, payload);
  return EmvTraceRecord.parse(bytes);
}

Uint8List _bytes(String value) => Uint8List.fromList([
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16),
    ]);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
