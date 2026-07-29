import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';

const String relayLabAidHex = 'F0010203040506';
const int relayLabMaxApduLength = 64;
const int relayLabMaxResponseLength = 260;

enum RelayLabDecision { allow, reject }

class RelayLabPolicyResult {
  const RelayLabPolicyResult(this.decision, this.reason, this.errorResponse);

  final RelayLabDecision decision;
  final String reason;
  final Uint8List errorResponse;

  bool get allowed => decision == RelayLabDecision.allow;
}

RelayLabPolicyResult evaluateRelayLabApdu(Uint8List apdu) {
  if (apdu.isEmpty || apdu.length > relayLabMaxApduLength) {
    return _reject('APDU length outside the synthetic lab limit', '6700');
  }
  if (apdu.length < 4) return _reject('Truncated APDU header', '6700');

  final ins = apdu[1];
  if (apdu[0] == 0x00 && ins == 0xA4) {
    if (apdu.length < 5 || apdu[2] != 0x04 || apdu[3] != 0x00) {
      return _reject('Only SELECT-by-name is accepted', '6A86');
    }
    final length = apdu[4];
    if (length != relayLabAidHex.length ~/ 2 || apdu.length < 5 + length) {
      return _reject('Only the private relay-lab AID is accepted', '6A82');
    }
    final aid = bytesToHex(Uint8List.fromList(apdu.sublist(5, 5 + length)))
        .toUpperCase();
    return aid == relayLabAidHex
        ? _allow('Private relay-lab AID selected')
        : _reject('Payment and unknown AIDs are prohibited', '6A82');
  }

  return apdu[0] == 0xF0
      ? _allow('Private-application APDU accepted')
      : _reject('Only private CLA F0 is accepted after AID selection', '6E00');
}

bool? relayLabNonceBound(Uint8List command, Uint8List response) {
  if (command.length != 13 || command[0] != 0xF0 || command[1] != 0x10) {
    return null;
  }
  if (response.length != 12 ||
      response[0] != 0x80 ||
      response[1] != 0x08 ||
      response[10] != 0x90 ||
      response[11] != 0x00) {
    return false;
  }
  for (var index = 0; index < 8; index++) {
    if (response[index + 2] != command[index + 5]) return false;
  }
  return true;
}

RelayLabPolicyResult _allow(String reason) => RelayLabPolicyResult(
      RelayLabDecision.allow,
      reason,
      Uint8List(0),
    );

RelayLabPolicyResult _reject(String reason, String response) =>
    RelayLabPolicyResult(
      RelayLabDecision.reject,
      reason,
      hexToBytes(response),
    );

class RelayLabExchange {
  const RelayLabExchange({
    required this.commandHex,
    required this.responseHex,
    required this.elapsedUs,
    required this.allowed,
    required this.reason,
    required this.withinDeadline,
    required this.nonceBound,
  });

  final String commandHex;
  final String responseHex;
  final int elapsedUs;
  final bool allowed;
  final String reason;
  final bool withinDeadline;
  final bool? nonceBound;

  bool get passed =>
      allowed &&
      withinDeadline &&
      nonceBound != false &&
      responseHex.endsWith('9000');

  Map<String, Object?> toJson() => {
        'commandHex': commandHex,
        'responseHex': responseHex,
        'elapsedUs': elapsedUs,
        'allowed': allowed,
        'reason': reason,
        'withinDeadline': withinDeadline,
        'nonceBound': nonceBound,
        'passed': passed,
      };
}

class RelayLabStats {
  const RelayLabStats({
    required this.count,
    required this.medianUs,
    required this.p95Us,
    required this.maxUs,
    required this.deadlineFailures,
    required this.nonceFailures,
  });

  final int count;
  final int medianUs;
  final int p95Us;
  final int maxUs;
  final int deadlineFailures;
  final int nonceFailures;

  Map<String, Object?> toJson() => {
        'count': count,
        'medianUs': medianUs,
        'p95Us': p95Us,
        'maxUs': maxUs,
        'deadlineFailures': deadlineFailures,
        'nonceFailures': nonceFailures,
      };
}

RelayLabStats relayLabStats(Iterable<RelayLabExchange> exchanges) {
  final values = exchanges.toList(growable: false);
  final timings = values.map((exchange) => exchange.elapsedUs).toList()..sort();
  if (timings.isEmpty) {
    return const RelayLabStats(
      count: 0,
      medianUs: 0,
      p95Us: 0,
      maxUs: 0,
      deadlineFailures: 0,
      nonceFailures: 0,
    );
  }
  final median = timings.length.isOdd
      ? timings[timings.length ~/ 2]
      : (timings[timings.length ~/ 2 - 1] + timings[timings.length ~/ 2]) ~/ 2;
  final p95Index =
      ((timings.length * 95 + 99) ~/ 100 - 1).clamp(0, timings.length - 1);
  return RelayLabStats(
    count: timings.length,
    medianUs: median,
    p95Us: timings[p95Index],
    maxUs: timings.last,
    deadlineFailures:
        values.where((exchange) => !exchange.withinDeadline).length,
    nonceFailures:
        values.where((exchange) => exchange.nonceBound == false).length,
  );
}

class RelayLabComparison {
  const RelayLabComparison({
    required this.baseline,
    required this.relayed,
    required this.medianOverheadUs,
    required this.conclusion,
  });

  final RelayLabStats baseline;
  final RelayLabStats relayed;
  final int? medianOverheadUs;
  final String conclusion;

  Map<String, Object?> toJson() => {
        'baseline': baseline.toJson(),
        'relayed': relayed.toJson(),
        'medianOverheadUs': medianOverheadUs,
        'conclusion': conclusion,
      };
}

RelayLabComparison compareRelayLabRuns(
  Iterable<RelayLabExchange> baseline,
  Iterable<RelayLabExchange> relayed,
) {
  final baselineStats = relayLabStats(baseline);
  final relayedStats = relayLabStats(relayed);
  final overhead = baselineStats.count == 0 || relayedStats.count == 0
      ? null
      : relayedStats.medianUs - baselineStats.medianUs;
  final conclusion = relayedStats.count == 0
      ? 'Run at least one terminal-facing relay exchange'
      : relayedStats.deadlineFailures > 0
          ? 'The configured deadline rejected one or more synthetic relay exchanges'
          : relayedStats.nonceFailures > 0
              ? 'Timing passed, but at least one challenge response was replayable'
              : 'Synthetic relay exchanges passed timing and nonce checks for this local setup';
  return RelayLabComparison(
    baseline: baselineStats,
    relayed: relayedStats,
    medianOverheadUs: overhead,
    conclusion: conclusion,
  );
}
