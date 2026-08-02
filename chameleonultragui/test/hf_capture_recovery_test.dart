import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/helpers/hf_capture_controller.dart';
import 'package:chameleonultragui/helpers/mifare_classic/hf_capture_recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/reader_key_recovery.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('continuous capture MIFARE parser', () {
    test('keeps a complete MFKey64 exchange across record batches', () {
      final parser = HfCaptureMifareParser();

      expect(
        parser.addRecords([
          _frame(0, HfCaptureDirection.readerToCard, [
            0x93,
            0x70,
            0xDE,
            0xAD,
            0xBE,
            0xEF,
          ]),
          _frame(1, HfCaptureDirection.readerToCard, [0x60, 0x04]),
          _frame(2, HfCaptureDirection.cardToReader, [1, 2, 3, 4]),
        ]),
        isEmpty,
      );

      final evidence = parser.addRecords([
        _frame(3, HfCaptureDirection.readerToCard, [
          0x10,
          0x11,
          0x12,
          0x13,
          0x20,
          0x21,
          0x22,
          0x23,
        ]),
        _frame(4, HfCaptureDirection.cardToReader, [0x30, 0x31, 0x32, 0x33]),
      ]);

      expect(evidence, hasLength(1));
      expect(evidence.single.uidHex, 'DEADBEEF');
      expect(evidence.single.target.sector, 1);
      expect(evidence.single.target.keyType, 'A');
      expect(evidence.single.ntHex, '01020304');
      expect(evidence.single.nrHex, '10111213');
      expect(evidence.single.arHex, '20212223');
      expect(evidence.single.atHex, '30313233');
    });

    test('uses the final cascade UID bytes for seven-byte cards', () {
      final parser = HfCaptureMifareParser();
      final evidence = parser.addRecords([
        _frame(0, HfCaptureDirection.readerToCard, [
          0x93,
          0x70,
          0x88,
          0x04,
          0x25,
          0x85,
        ]),
        _frame(1, HfCaptureDirection.readerToCard, [
          0x95,
          0x70,
          0x11,
          0x22,
          0x33,
          0x44,
        ]),
        _frame(2, HfCaptureDirection.readerToCard, [0x61, 0x08]),
        _frame(3, HfCaptureDirection.cardToReader, [1, 2, 3, 4]),
        _frame(4, HfCaptureDirection.readerToCard, [5, 6, 7, 8, 9, 10, 11, 12]),
        _frame(5, HfCaptureDirection.cardToReader, [13, 14, 15, 16]),
      ]);

      expect(evidence.single.uidHex, '11223344');
      expect(evidence.single.target.keyType, 'B');
    });

    test('does not join authentication frames across a sequence gap', () {
      final parser = HfCaptureMifareParser(expectedUid: 0xDEADBEEF);
      final evidence = parser.addRecords([
        _frame(0, HfCaptureDirection.readerToCard, [0x60, 0x04]),
        _frame(1, HfCaptureDirection.cardToReader, [1, 2, 3, 4]),
        _frame(3, HfCaptureDirection.readerToCard, [5, 6, 7, 8, 9, 10, 11, 12]),
        _frame(4, HfCaptureDirection.cardToReader, [13, 14, 15, 16]),
      ]);

      expect(evidence, isEmpty);
      expect(parser.flush(), isEmpty);
    });

    test('does not join authentication frames across a field event', () {
      final parser = HfCaptureMifareParser(expectedUid: 0xDEADBEEF);
      final evidence = parser.addRecords([
        _frame(0, HfCaptureDirection.readerToCard, [0x60, 0x04]),
        _frame(1, HfCaptureDirection.cardToReader, [1, 2, 3, 4]),
        _field(2),
        _frame(3, HfCaptureDirection.readerToCard, [5, 6, 7, 8, 9, 10, 11, 12]),
      ]);

      expect(evidence, isEmpty);
    });

    test('flushes a complete MFKey32 transcript without AT', () {
      final parser = HfCaptureMifareParser(expectedUid: 0xDEADBEEF);
      expect(
        parser.addRecords([
          _frame(0, HfCaptureDirection.readerToCard, [0x60, 0x04]),
          _frame(1, HfCaptureDirection.cardToReader, [1, 2, 3, 4]),
          _frame(2, HfCaptureDirection.readerToCard, [
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
          ]),
        ]),
        isEmpty,
      );

      final evidence = parser.flush();
      expect(evidence, hasLength(1));
      expect(evidence.single.at, isNull);
    });
  });

  group('continuous capture key recovery', () {
    test('passes the captured AT to MFKey64', () async {
      recovery.Mfkey64Dart? request;
      final recovered = await recoverHfCaptureMifareKeys(
        evidence: [_evidence(nt: 1, at: 0xAABBCCDD)],
        mfkey64Solver: (value) async {
          request = value;
          return 0xA0A1A2A3A4A5;
        },
        mfkey32Solver: (_) async => fail('MFKey32 must not run'),
      );

      expect(request!.atEnc, 0xAABBCCDD);
      expect(recovered.single.keyHex, 'A0A1A2A3A4A5');
      expect(recovered.single.method, 'MFKey64');
    });

    test('uses two compatible transcripts with MFKey32', () async {
      var calls = 0;
      final recovered = await recoverHfCaptureMifareKeys(
        evidence: [_evidence(nt: 1), _evidence(nt: 2)],
        mfkey64Solver: (_) async => fail('MFKey64 must not run'),
        mfkey32Solver: (request) async {
          calls++;
          expect({request.nt0, request.nt1}, {1, 2});
          return 0x010203040506;
        },
      );

      expect(calls, 1);
      expect(recovered.single.keyHex, '010203040506');
      expect(recovered.single.method, 'MFKey32');
    });

    test('rejects the native no-key sentinel', () async {
      final recovered = await recoverHfCaptureMifareKeys(
        evidence: [_evidence(nt: 1, at: 2)],
        mfkey64Solver: (_) async => mfkey32NoKey,
        mfkey32Solver: (_) async => null,
      );

      expect(recovered, isEmpty);
    });

    test(
      'saves recovered keys automatically in a per-UID dictionary',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = SharedPreferencesProvider();
        await preferences.load();
        final captureController = HfCaptureController(preferences);
        final batches = StreamController<HfCaptureRecordBatch>();
        final saved = Completer<void>();
        final recoveryController = HfCaptureMifareRecoveryController(
          preferences,
          captureController,
          recordBatches: batches.stream,
          mfkey64Solver: (_) async => 0xA0A1A2A3A4A5,
          mfkey32Solver: (_) async => null,
          onKeysSaved: saved.complete,
        );
        addTearDown(() async {
          recoveryController.dispose();
          captureController.dispose();
          await batches.close();
        });

        batches.add(
          HfCaptureRecordBatch(
            sessionId: 1,
            bootId: 2,
            startToken: 3,
            mode: HfCaptureMode.emulation,
            pageIndex: 0,
            deliveryToken: 4,
            records: _completeExchange(),
            replayed: false,
          ),
        );
        await saved.future.timeout(const Duration(seconds: 5));

        expect(recoveryController.savedKeyCount, 1);
        expect(recoveryController.recoveredKeys.single.saved, isTrue);
        final dictionaries = preferences.getDictionaries(keyLength: 12);
        expect(dictionaries, hasLength(1));
        expect(dictionaries.single.name, 'hf-capture-deadbeef');
        expect(dictionaries.single.toString().trim(), 'A0A1A2A3A4A5');
      },
    );
  });
}

HfCaptureMifareEvidence _evidence({required int nt, int? at}) =>
    HfCaptureMifareEvidence(
      detection: DetectionResult(
        block: 4,
        type: 0x60,
        isNested: false,
        uid: 0xDEADBEEF,
        nt: nt,
        nr: nt + 10,
        ar: nt + 20,
      ),
      authSequence: nt,
      at: at,
    );

List<HfCaptureRecord> _completeExchange() => [
  _frame(0, HfCaptureDirection.readerToCard, [
    0x93,
    0x70,
    0xDE,
    0xAD,
    0xBE,
    0xEF,
  ]),
  _frame(1, HfCaptureDirection.readerToCard, [0x60, 0x04]),
  _frame(2, HfCaptureDirection.cardToReader, [1, 2, 3, 4]),
  _frame(3, HfCaptureDirection.readerToCard, [5, 6, 7, 8, 9, 10, 11, 12]),
  _frame(4, HfCaptureDirection.cardToReader, [13, 14, 15, 16]),
];

HfCaptureRecord _frame(
  int sequence,
  HfCaptureDirection direction,
  List<int> data,
) => HfCaptureRecord(
  type: HfCaptureRecordType.frame,
  sequence: sequence,
  timestampTicks: sequence,
  direction: direction,
  flags: 0,
  bitLength: data.length * 8,
  data: Uint8List.fromList(data),
  encoded: Uint8List(0),
);

HfCaptureRecord _field(int sequence) => HfCaptureRecord(
  type: HfCaptureRecordType.field,
  sequence: sequence,
  timestampTicks: sequence,
  direction: HfCaptureDirection.event,
  flags: 0,
  bitLength: 0,
  data: Uint8List.fromList([0]),
  encoded: Uint8List(0),
);
