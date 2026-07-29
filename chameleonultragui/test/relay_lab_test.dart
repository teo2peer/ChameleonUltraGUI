import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/relay_lab.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hex(String value) => hexToBytes(value);

void main() {
  group('synthetic relay policy', () {
    test('allows only the private AID and synthetic commands', () {
      expect(
        evaluateRelayLabApdu(_hex('00A4040007F001020304050600')).allowed,
        isTrue,
      );
      expect(
        evaluateRelayLabApdu(_hex('F0100000080102030405060708')).allowed,
        isTrue,
      );
      expect(evaluateRelayLabApdu(_hex('F0FF123456AABBCC')).allowed, isTrue);
      expect(evaluateRelayLabApdu(_hex('F030000000')).allowed, isTrue);
    });

    test('rejects payment and unknown application traffic', () {
      final prohibited = [
        '00A404000E325041592E5359532E444446303100',
        '00A4040007A000000003101000',
        '80A8000002830000',
        '00B2010C00',
        '80AE800000',
      ];
      for (final command in prohibited) {
        final result = evaluateRelayLabApdu(_hex(command));
        expect(result.allowed, isFalse, reason: command);
        expect(result.errorResponse.length, 2);
      }
    });

    test('rejects non-private and oversized commands', () {
      expect(evaluateRelayLabApdu(_hex('8010000007AABBCCDDEEFF00')).allowed,
          isFalse);
      expect(
        evaluateRelayLabApdu(Uint8List(relayLabMaxApduLength + 1)).allowed,
        isFalse,
      );
    });

    test('detects challenge responses that are not nonce-bound', () {
      final command = _hex('F0100000080102030405060708');
      expect(
        relayLabNonceBound(command, _hex('800801020304050607089000')),
        isTrue,
      );
      expect(
        relayLabNonceBound(command, _hex('8008A1A2A3A4A5A6A7A89000')),
        isFalse,
      );
      expect(relayLabNonceBound(_hex('F030000000'), _hex('9000')), isNull);
    });

    test('serializes timing evidence without payment data', () {
      const exchange = RelayLabExchange(
        commandHex: 'F030000000',
        responseHex: 'DF0101019000',
        elapsedUs: 12000,
        allowed: true,
        reason: 'Synthetic command accepted',
        withinDeadline: true,
        nonceBound: null,
      );
      expect(exchange.toJson()['withinDeadline'], isTrue);
      expect(exchange.toJson()['elapsedUs'], 12000);
      expect(exchange.passed, isTrue);
      expect(
        const RelayLabExchange(
          commandHex: '00A40400',
          responseHex: '6400',
          elapsedUs: 1000,
          allowed: true,
          reason: 'backend failed',
          withinDeadline: true,
          nonceBound: null,
        ).passed,
        isFalse,
      );
    });

    test('compares direct and relayed timing, deadlines and nonce failures',
        () {
      RelayLabExchange sample(int elapsedUs,
              {bool withinDeadline = true, bool? nonceBound}) =>
          RelayLabExchange(
            commandHex: 'F030000000',
            responseHex: '9000',
            elapsedUs: elapsedUs,
            allowed: true,
            reason: 'test',
            withinDeadline: withinDeadline,
            nonceBound: nonceBound,
          );

      final comparison = compareRelayLabRuns(
        [sample(10000), sample(20000), sample(30000), sample(40000)],
        [
          sample(50000),
          sample(70000, nonceBound: false),
          sample(90000, withinDeadline: false),
        ],
      );
      expect(comparison.baseline.medianUs, 25000);
      expect(comparison.baseline.p95Us, 40000);
      expect(comparison.relayed.medianUs, 70000);
      expect(comparison.medianOverheadUs, 45000);
      expect(comparison.relayed.deadlineFailures, 1);
      expect(comparison.relayed.nonceFailures, 1);
      expect(comparison.conclusion, contains('deadline rejected'));
    });
  });
}
