import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/emv.dart';
import 'package:chameleonultragui/helpers/emv_trace.dart';
import 'package:chameleonultragui/helpers/general.dart';

enum TransitGateOutcome {
  noTarget,
  directoryUnavailable,
  noApplications,
  discoveryReady,
  gpoNotCompleted,
  transactionEvidence,
  transactionIncomplete,
}

class TransitReplayResult {
  const TransitReplayResult({
    required this.assessment,
    required this.recordCount,
    required this.crc32,
  });

  final TransitGateAssessment assessment;
  final int recordCount;
  final int crc32;
}

class TransitApplicationDecode {
  const TransitApplicationDecode({
    required this.applicationIndex,
    required this.aid,
    required this.apdus,
    required this.fields,
    required this.aip,
    required this.cryptogram,
  });

  final int applicationIndex;
  final String? aid;
  final List<EmvApduTrace> apdus;
  final Map<String, String> fields;
  final EmvAip? aip;
  final Map<String, String> cryptogram;
}

List<TransitApplicationDecode> decodeTransitTrace(
    Iterable<EmvTraceRecord> records) {
  final pairs = <int, List<(Uint8List, Uint8List)>>{};
  final aids = <int, String>{};
  for (final record in records) {
    final payload = record.payload;
    if (payload is EmvTraceApplicationPayload) {
      aids[record.applicationIndex] = bytesToHex(payload.aid).toUpperCase();
    }
    if (payload is! EmvTraceApduPayload) continue;
    pairs
        .putIfAbsent(record.applicationIndex, () => [])
        .add((payload.command, payload.response));
  }

  final indexes = pairs.keys.toList()..sort();
  return List.unmodifiable(indexes.map((index) {
    final apdus = emvBuildTrace(_foldResponseChains(pairs[index]!));
    final leaf = emvLeafMapFromTrace(apdus);
    return TransitApplicationDecode(
      applicationIndex: index,
      aid: aids[index],
      apdus: List.unmodifiable(apdus),
      fields: Map.unmodifiable(emvExtractFields(leaf)),
      aip: emvDecodeAip(leaf),
      cryptogram: Map.unmodifiable(emvExtractCryptogram(leaf)),
    );
  }));
}

List<String> decodeTransitRfFrame(EmvTraceRecord record) {
  final payload = record.payload;
  if (payload is! EmvTraceRfPayload || payload.data.isEmpty) return const [];
  final bytes = payload.data;

  const ecp2 = [
    0x6A,
    0x02,
    0xC8,
    0x01,
    0x00,
    0x03,
    0x00,
    0x02,
    0x79,
    0x00,
    0x00,
    0x00,
    0x00,
    0xC2,
    0xD8,
  ];
  if (payload.readerToCard && _bytesEqual(bytes, ecp2)) {
    return const [
      'Apple Enhanced Contactless Polling v2 (ECP2)',
      'Terminal profile: transit',
      'TCI: 030002',
      'Network mask: 7900000000',
      'Trailing C2D8: frame integrity bytes',
    ];
  }

  if (record.stage == 0) {
    if (payload.readerToCard) {
      if (bytes.length == 1 && bytes[0] == 0x26) return const ['REQA'];
      if (bytes.length == 1 && bytes[0] == 0x52) return const ['WUPA'];
      if (bytes.length >= 2 && bytes[0] == 0xE0) {
        return [
          'RATS: request ISO 14443-4 activation',
          'FSDI: ${(bytes[1] >> 4) & 0x0F}',
          'CID: ${bytes[1] & 0x0F}',
        ];
      }
      if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x00) {
        return const ['HLTA: halt ISO 14443-A target'];
      }
      if (bytes.length >= 2 && const [0x93, 0x95, 0x97].contains(bytes[0])) {
        final level = switch (bytes[0]) { 0x93 => 1, 0x95 => 2, _ => 3 };
        if (bytes[1] == 0x20) return ['ANTICOLLISION cascade level $level'];
        if (bytes[1] == 0x70) return ['SELECT cascade level $level'];
      }
    } else {
      if (payload.bitLength == 16) return const ['ATQA'];
      if (payload.bitLength == 40) {
        return const ['UID cascade fragment plus BCC'];
      }
      if (bytes.length == 3) return const ['SAK plus CRC-A'];
      if (bytes.first == bytes.length || bytes.first == bytes.length - 2) {
        return const ['ATS: ISO 14443-4 Answer To Select'];
      }
    }
    return const [];
  }

  final pcb = bytes.first;
  if ((pcb & 0xC0) == 0x00) {
    return [
      'ISO-DEP I-block',
      'Block number: ${pcb & 0x01}',
      'Chaining: ${(pcb & 0x10) != 0 ? 'yes' : 'no'}',
    ];
  }
  if ((pcb & 0xC0) == 0x80) {
    return [
      'ISO-DEP R-block (${(pcb & 0x10) == 0 ? 'ACK' : 'NAK'})',
      'Block number: ${pcb & 0x01}',
    ];
  }
  if ((pcb & 0xC0) == 0xC0) {
    return [
      'ISO-DEP S-block',
      (pcb & 0x30) == 0x30 ? 'WTX request/response' : 'Control block',
    ];
  }
  return const [];
}

TransitReplayResult replayTransitReport(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, dynamic> ||
      decoded['system'] != 'chameleon-transit-gate-lab') {
    throw const FormatException('Not a Chameleon transit report');
  }
  final trace = decoded['trace'];
  if (trace is! Map<String, dynamic> ||
      trace['protocol'] != 'chameleon-emv-trace') {
    throw const FormatException('Missing retained EMV trace');
  }
  final recordJson = trace['records'];
  final streamHex = trace['recordStreamHex'];
  final meta = trace['meta'];
  if (recordJson is! List ||
      streamHex is! String ||
      meta is! Map<String, dynamic>) {
    throw const FormatException('Malformed retained EMV trace JSON');
  }
  final records = <EmvTraceRecord>[];
  final stream = BytesBuilder(copy: false);
  for (final value in recordJson) {
    if (value is! Map || value['rawRecordHex'] is! String) {
      throw const FormatException('Malformed replay record');
    }
    final raw = _strictHex(value['rawRecordHex'] as String);
    records.add(EmvTraceRecord.parse(raw));
    stream.add(raw);
  }
  final streamBytes = stream.takeBytes();
  if (bytesToHex(streamBytes).toUpperCase() != streamHex.toUpperCase()) {
    throw const FormatException('Replay record stream mismatch');
  }
  final crc = emvTraceCrc32(streamBytes);
  if (meta['crc32'] is! int || meta['crc32'] != crc) {
    throw const FormatException('Replay CRC-32 mismatch');
  }
  final previousAssessment = decoded['assessment'];
  final transactionRequested = previousAssessment is Map &&
      previousAssessment['transactionRequested'] == true;
  final uidHex = meta['uidHex'];
  final assessment = assessTransitRecords(
    targetDetected: uidHex is String && uidHex.isNotEmpty,
    records: records,
    transactionRequested: transactionRequested,
  );
  return TransitReplayResult(
    assessment: assessment,
    recordCount: records.length,
    crc32: crc,
  );
}

class TransitGpoAttempt {
  const TransitGpoAttempt({
    required this.index,
    required this.command,
    required this.pdolData,
    required this.ttq,
    required this.statusWord,
    required this.statusText,
  });

  final int index;
  final String command;
  final String pdolData;
  final String? ttq;
  final int? statusWord;
  final String statusText;

  bool get succeeded => statusWord == 0x9000;
  String get recommendation => switch (statusWord) {
        0x9000 => 'Stop: GPO completed',
        0x6985 => 'Try the next bounded terminal profile',
        0x6986 => 'Reacquire RF, rerun ECP, then try the next profile',
        0x6A80 => 'Try the next profile and inspect PDOL values',
        null => 'Inspect transport and trace-truncation flags',
        _ => 'Stop automatic retries and inspect this status',
      };

  Map<String, Object?> toJson() => {
        'index': index,
        'command': command,
        'pdolData': pdolData,
        'ttq': ttq,
        'statusWord': statusWord,
        'statusText': statusText,
        'succeeded': succeeded,
        'recommendation': recommendation,
      };
}

Uint8List transitAmountBcd(String input) {
  final normalized = input.replaceAll(',', '.').trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) throw const FormatException('invalid amount');
  final whole = match.group(1)!;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final digits = '$whole$fraction'.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (digits.length > 12) throw const FormatException('amount too large');
  final padded = digits.padLeft(12, '0');
  return Uint8List.fromList([
    for (var i = 0; i < 12; i += 2)
      (int.parse(padded[i]) << 4) | int.parse(padded[i + 1]),
  ]);
}

class TransitApplicationEvidence {
  const TransitApplicationEvidence({
    required this.index,
    required this.aid,
    required this.scheme,
    required this.gpoAttempted,
    required this.gpoSucceeded,
    required this.gpoStatusWord,
    required this.gpoStatusText,
    required this.gpoAttempts,
    required this.generateAcAttempted,
    required this.cryptogram,
    required this.cryptogramType,
    required this.cvmResults,
    required this.cardTransactionQualifiers,
    required this.oda,
  });

  final int index;
  final String aid;
  final String scheme;
  final bool gpoAttempted;
  final bool gpoSucceeded;
  final int? gpoStatusWord;
  final String? gpoStatusText;
  final List<TransitGpoAttempt> gpoAttempts;
  final bool generateAcAttempted;
  final String? cryptogram;
  final String? cryptogramType;
  final String? cvmResults;
  final String? cardTransactionQualifiers;
  final EmvOdaAssessment oda;

  bool get hasTransactionEvidence => cryptogram != null;
  List<String> get gpoCommands =>
      gpoAttempts.map((attempt) => attempt.command).toList(growable: false);

  Map<String, Object?> toJson() => {
        'index': index,
        'aid': aid,
        'scheme': scheme,
        'gpoAttempted': gpoAttempted,
        'gpoSucceeded': gpoSucceeded,
        'gpoStatusWord': gpoStatusWord,
        'gpoStatusText': gpoStatusText,
        'gpoAttemptCount': gpoAttempts.length,
        'gpoAttempts': gpoAttempts.map((attempt) => attempt.toJson()).toList(),
        'generateAcAttempted': generateAcAttempted,
        'cryptogram': cryptogram,
        'cryptogramType': cryptogramType,
        'cvmResults': cvmResults,
        'cardTransactionQualifiers': cardTransactionQualifiers,
        'oda': oda.toJson(),
      };
}

class TransitGateAssessment {
  const TransitGateAssessment({
    required this.outcome,
    required this.targetDetected,
    required this.ppseSucceeded,
    required this.transactionRequested,
    required this.gpoAttempted,
    required this.gpoSucceeded,
    required this.applications,
  });

  final TransitGateOutcome outcome;
  final bool targetDetected;
  final bool ppseSucceeded;
  final bool transactionRequested;
  final bool gpoAttempted;
  final bool gpoSucceeded;
  final List<TransitApplicationEvidence> applications;

  bool get walletResponded =>
      targetDetected && (ppseSucceeded || applications.isNotEmpty);
  bool get hasTransactionEvidence =>
      applications.any((application) => application.hasTransactionEvidence);

  String get headline => switch (outcome) {
        TransitGateOutcome.noTarget => 'No contactless target',
        TransitGateOutcome.directoryUnavailable =>
          'Phone detected, payment directory unavailable',
        TransitGateOutcome.noApplications =>
          'Payment directory responded, no EMV application found',
        TransitGateOutcome.discoveryReady => 'Wallet responded to locked test',
        TransitGateOutcome.gpoNotCompleted =>
          'Wallet visible, transaction path did not complete',
        TransitGateOutcome.transactionEvidence =>
          'Transit transaction evidence captured',
        TransitGateOutcome.transactionIncomplete =>
          'GPO completed, no cryptogram captured',
      };

  String get explanation => switch (outcome) {
        TransitGateOutcome.noTarget =>
          'No ISO-DEP phone or card was detected during the polling window.',
        TransitGateOutcome.directoryUnavailable =>
          'The NFC target answered, but SELECT PPSE did not return 9000. The wallet may require unlock, another gesture, or a proprietary transit protocol.',
        TransitGateOutcome.noApplications =>
          'SELECT PPSE succeeded but did not advertise an EMV payment AID.',
        TransitGateOutcome.discoveryReady => ppseSucceeded
            ? 'The phone exposed its EMV payment directory and application while the operator reported it locked. This is readiness evidence, not proof that a real gate would approve a fare.'
            : 'PPSE was unavailable, but a bounded direct-AID probe selected a known payment application. This is compatibility evidence, not proof that a real gate would approve a fare.',
        TransitGateOutcome.gpoNotCompleted => _gpoFailureExplanation,
        TransitGateOutcome.transactionEvidence =>
          'At least one application returned an application cryptogram. It was not sent to an issuer and is not a payment approval.',
        TransitGateOutcome.transactionIncomplete =>
          'An application completed GPO, but the trace contained no application cryptogram. Unlock/CDCVM, issuer policy, or a different transit profile may be required.',
      };

  String get _gpoFailureExplanation {
    final attempted =
        applications.where((application) => application.gpoAttempted);
    if (attempted.isEmpty) {
      return 'The wallet was visible, but no GPO command was sent. Check SELECT AID, trace truncation, or the card PDOL.';
    }
    final statuses = attempted
        .where((application) => application.gpoStatusWord != null)
        .map((application) {
      final sw = application.gpoStatusWord!
          .toRadixString(16)
          .padLeft(4, '0')
          .toUpperCase();
      return 'App ${application.index}: SW $sw (${application.gpoStatusText})';
    }).join('; ');
    return statuses.isEmpty
        ? 'GPO was sent, but no complete response status was captured. Check transport and truncation flags.'
        : 'GPO did not complete. $statuses';
  }

  Map<String, Object?> toJson() => {
        'outcome': outcome.name,
        'headline': headline,
        'explanation': explanation,
        'targetDetected': targetDetected,
        'ppseSucceeded': ppseSucceeded,
        'transactionRequested': transactionRequested,
        'gpoAttempted': gpoAttempted,
        'gpoSucceeded': gpoSucceeded,
        'operatorDeclaredLocked': true,
        'lockStateVerifiedByNfc': false,
        'applications': applications.map((value) => value.toJson()).toList(),
      };
}

TransitGateAssessment assessTransitCapture(
  EmvTraceCapture capture, {
  required bool transactionRequested,
}) {
  return assessTransitRecords(
    targetDetected: capture.meta.uid.isNotEmpty,
    records: capture.records,
    transactionRequested: transactionRequested,
  );
}

TransitGateAssessment assessTransitRecords({
  required bool targetDetected,
  required Iterable<EmvTraceRecord> records,
  required bool transactionRequested,
}) {
  final aids = <int, String>{};
  final pairs = <int, List<(Uint8List, Uint8List)>>{};

  for (final record in records) {
    final payload = record.payload;
    if (payload is EmvTraceApplicationPayload) {
      aids[record.applicationIndex] = bytesToHex(payload.aid).toUpperCase();
      continue;
    }
    if (payload is! EmvTraceApduPayload) continue;
    pairs
        .putIfAbsent(record.applicationIndex, () => [])
        .add((payload.command, payload.response));
  }

  final logicalPairs = {
    for (final entry in pairs.entries)
      entry.key: _foldResponseChains(entry.value),
  };
  final ppseSucceeded = (logicalPairs[0] ?? const [])
      .any((pair) => _isPpseSelect(pair.$1) && _statusWord(pair.$2) == 0x9000);
  var gpoAttempted = false;
  var gpoSucceeded = false;

  final applicationIndexes = aids.keys.toList()..sort();
  final applications = <TransitApplicationEvidence>[];
  for (final index in applicationIndexes.where((value) => value > 0)) {
    final traces = emvBuildTrace(logicalPairs[index] ?? const []);
    final leaf = emvLeafMapFromTrace(traces);
    final cryptogram = leaf['9F26'];
    final cid = leaf['9F27'];
    final gpoTraces =
        traces.where((trace) => _hasInstruction(trace.command, 0xA8)).toList();
    final gpoStatus = gpoTraces.isEmpty ? null : gpoTraces.last.statusWord;
    final gpoAttempts = [
      for (var attempt = 0; attempt < gpoTraces.length; attempt++)
        _gpoAttempt(attempt + 1, gpoTraces[attempt]),
    ];
    final applicationGpoSucceeded = gpoStatus == 0x9000;
    gpoAttempted |= gpoTraces.isNotEmpty;
    gpoSucceeded |= applicationGpoSucceeded;
    applications.add(TransitApplicationEvidence(
      index: index,
      aid: aids[index] ?? 'Unknown',
      scheme: paymentSchemeForAid(aids[index] ?? ''),
      gpoAttempted: gpoTraces.isNotEmpty,
      gpoSucceeded: applicationGpoSucceeded,
      gpoStatusWord: gpoStatus,
      gpoStatusText: gpoStatus == null ? null : emvStatusText(gpoStatus),
      gpoAttempts: List.unmodifiable(gpoAttempts),
      generateAcAttempted:
          traces.any((trace) => _hasInstruction(trace.command, 0xAE)),
      cryptogram:
          cryptogram == null ? null : bytesToHex(cryptogram).toUpperCase(),
      cryptogramType:
          cid == null || cid.isEmpty ? null : _cryptogramType(cid.first),
      cvmResults: _hexOrNull(leaf['9F34']),
      cardTransactionQualifiers: _hexOrNull(leaf['9F6C']),
      oda: emvAssessOda(leaf),
    ));
  }

  final outcome = !targetDetected
      ? TransitGateOutcome.noTarget
      : !ppseSucceeded && applications.isEmpty
          ? TransitGateOutcome.directoryUnavailable
          : applications.isEmpty
              ? TransitGateOutcome.noApplications
              : !transactionRequested
                  ? TransitGateOutcome.discoveryReady
                  : !gpoAttempted || !gpoSucceeded
                      ? TransitGateOutcome.gpoNotCompleted
                      : applications.any(
                              (application) => application.cryptogram != null)
                          ? TransitGateOutcome.transactionEvidence
                          : TransitGateOutcome.transactionIncomplete;

  return TransitGateAssessment(
    outcome: outcome,
    targetDetected: targetDetected,
    ppseSucceeded: ppseSucceeded,
    transactionRequested: transactionRequested,
    gpoAttempted: gpoAttempted,
    gpoSucceeded: gpoSucceeded,
    applications: List.unmodifiable(applications),
  );
}

String paymentSchemeForAid(String aid) {
  final normalized = aid.toUpperCase();
  if (normalized.startsWith('A000000003')) return 'Visa';
  if (normalized.startsWith('A000000004')) {
    return normalized.startsWith('A0000000043060') ? 'Maestro' : 'Mastercard';
  }
  if (normalized.startsWith('A000000025')) return 'American Express';
  if (normalized.startsWith('A000000152')) return 'Discover';
  if (normalized.startsWith('A000000065')) return 'JCB';
  if (normalized.startsWith('A000000333')) return 'UnionPay';
  if (normalized.startsWith('A000000277')) return 'Interac';
  return 'Unknown scheme';
}

List<EmvTerminalProfile> transitProfileOrder(String? scheme,
    {required bool adaptive}) {
  if (!adaptive || scheme == 'Visa') {
    return const [
      EmvTerminalProfile.appleTransit,
      EmvTerminalProfile.onlineNoOda,
      EmvTerminalProfile.qvsdcOnline,
      EmvTerminalProfile.broadMobile,
      EmvTerminalProfile.minimalOnline,
      EmvTerminalProfile.msdQvsdc,
    ];
  }
  if (scheme == 'Mastercard' || scheme == 'Maestro') {
    return const [
      EmvTerminalProfile.broadMobile,
      EmvTerminalProfile.qvsdcOnline,
      EmvTerminalProfile.appleTransit,
      EmvTerminalProfile.onlineNoOda,
      EmvTerminalProfile.msdQvsdc,
      EmvTerminalProfile.minimalOnline,
    ];
  }
  return const [
    EmvTerminalProfile.qvsdcOnline,
    EmvTerminalProfile.broadMobile,
    EmvTerminalProfile.appleTransit,
    EmvTerminalProfile.onlineNoOda,
    EmvTerminalProfile.minimalOnline,
    EmvTerminalProfile.msdQvsdc,
  ];
}

TransitGpoAttempt _gpoAttempt(int index, EmvApduTrace trace) {
  final command = trace.command;
  var pdol = Uint8List(0);
  if (command.length >= 7 && command[4] + 5 <= command.length) {
    final data = command.sublist(5, 5 + command[4]);
    if (data.length >= 2 && data[0] == 0x83 && data[1] <= data.length - 2) {
      pdol = Uint8List.fromList(data.sublist(2, 2 + data[1]));
    }
  }
  final pdolHex = bytesToHex(pdol).toUpperCase();
  const knownTtqs = [
    '33804000',
    '32804000',
    '3600C000',
    '26804000',
    '22804000',
    'B600C000',
  ];
  final ttq = knownTtqs.where(pdolHex.contains).firstOrNull;
  return TransitGpoAttempt(
    index: index,
    command: bytesToHex(command).toUpperCase(),
    pdolData: pdolHex,
    ttq: ttq,
    statusWord: trace.statusWord,
    statusText: trace.statusText,
  );
}

List<(Uint8List, Uint8List)> _foldResponseChains(
    List<(Uint8List, Uint8List)> pairs) {
  final logical = <(Uint8List, Uint8List)>[];
  for (var i = 0; i < pairs.length; i++) {
    final command = pairs[i].$1;
    var response = pairs[i].$2;
    if (response.length < 2 || response[response.length - 2] != 0x61) {
      logical.add((command, response));
      continue;
    }

    final body = BytesBuilder(copy: false)
      ..add(response.sublist(0, response.length - 2));
    var cursor = i;
    while (response.length >= 2 &&
        response[response.length - 2] == 0x61 &&
        cursor + 1 < pairs.length &&
        _hasInstruction(pairs[cursor + 1].$1, 0xC0)) {
      cursor++;
      response = pairs[cursor].$2;
      if (response.length >= 2) {
        body.add(response.sublist(0, response.length - 2));
      }
    }
    if (cursor == i || response.length < 2) {
      logical.add((command, pairs[i].$2));
      continue;
    }
    body.add(response.sublist(response.length - 2));
    logical.add((command, body.takeBytes()));
    i = cursor;
  }
  return logical;
}

int? _statusWord(Uint8List response) => response.length < 2
    ? null
    : (response[response.length - 2] << 8) | response.last;

bool _hasInstruction(Uint8List command, int instruction) =>
    command.length >= 2 && command[1] == instruction;

bool _isPpseSelect(Uint8List command) {
  if (command.length < 20 || command[1] != 0xA4) return false;
  const ppse = [
    0x32,
    0x50,
    0x41,
    0x59,
    0x2E,
    0x53,
    0x59,
    0x53,
    0x2E,
    0x44,
    0x44,
    0x46,
    0x30,
    0x31,
  ];
  if (command[4] != ppse.length || command.length < 5 + ppse.length) {
    return false;
  }
  for (var i = 0; i < ppse.length; i++) {
    if (command[5 + i] != ppse[i]) return false;
  }
  return true;
}

String _cryptogramType(int cid) => switch (cid & 0xC0) {
      0x00 => 'AAC (decline)',
      0x40 => 'TC (offline cryptogram)',
      0x80 => 'ARQC (online/deferred-online request)',
      _ => 'RFU cryptogram type',
    };

String? _hexOrNull(Uint8List? value) =>
    value == null ? null : bytesToHex(value).toUpperCase();

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Uint8List _strictHex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw const FormatException('Invalid replay hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}
