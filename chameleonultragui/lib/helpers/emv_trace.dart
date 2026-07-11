import 'dart:typed_data';

const int emvTraceProtocolVersion = 1;

const int emvTraceFlagComplete = 0x00000001;
const int emvTraceFlagTimeout = 0x00000002;
const int emvTraceFlagLogTruncated = 0x00000004;
const int emvTraceFlagRfTruncated = 0x00000008;
const int emvTraceFlagResponseTruncated = 0x00000010;
const int emvTraceFlagAppLimit = 0x00000020;
const int emvTraceFlagTimingValid = 0x00000040;
const int emvTraceFlagMaximumProcessing = 0x00000080;
const int emvTraceFlagTransportError = 0x00000100;

const int _knownTraceFlags = 0x000001ff;
const int _noDroppedRecord = 0xffffffff;

enum EmvTraceState {
  empty(0, 'empty'),
  running(1, 'running'),
  complete(2, 'complete'),
  aborted(3, 'aborted');

  const EmvTraceState(this.value, this.label);

  final int value;
  final String label;

  static EmvTraceState fromValue(int value) {
    return values.firstWhere(
      (state) => state.value == value,
      orElse: () => throw FormatException('Unknown EMV trace state $value'),
    );
  }
}

enum EmvTraceRecordType {
  rf(1, 'RF frame'),
  apdu(2, 'APDU'),
  application(3, 'application'),
  summary(4, 'summary');

  const EmvTraceRecordType(this.value, this.label);

  final int value;
  final String label;

  static EmvTraceRecordType fromValue(int value) {
    return values.firstWhere(
      (type) => type.value == value,
      orElse: () =>
          throw FormatException('Unknown EMV trace record type $value'),
    );
  }
}

const Map<int, String> emvTraceStageNames = {
  0: 'activation',
  1: 'PPSE',
  2: 'select application',
  3: 'get data',
  4: 'GPO',
  5: 'read AFL',
  6: 'record grid',
  7: 'get response',
  8: 'generate AC',
  9: 'transaction log',
  0xff: 'summary',
};

class EmvTraceRequest {
  const EmvTraceRequest({
    this.maximumProcessing = false,
    this.includeRf = true,
    this.includeTiming = true,
    this.scanRecordGrid = false,
    this.readTransactionLogs = false,
    this.usePdolFallback = true,
    this.maxAids = 8,
    this.maxRecords = 32,
    this.maxApdus = 128,
    this.budgetMs = 12000,
    required this.amount,
    required this.country,
    required this.currency,
    required this.date,
    this.transactionType = 0,
    this.cryptogramType = 0xff,
  });

  factory EmvTraceRequest.readOnly({
    bool maximumProcessing = false,
    bool includeRf = true,
    bool scanRecordGrid = false,
    bool readTransactionLogs = false,
    int maxAids = 8,
    int maxRecords = 32,
    int maxApdus = 128,
    int budgetMs = 12000,
    Uint8List? country,
    Uint8List? currency,
    Uint8List? date,
  }) {
    return EmvTraceRequest(
      maximumProcessing: maximumProcessing,
      includeRf: includeRf,
      scanRecordGrid: scanRecordGrid,
      readTransactionLogs: readTransactionLogs,
      maxAids: maxAids,
      maxRecords: maxRecords,
      maxApdus: maxApdus,
      budgetMs: budgetMs,
      amount: Uint8List(6),
      country: country ?? Uint8List.fromList([0x02, 0x50]),
      currency: currency ?? Uint8List.fromList([0x09, 0x78]),
      date: date ?? emvTraceDate(DateTime.now()),
    );
  }

  final bool maximumProcessing;
  final bool includeRf;
  final bool includeTiming;
  final bool scanRecordGrid;
  final bool readTransactionLogs;
  final bool usePdolFallback;
  final int maxAids;
  final int maxRecords;
  final int maxApdus;
  final int budgetMs;
  final Uint8List amount;
  final Uint8List country;
  final Uint8List currency;
  final Uint8List date;
  final int transactionType;
  final int cryptogramType;

  int get flags =>
      (maximumProcessing ? 0x01 : 0) |
      (includeRf ? 0x02 : 0) |
      (includeTiming ? 0x04 : 0) |
      (scanRecordGrid ? 0x08 : 0) |
      (readTransactionLogs ? 0x10 : 0) |
      (usePdolFallback ? 0x20 : 0);

  Uint8List encode() {
    if (maxAids < 0 || maxAids > 16) {
      throw ArgumentError.value(maxAids, 'maxAids', 'must be 0..16');
    }
    if (maxRecords < 0 || maxRecords > 64) {
      throw ArgumentError.value(maxRecords, 'maxRecords', 'must be 0..64');
    }
    if (maxApdus < 0 || maxApdus > 512) {
      throw ArgumentError.value(maxApdus, 'maxApdus', 'must be 0..512');
    }
    if (budgetMs < 0 || budgetMs > 30000) {
      throw ArgumentError.value(budgetMs, 'budgetMs', 'must be 0..30000');
    }
    _requireLength(amount, 6, 'amount');
    _requireLength(country, 2, 'country');
    _requireLength(currency, 2, 'currency');
    _requireLength(date, 3, 'date');
    if (transactionType < 0 || transactionType > 0xff) {
      throw ArgumentError.value(
          transactionType, 'transactionType', 'must be 0..255');
    }
    if (!const [0xff, 0x00, 0x40, 0x80].contains(cryptogramType)) {
      throw ArgumentError.value(
          cryptogramType, 'cryptogramType', 'must be FF, 00, 40, or 80');
    }

    final output = Uint8List(25);
    final data = ByteData.sublistView(output);
    output[0] = emvTraceProtocolVersion;
    output[1] = flags;
    output[2] = maxAids;
    output[3] = maxRecords;
    data.setUint16(4, maxApdus, Endian.big);
    data.setUint32(6, budgetMs, Endian.big);
    output.setRange(10, 16, amount);
    output.setRange(16, 18, country);
    output.setRange(18, 20, currency);
    output.setRange(20, 23, date);
    output[23] = transactionType;
    output[24] = cryptogramType;
    return output;
  }
}

Uint8List emvTraceDate(DateTime value) => Uint8List.fromList([
      _bcd(value.year % 100),
      _bcd(value.month),
      _bcd(value.day),
    ]);

class EmvTraceStartResponse {
  const EmvTraceStartResponse({
    required this.state,
    required this.scanId,
    required this.flags,
  });

  final EmvTraceState state;
  final int scanId;
  final int flags;

  factory EmvTraceStartResponse.parse(Uint8List bytes) {
    if (bytes.length != 10) {
      throw const FormatException('EMV trace START response must be 10 bytes');
    }
    _requireVersion(bytes[0]);
    final data = ByteData.sublistView(bytes);
    final flags = data.getUint32(6, Endian.big);
    _requireKnownFlags(flags);
    final scanId = data.getUint32(2, Endian.big);
    if (scanId == 0) {
      throw const FormatException('EMV trace scan ID must not be zero');
    }
    return EmvTraceStartResponse(
      state: EmvTraceState.fromValue(bytes[1]),
      scanId: scanId,
      flags: flags,
    );
  }
}

class EmvTraceMeta {
  const EmvTraceMeta({
    required this.state,
    required this.resultStatus,
    required this.flags,
    required this.scanId,
    required this.storedRecords,
    required this.observedRecords,
    required this.storedBytes,
    required this.requiredBytes,
    required this.firstDropped,
    required this.crc32,
    required this.applicationCount,
    required this.elapsedMs,
    required this.uid,
    required this.atqa,
    required this.sak,
    required this.ats,
  });

  final EmvTraceState state;
  final int resultStatus;
  final int flags;
  final int scanId;
  final int storedRecords;
  final int observedRecords;
  final int storedBytes;
  final int requiredBytes;
  final int firstDropped;
  final int crc32;
  final int applicationCount;
  final int elapsedMs;
  final Uint8List uid;
  final Uint8List atqa;
  final int sak;
  final Uint8List ats;

  bool get isComplete =>
      state == EmvTraceState.complete && (flags & emvTraceFlagComplete) != 0;
  bool get isTruncated =>
      (flags &
              (emvTraceFlagLogTruncated |
                  emvTraceFlagRfTruncated |
                  emvTraceFlagResponseTruncated)) !=
          0 ||
      storedRecords != observedRecords ||
      storedBytes != requiredBytes;
  bool get maximumProcessing => (flags & emvTraceFlagMaximumProcessing) != 0;

  factory EmvTraceMeta.parse(Uint8List bytes) {
    if (bytes.length < 43) {
      throw const FormatException('Truncated EMV trace META response');
    }
    _requireVersion(bytes[0]);
    final data = ByteData.sublistView(bytes);
    final flags = data.getUint32(4, Endian.big);
    _requireKnownFlags(flags);
    final scanId = data.getUint32(8, Endian.big);
    final storedRecords = data.getUint32(12, Endian.big);
    final observedRecords = data.getUint32(16, Endian.big);
    final storedBytes = data.getUint32(20, Endian.big);
    final requiredBytes = data.getUint32(24, Endian.big);
    final firstDropped = data.getUint32(28, Endian.big);
    if (scanId == 0 || storedRecords > observedRecords) {
      throw const FormatException('Invalid EMV trace META counters');
    }
    if (storedBytes > requiredBytes) {
      throw const FormatException('Invalid EMV trace META byte counts');
    }
    final logTruncated = (flags & emvTraceFlagLogTruncated) != 0;
    if ((logTruncated && firstDropped >= observedRecords) ||
        (!logTruncated && firstDropped != _noDroppedRecord)) {
      throw const FormatException('Invalid EMV trace first-dropped marker');
    }

    var offset = 42;
    final uidLength = bytes[offset++];
    if (uidLength > 10 || offset + uidLength + 4 > bytes.length) {
      throw const FormatException('Invalid EMV trace UID length');
    }
    final uid = Uint8List.fromList(bytes.sublist(offset, offset + uidLength));
    offset += uidLength;
    final atqa = Uint8List.fromList(bytes.sublist(offset, offset + 2));
    offset += 2;
    final sak = bytes[offset++];
    final atsLength = bytes[offset++];
    if (offset + atsLength != bytes.length) {
      throw const FormatException('Invalid EMV trace ATS length');
    }

    return EmvTraceMeta(
      state: EmvTraceState.fromValue(bytes[1]),
      resultStatus: data.getUint16(2, Endian.big),
      flags: flags,
      scanId: scanId,
      storedRecords: storedRecords,
      observedRecords: observedRecords,
      storedBytes: storedBytes,
      requiredBytes: requiredBytes,
      firstDropped: firstDropped,
      crc32: data.getUint32(32, Endian.big),
      applicationCount: data.getUint16(36, Endian.big),
      elapsedMs: data.getUint32(38, Endian.big),
      uid: uid,
      atqa: atqa,
      sak: sak,
      ats: Uint8List.fromList(bytes.sublist(offset)),
    );
  }

  Map<String, Object?> toJson() => {
        'version': emvTraceProtocolVersion,
        'state': state.label,
        'stateValue': state.value,
        'resultStatus': resultStatus,
        'flags': flags,
        'scanId': scanId,
        'storedRecords': storedRecords,
        'observedRecords': observedRecords,
        'storedBytes': storedBytes,
        'requiredBytes': requiredBytes,
        'firstDropped': firstDropped,
        'crc32': crc32,
        'applicationCount': applicationCount,
        'elapsedMs': elapsedMs,
        'uidHex': _hex(uid),
        'atqaHex': _hex(atqa),
        'sak': sak,
        'atsHex': _hex(ats),
      };
}

sealed class EmvTraceRecordPayload {
  const EmvTraceRecordPayload();

  Map<String, Object?> toJson();
}

class EmvTraceRfPayload extends EmvTraceRecordPayload {
  const EmvTraceRfPayload({
    required this.direction,
    required this.bitLength,
    required this.data,
  });

  final int direction;
  final int bitLength;
  final Uint8List data;

  bool get readerToCard => direction == 0;

  @override
  Map<String, Object?> toJson() => {
        'direction': direction,
        'directionName': readerToCard ? 'readerToCard' : 'cardToReader',
        'bitLength': bitLength,
        'dataHex': _hex(data),
      };
}

class EmvTraceApduPayload extends EmvTraceRecordPayload {
  const EmvTraceApduPayload({
    required this.statusWord,
    required this.command,
    required this.response,
  });

  final int statusWord;
  final Uint8List command;
  final Uint8List response;

  @override
  Map<String, Object?> toJson() => {
        'statusWord': statusWord,
        'commandHex': _hex(command),
        'responseHex': _hex(response),
      };
}

class EmvTraceApplicationPayload extends EmvTraceRecordPayload {
  const EmvTraceApplicationPayload({
    required this.aid,
    required this.priority,
  });

  final Uint8List aid;
  final int priority;

  @override
  Map<String, Object?> toJson() => {
        'aidHex': _hex(aid),
        'priority': priority,
      };
}

class EmvTraceSummaryPayload extends EmvTraceRecordPayload {
  const EmvTraceSummaryPayload({
    required this.storedRecordsBeforeSummary,
    required this.observedRecordsBeforeSummary,
    required this.flags,
  });

  final int storedRecordsBeforeSummary;
  final int observedRecordsBeforeSummary;
  final int flags;

  @override
  Map<String, Object?> toJson() => {
        'storedRecordsBeforeSummary': storedRecordsBeforeSummary,
        'observedRecordsBeforeSummary': observedRecordsBeforeSummary,
        'flags': flags,
      };
}

class EmvTraceRecord {
  const EmvTraceRecord({
    required this.type,
    required this.sequence,
    required this.stage,
    required this.applicationIndex,
    required this.attempt,
    required this.flags,
    required this.status,
    required this.timestampMs,
    required this.payloadBytes,
    required this.payload,
    required this.rawBytes,
  });

  final EmvTraceRecordType type;
  final int sequence;
  final int stage;
  final int applicationIndex;
  final int attempt;
  final int flags;
  final int status;
  final int timestampMs;
  final Uint8List payloadBytes;
  final EmvTraceRecordPayload payload;
  final Uint8List rawBytes;

  String get stageName => emvTraceStageNames[stage]!;

  static EmvTraceRecord parse(Uint8List bytes) {
    if (bytes.length < 18) {
      throw const FormatException('Truncated EMV trace record');
    }
    final data = ByteData.sublistView(bytes);
    final bodyLength = data.getUint16(0, Endian.big);
    if (bodyLength < 16 || bodyLength + 2 != bytes.length) {
      throw const FormatException('Invalid EMV trace record length');
    }
    _requireVersion(bytes[2]);
    final type = EmvTraceRecordType.fromValue(bytes[3]);
    final stage = bytes[8];
    if (!emvTraceStageNames.containsKey(stage) ||
        (type == EmvTraceRecordType.summary && stage != 0xff) ||
        (type != EmvTraceRecordType.summary && stage == 0xff)) {
      throw FormatException('Invalid EMV trace stage $stage for ${type.label}');
    }
    final payloadBytes = Uint8List.fromList(bytes.sublist(18));
    final payload = _parsePayload(type, payloadBytes);
    return EmvTraceRecord(
      type: type,
      sequence: data.getUint32(4, Endian.big),
      stage: stage,
      applicationIndex: bytes[9],
      attempt: bytes[10],
      flags: bytes[11],
      status: data.getUint16(12, Endian.big),
      timestampMs: data.getUint32(14, Endian.big),
      payloadBytes: payloadBytes,
      payload: payload,
      rawBytes: Uint8List.fromList(bytes),
    );
  }

  static EmvTraceRecordPayload _parsePayload(
      EmvTraceRecordType type, Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    switch (type) {
      case EmvTraceRecordType.rf:
        if (bytes.length < 5 || bytes[0] > 1) {
          throw const FormatException('Invalid EMV trace RF payload');
        }
        final dataLength = data.getUint16(3, Endian.big);
        if (bytes.length != 5 + dataLength) {
          throw const FormatException('Invalid EMV trace RF data length');
        }
        return EmvTraceRfPayload(
          direction: bytes[0],
          bitLength: data.getUint16(1, Endian.big),
          data: Uint8List.fromList(bytes.sublist(5)),
        );
      case EmvTraceRecordType.apdu:
        if (bytes.length < 6) {
          throw const FormatException('Truncated EMV trace APDU payload');
        }
        final commandLength = data.getUint16(2, Endian.big);
        final responseLength = data.getUint16(4, Endian.big);
        if (bytes.length != 6 + commandLength + responseLength) {
          throw const FormatException('Invalid EMV trace APDU lengths');
        }
        final statusWord = data.getUint16(0, Endian.big);
        final response = Uint8List.fromList(bytes.sublist(6 + commandLength));
        final expectedStatus = response.length >= 2
            ? (response[response.length - 2] << 8) | response.last
            : 0xffff;
        if (statusWord != expectedStatus) {
          throw const FormatException('Inconsistent EMV trace status word');
        }
        return EmvTraceApduPayload(
          statusWord: statusWord,
          command: Uint8List.fromList(bytes.sublist(6, 6 + commandLength)),
          response: response,
        );
      case EmvTraceRecordType.application:
        if (bytes.length < 2 || bytes[0] < 5 || bytes[0] > 16) {
          throw const FormatException('Invalid EMV trace application payload');
        }
        final aidLength = bytes[0];
        if (bytes.length != aidLength + 2) {
          throw const FormatException('Invalid EMV trace AID length');
        }
        return EmvTraceApplicationPayload(
          aid: Uint8List.fromList(bytes.sublist(1, 1 + aidLength)),
          priority: bytes.last,
        );
      case EmvTraceRecordType.summary:
        if (bytes.length != 12) {
          throw const FormatException('Invalid EMV trace summary length');
        }
        final flags = data.getUint32(8, Endian.big);
        _requireKnownFlags(flags);
        return EmvTraceSummaryPayload(
          storedRecordsBeforeSummary: data.getUint32(0, Endian.big),
          observedRecordsBeforeSummary: data.getUint32(4, Endian.big),
          flags: flags,
        );
    }
  }

  Map<String, Object?> toJson() => {
        'version': emvTraceProtocolVersion,
        'type': type.label,
        'typeValue': type.value,
        'sequence': sequence,
        'stage': stage,
        'stageName': stageName,
        'applicationIndex': applicationIndex,
        'attempt': attempt,
        'flags': flags,
        'status': status,
        'timestampMs': timestampMs,
        'payloadHex': _hex(payloadBytes),
        'payload': payload.toJson(),
        'rawRecordHex': _hex(rawBytes),
      };
}

class EmvTracePage {
  const EmvTracePage({
    required this.flags,
    required this.scanId,
    required this.startRecord,
    required this.nextRecord,
    required this.recordBytes,
    required this.records,
  });

  final int flags;
  final int scanId;
  final int startRecord;
  final int nextRecord;
  final Uint8List recordBytes;
  final List<EmvTraceRecord> records;

  bool get hasMore => (flags & 0x01) != 0;
  bool get isEnd => (flags & 0x02) != 0;
  bool get logTruncated => (flags & 0x04) != 0;

  factory EmvTracePage.parse(Uint8List bytes) {
    if (bytes.length < 18) {
      throw const FormatException('Truncated EMV trace GET response');
    }
    _requireVersion(bytes[0]);
    final flags = bytes[1];
    if ((flags & ~0x07) != 0 ||
        ((flags & 0x03) != 0x01 && (flags & 0x03) != 0x02)) {
      throw const FormatException('Invalid EMV trace page flags');
    }
    final data = ByteData.sublistView(bytes);
    final scanId = data.getUint32(2, Endian.big);
    final start = data.getUint32(6, Endian.big);
    final next = data.getUint32(10, Endian.big);
    final count = data.getUint16(14, Endian.big);
    final byteLength = data.getUint16(16, Endian.big);
    if (scanId == 0 ||
        bytes.length != 18 + byteLength ||
        next != start + count) {
      throw const FormatException('Invalid EMV trace page header');
    }

    final recordBytes = Uint8List.fromList(bytes.sublist(18));
    final records = <EmvTraceRecord>[];
    var offset = 0;
    while (offset < recordBytes.length) {
      if (recordBytes.length - offset < 2) {
        throw const FormatException('Truncated EMV trace record prefix');
      }
      final bodyLength = ByteData.sublistView(recordBytes, offset, offset + 2)
          .getUint16(0, Endian.big);
      final end = offset + bodyLength + 2;
      if (bodyLength < 16 || end > recordBytes.length) {
        throw const FormatException('Invalid EMV trace page record length');
      }
      records.add(EmvTraceRecord.parse(
          Uint8List.fromList(recordBytes.sublist(offset, end))));
      offset = end;
    }
    if (records.length != count) {
      throw const FormatException('EMV trace page record count mismatch');
    }
    if (count == 0) {
      throw const FormatException('EMV trace page made no cursor progress');
    }

    return EmvTracePage(
      flags: flags,
      scanId: scanId,
      startRecord: start,
      nextRecord: next,
      recordBytes: recordBytes,
      records: List.unmodifiable(records),
    );
  }
}

class EmvTraceCapture {
  const EmvTraceCapture._({
    required this.meta,
    required this.pages,
    required this.records,
    required this.recordBytes,
  });

  final EmvTraceMeta meta;
  final List<EmvTracePage> pages;
  final List<EmvTraceRecord> records;
  final Uint8List recordBytes;

  Iterable<EmvTraceRecord> get apduRecords =>
      records.where((record) => record.type == EmvTraceRecordType.apdu);
  Iterable<EmvTraceRecord> get rfRecords =>
      records.where((record) => record.type == EmvTraceRecordType.rf);
  Iterable<EmvTraceRecord> get applicationRecords =>
      records.where((record) => record.type == EmvTraceRecordType.application);

  factory EmvTraceCapture.assemble(
      EmvTraceMeta meta, List<EmvTracePage> pages) {
    final records = <EmvTraceRecord>[];
    final builder = BytesBuilder(copy: false);
    var cursor = 0;
    int? previousSequence;
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      if (page.scanId != meta.scanId || page.startRecord != cursor) {
        throw const FormatException('EMV trace page session/cursor mismatch');
      }
      final shouldHaveMore = page.nextRecord < meta.storedRecords;
      if (page.hasMore != shouldHaveMore || page.isEnd == shouldHaveMore) {
        throw const FormatException('EMV trace page termination mismatch');
      }
      if (page.logTruncated != ((meta.flags & emvTraceFlagLogTruncated) != 0)) {
        throw const FormatException('EMV trace page truncation mismatch');
      }
      for (final record in page.records) {
        if (record.sequence >= meta.observedRecords ||
            (previousSequence != null && record.sequence <= previousSequence)) {
          throw const FormatException('Invalid EMV trace record sequence');
        }
        previousSequence = record.sequence;
      }
      records.addAll(page.records);
      builder.add(page.recordBytes);
      cursor = page.nextRecord;
    }
    if (cursor != meta.storedRecords || records.length != meta.storedRecords) {
      throw const FormatException('Incomplete EMV trace page set');
    }
    final bytes = builder.takeBytes();
    if (bytes.length != meta.storedBytes) {
      throw const FormatException('EMV trace stored-byte count mismatch');
    }
    if (emvTraceCrc32(bytes) != meta.crc32) {
      throw const FormatException('EMV trace CRC-32 mismatch');
    }
    return EmvTraceCapture._(
      meta: meta,
      pages: List.unmodifiable(pages),
      records: List.unmodifiable(records),
      recordBytes: bytes,
    );
  }

  Map<String, Object?> toJson() => {
        'protocol': 'chameleon-emv-trace',
        'version': emvTraceProtocolVersion,
        'meta': meta.toJson(),
        'recordStreamHex': _hex(recordBytes),
        'records': records.map((record) => record.toJson()).toList(),
      };
}

int emvTraceCrc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (~crc) & 0xffffffff;
}

Uint8List encodeEmvTraceSessionRequest(int scanId) {
  if (scanId <= 0 || scanId > 0xffffffff) {
    throw ArgumentError.value(scanId, 'scanId', 'must be 1..0xffffffff');
  }
  final output = Uint8List(5)..[0] = emvTraceProtocolVersion;
  ByteData.sublistView(output).setUint32(1, scanId, Endian.big);
  return output;
}

Uint8List encodeEmvTraceGetRequest(
    int scanId, int startRecord, int maxPayload) {
  if (startRecord < 0 || startRecord > 0xffffffff) {
    throw ArgumentError.value(
        startRecord, 'startRecord', 'must be 0..0xffffffff');
  }
  if (maxPayload < 48 || maxPayload > 4096) {
    throw ArgumentError.value(maxPayload, 'maxPayload', 'must be 48..4096');
  }
  final output = Uint8List(11);
  output.setRange(0, 5, encodeEmvTraceSessionRequest(scanId));
  final data = ByteData.sublistView(output);
  data.setUint32(5, startRecord, Endian.big);
  data.setUint16(9, maxPayload, Endian.big);
  return output;
}

void _requireVersion(int version) {
  if (version != emvTraceProtocolVersion) {
    throw FormatException('Unsupported EMV trace version $version');
  }
}

void _requireKnownFlags(int flags) {
  if ((flags & ~_knownTraceFlags) != 0) {
    throw FormatException(
        'Unknown EMV trace flags 0x${flags.toRadixString(16)}');
  }
}

void _requireLength(Uint8List bytes, int length, String name) {
  if (bytes.length != length) {
    throw ArgumentError.value(bytes.length, name, 'must be $length bytes');
  }
}

int _bcd(int value) => ((value ~/ 10) << 4) | (value % 10);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
