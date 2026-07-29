import 'dart:typed_data';

import 'package:chameleonultragui/helpers/emv.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hex(String s) => hexToBytes(s.replaceAll(' ', ''));

void main() {
  group('EMV helper', () {
    test('expands GPO format 1 tag 80 into synthetic AIP and AFL leaves', () {
      final tlvs = parseEmvTlv(hex('80 06 12 34 10 01 02 00'));
      final leaf = emvLeafMap(tlvs);

      expect(bytesToHex(leaf['82']!).toUpperCase(), '1234');
      expect(bytesToHex(leaf['94']!).toUpperCase(), '10010200');
    });

    test('builds APDU trace with GENERATE AC and status text', () {
      final trace = emvBuildTrace([
        (hex('80 AE 80 00 00'), hex('77 0A 9F 27 01 80 9F 36 02 00 01 90 00')),
      ]).single;

      expect(trace.name, 'GENERATE AC');
      expect(trace.statusWord, 0x9000);
      expect(trace.statusText, 'Success');
      expect(trace.commandDetails.first, 'ARQC requested');
      expect(
          trace.responseTlvs.map((t) => t.tag), containsAll(['9F27', '9F36']));
    });

    test('expands GENERATE AC format 1 tag 80 into cryptogram leaves', () {
      final traces = emvBuildTrace([
        (
          hex('80 AE 80 00 00'),
          hex('80 0F 80 00 02 11 22 33 44 55 66 77 88 AA BB CC DD 90 00'),
        ),
      ]);
      final leaf = emvLeafMapFromTrace(traces);

      expect(bytesToHex(leaf['9F27']!).toUpperCase(), '80');
      expect(bytesToHex(leaf['9F36']!).toUpperCase(), '0002');
      expect(bytesToHex(leaf['9F26']!).toUpperCase(), '1122334455667788');
      expect(bytesToHex(leaf['9F10']!).toUpperCase(), 'AABBCCDD');
      expect(emvExtractCryptogram(leaf)['Cryptogram type'],
          'ARQC — online authorisation requested');
    });

    test('reports ODA readiness without claiming cryptographic verification',
        () {
      final incomplete = emvAssessOda({
        '82': hex('6100'),
        '8F': hex('05'),
      });
      expect(incomplete.advertisedMethods, ['SDA', 'DDA', 'CDA']);
      expect(incomplete.missingTags,
          containsAll(['90', '93', '9F32', '9F46', '9F47']));
      expect(incomplete.cryptographicallyVerified, isFalse);

      final ready = emvAssessOda({
        '82': hex('6100'),
        '8F': hex('05'),
        '90': hex('01'),
        '93': hex('01'),
        '9F32': hex('03'),
        '9F46': hex('01'),
        '9F47': hex('03'),
      });
      expect(ready.missingTags, isEmpty);
      expect(ready.caPublicKeyIndex, 5);
      expect(ready.status, contains('trusted CAPK'));
      expect(ready.cryptographicallyVerified, isFalse);
    });

    test('interprets the RRP AIP bit only for Mastercard applications', () {
      final aip2020 = emvDecodeAip({'82': hex('2020')})!;
      final mastercardRrp = emvDecodeAip({'82': hex('2001')})!;

      expect(aip2020.dda, isTrue);
      expect(
        emvAssessRrp(aip2020, 'A0000000031010'),
        EmvRrpAssessment.notApplicable,
      );
      expect(
        emvAssessRrp(aip2020, 'A0000000041010'),
        EmvRrpAssessment.notAdvertised,
      );
      expect(
        emvAssessRrp(mastercardRrp, 'A0000000041010'),
        EmvRrpAssessment.advertised,
      );
      expect(
        emvAssessRrp(aip2020, null),
        EmvRrpAssessment.unknownScheme,
      );
    });
  });
}
