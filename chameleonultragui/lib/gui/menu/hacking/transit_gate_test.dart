import 'dart:convert';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/emv.dart';
import 'package:chameleonultragui/helpers/emv_trace.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/transit_gate.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class TransitGateTestPage extends StatefulWidget {
  const TransitGateTestPage({super.key});

  @override
  State<TransitGateTestPage> createState() => _TransitGateTestPageState();
}

class _TransitSessionResult {
  const _TransitSessionResult(
      this.profile, this.requestBytes, this.capture, this.assessment);

  final EmvTerminalProfile profile;
  final Uint8List requestBytes;
  final EmvTraceCapture capture;
  final TransitGateAssessment assessment;

  Map<String, Object?> toJson() => {
        'profile': profile.name,
        'ttq': profile.ttqHex,
        'startRequestHex': bytesToHex(requestBytes).toUpperCase(),
        'assessment': assessment.toJson(),
        'trace': capture.toJson(),
      };
}

class _TransitGateTestPageState extends State<TransitGateTestPage> {
  final _amount = TextEditingController(text: '0.10');
  final _customTtq = TextEditingController(text: '33804000');
  bool _busy = false;
  bool _runningTransaction = false;
  bool? _supported;
  int _pollAttempts = 3;
  int _currentAttempt = 0;
  int _cryptogramRequest = 0x80;
  EmvTerminalProfile _terminalProfile = EmvTerminalProfile.compatibilitySweep;
  EmvPollingProfile _pollingProfile = EmvPollingProfile.balanced;
  bool _directAidFallback = true;
  bool _adaptiveProfiles = true;
  bool _reacquireProfiles = true;
  bool _separateProfileSessions = false;
  String? _error;
  String? _replaySummary;
  Uint8List? _discoveryRequestBytes;
  EmvTraceCapture? _discoveryCapture;
  EmvTraceCapture? _transactionCapture;
  TransitGateAssessment? _assessment;
  List<_TransitSessionResult> _sessionResults = const [];

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCapabilities());
  }

  @override
  void dispose() {
    _amount.dispose();
    _customTtq.dispose();
    super.dispose();
  }

  Future<void> _loadCapabilities() async {
    try {
      final capabilities = await _app.communicator!.getDeviceCapabilities();
      if (!mounted) return;
      setState(() {
        _supported = const [
          ChameleonCommand.hf14a4EmvTraceStart,
          ChameleonCommand.hf14a4EmvTraceMeta,
          ChameleonCommand.hf14a4EmvTraceGet,
        ].every((command) => capabilities.contains(command.value));
      });
    } catch (_) {
      if (mounted) setState(() => _supported = false);
    }
  }

  Future<void> _ensureReaderMode() async {
    if (!await _app.communicator!.isReaderDeviceMode()) {
      await _app.communicator!.setReaderDeviceMode(true);
    }
  }

  Future<void> _runLockedDiscovery() async {
    setState(() {
      _busy = true;
      _runningTransaction = false;
      _currentAttempt = 0;
      _error = null;
      _discoveryRequestBytes = null;
      _discoveryCapture = null;
      _transactionCapture = null;
      _assessment = null;
      _sessionResults = const [];
      _replaySummary = null;
    });
    try {
      await _ensureReaderMode();
      EmvTraceCapture? lastCapture;
      TransitGateAssessment? lastAssessment;
      for (var attempt = 1; attempt <= _pollAttempts; attempt++) {
        if (mounted) setState(() => _currentAttempt = attempt);
        final request = EmvTraceRequest.readOnly(
          includeRf: true,
          expressTransit: true,
          pollingProfile: _pollingProfile,
          directAidFallback: _directAidFallback,
          maxAids: 16,
          maxRecords: 24,
          maxApdus: 160,
          budgetMs: 12000,
          country: Uint8List.fromList([0x08, 0x26]),
          currency: Uint8List.fromList([0x08, 0x26]),
        );
        final capture = await _app.communicator!.hf14a4EmvTrace(request);
        lastCapture = capture;
        _discoveryRequestBytes = request.encode();
        lastAssessment = assessTransitCapture(
          capture,
          transactionRequested: false,
        );
        if (lastAssessment.walletResponded) break;
        if (attempt < _pollAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
        }
      }
      if (!mounted) return;
      setState(() {
        _discoveryCapture = lastCapture;
        _assessment = lastAssessment;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runTransaction() async {
    late final Uint8List amount;
    try {
      amount = transitAmountBcd(_amount.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    var customTtq = const <int>[0, 0, 0, 0];
    if (_terminalProfile == EmvTerminalProfile.custom) {
      final value = _customTtq.text.trim();
      if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(value)) {
        setState(() => _error = 'Custom TTQ must be exactly 8 hex digits');
        return;
      }
      customTtq = [
        for (var i = 0; i < 8; i += 2)
          int.parse(value.substring(i, i + 2), radix: 16),
      ];
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Run one transit transaction attempt?'),
            content: const Text(
              'No prior locked-wallet test is required. Keep the phone locked and '
              'on your Chameleon antenna. This run performs ECP polling, discovers '
              'the wallet, sends GPO, and may request a cryptogram for every AID. It can '
              'try up to six terminal profiles, stopping after the first successful '
              'GPO, and may cycle the RF field between rejected profiles. It can '
              'advance ATC or wallet state. No issuer is contacted and no fare is '
              'approved. Use only your own or explicitly authorised phone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Run once'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final discoveredScheme = _assessment?.applications.firstOrNull?.scheme;
    setState(() {
      _busy = true;
      _runningTransaction = true;
      _currentAttempt = 0;
      _error = null;
      _replaySummary = null;
      _discoveryRequestBytes = null;
      _discoveryCapture = null;
      _transactionCapture = null;
      _assessment = null;
      _sessionResults = const [];
    });
    try {
      await _ensureReaderMode();
      final profiles = _separateProfileSessions &&
              _terminalProfile == EmvTerminalProfile.compatibilitySweep
          ? transitProfileOrder(discoveredScheme, adaptive: _adaptiveProfiles)
          : [_terminalProfile];
      final sessions = <_TransitSessionResult>[];
      for (var index = 0; index < profiles.length; index++) {
        if (mounted) setState(() => _currentAttempt = index + 1);
        final profile = profiles[index];
        final request = EmvTraceRequest(
          maximumProcessing: true,
          includeRf: true,
          expressTransit: true,
          terminalProfile: profile,
          customTtq: customTtq,
          pollingProfile: _pollingProfile,
          directAidFallback: _directAidFallback,
          adaptiveProfiles: !_separateProfileSessions && _adaptiveProfiles,
          reacquireBetweenProfiles:
              !_separateProfileSessions && _reacquireProfiles,
          usePdolFallback: false,
          scanRecordGrid: false,
          readTransactionLogs: false,
          maxAids: 16,
          maxRecords: 32,
          maxApdus: 320,
          budgetMs: 30000,
          amount: amount,
          country: Uint8List.fromList([0x08, 0x26]),
          currency: Uint8List.fromList([0x08, 0x26]),
          date: emvTraceDate(DateTime.now()),
          transactionType: 0x00,
          cryptogramType: _cryptogramRequest,
        );
        final capture = await _app.communicator!.hf14a4EmvTrace(request);
        final assessment = assessTransitCapture(
          capture,
          transactionRequested: true,
        );
        sessions.add(_TransitSessionResult(
            profile, request.encode(), capture, assessment));
        if (assessment.gpoSucceeded || index == profiles.length - 1) break;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      if (!mounted) return;
      final result = sessions.last;
      setState(() {
        _sessionResults = List.unmodifiable(sessions);
        _transactionCapture = result.capture;
        _assessment = result.assessment;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _runningTransaction = false;
        });
      }
    }
  }

  Future<void> _copyReport() async {
    final assessment = _assessment;
    final capture = _transactionCapture ?? _discoveryCapture;
    if (assessment == null || capture == null) return;
    final report = {
      'system': 'chameleon-transit-gate-lab',
      'notice':
          'Operator-declared lock state only. No issuer contact or payment approval.',
      'ecpProfile': {
        'version': 2,
        'terminalType': 'transit',
        'tci': '030002',
        'networkMask': '7900000000',
        'frame': '6A02C801000300027900000000C2D8',
      },
      'terminalProfile': {
        'requested': _terminalProfile.name,
        'fixedTtq': _terminalProfile == EmvTerminalProfile.custom
            ? _customTtq.text.trim().toUpperCase()
            : _terminalProfile.ttqHex,
        'visaSweepOrder':
            _terminalProfile == EmvTerminalProfile.compatibilitySweep
                ? const [
                    '33804000',
                    '32804000',
                    '26804000',
                    '3600C000',
                    '22804000',
                    'B600C000',
                  ]
                : null,
        'mastercardSweepOrder':
            _terminalProfile == EmvTerminalProfile.compatibilitySweep
                ? const [
                    '3600C000',
                    '26804000',
                    '33804000',
                    '32804000',
                    'B600C000',
                    '22804000',
                  ]
                : null,
        'otherSchemeSweepOrder':
            _terminalProfile == EmvTerminalProfile.compatibilitySweep
                ? const [
                    '26804000',
                    '3600C000',
                    '33804000',
                    '32804000',
                    '22804000',
                    'B600C000',
                  ]
                : null,
        'odaForOnlineMayBeAdvertised': true,
        'odaValidatedByLab': false,
        'issuerContacted': false,
        'adaptiveOrder': _adaptiveProfiles,
        'directAidFallback': _directAidFallback,
        'reacquireBetweenProfiles': _reacquireProfiles,
        'pollingProfile': _pollingProfile.name,
        'separateProfileSessions': _separateProfileSessions,
      },
      'sessions': _sessionResults.map((session) => session.toJson()).toList(),
      'assessment': assessment.toJson(),
      'trace': capture.toJson(),
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(report)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transit report copied')),
      );
    }
  }

  Future<void> _replayCopiedReport() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.trim().isEmpty) {
        throw const FormatException('Clipboard does not contain a report');
      }
      final replay = replayTransitReport(data.text!);
      if (!mounted) return;
      setState(() {
        _assessment = replay.assessment;
        _discoveryCapture = null;
        _transactionCapture = null;
        _sessionResults = const [];
        _error = null;
        _replaySummary =
            '${replay.recordCount} records | CRC-32 ${replay.crc32.toRadixString(16).padLeft(8, '0').toUpperCase()} verified';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Replay failed: $error');
    }
  }

  Color _gateColor(TransitGateAssessment assessment) {
    if (assessment.hasTransactionEvidence) return Colors.green.shade700;
    if (assessment.walletResponded) return Colors.amber.shade800;
    return Colors.red.shade800;
  }

  Widget _gateStatus(TransitGateAssessment assessment) {
    final capture = _transactionCapture ?? _discoveryCapture;
    final color = _gateColor(assessment);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                assessment.hasTransactionEvidence
                    ? Icons.check_circle
                    : assessment.walletResponded
                        ? Icons.contactless
                        : Icons.cancel,
                color: Colors.white,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  assessment.headline.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            assessment.explanation,
            style: const TextStyle(color: Colors.white, height: 1.35),
          ),
          if (capture != null) ...[
            const SizedBox(height: 10),
            Text(
              '${capture.meta.applicationCount} AIDs | '
              '${capture.meta.storedRecords}/${capture.meta.observedRecords} records | '
              '${capture.meta.elapsedMs} ms | CRC-32 verified',
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'RobotoMono',
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _applicationCard(TransitApplicationEvidence application) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Application ${application.index} | ${application.scheme}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(
              application.aid,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text(application.gpoSucceeded
                      ? 'GPO 9000'
                      : application.gpoStatusWord == null
                          ? 'GPO not sent'
                          : 'GPO SW ${application.gpoStatusWord!.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
                ),
                Chip(
                    label:
                        Text('GPO attempts ${application.gpoCommands.length}')),
                if (application.generateAcAttempted)
                  const Chip(label: Text('GENERATE AC sent')),
                if (application.cryptogramType != null)
                  Chip(label: Text(application.cryptogramType!)),
              ],
            ),
            if (application.cryptogram != null)
              SelectableText(
                'Cryptogram ${application.cryptogram}',
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
              ),
            if (!application.gpoSucceeded && application.gpoStatusText != null)
              Text('GPO: ${application.gpoStatusText}'),
            if (application.gpoAttempts.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('PROFILE COMPARISON',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              for (final attempt in application.gpoAttempts)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    '#${attempt.index}  TTQ ${attempt.ttq ?? 'custom/undetected'}  '
                    'SW ${attempt.statusWord?.toRadixString(16).padLeft(4, '0').toUpperCase() ?? 'none'}  '
                    '${attempt.statusText} | ${attempt.recommendation}',
                    style: TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 11,
                      color: attempt.succeeded ? Colors.green.shade700 : null,
                    ),
                  ),
                ),
            ],
            if (application.cvmResults != null)
              Text('CVM results: ${application.cvmResults}'),
            if (application.cardTransactionQualifiers != null)
              Text('CTQ: ${application.cardTransactionQualifiers}'),
            Text('ODA: ${application.oda.status}'),
          ],
        ),
      ),
    );
  }

  List<
      ({
        String label,
        Uint8List? requestBytes,
        EmvTraceCapture capture,
      })> _visibleCaptures() {
    if (_sessionResults.isNotEmpty) {
      return [
        for (var index = 0; index < _sessionResults.length; index++)
          (
            label:
                'Session ${index + 1}: ${_sessionResults[index].profile.label}',
            requestBytes: _sessionResults[index].requestBytes,
            capture: _sessionResults[index].capture,
          ),
      ];
    }
    final capture = _transactionCapture ?? _discoveryCapture;
    if (capture == null) return const [];
    return [
      (
        label: _transactionCapture == null
            ? 'Locked-wallet discovery'
            : 'Transit transaction',
        requestBytes: _discoveryRequestBytes,
        capture: capture,
      ),
    ];
  }

  Widget _fullRawTrace(
      List<
              ({
                String label,
                Uint8List? requestBytes,
                EmvTraceCapture capture,
              })>
          sessions) {
    final recordCount = sessions.fold<int>(
        0, (total, session) => total + session.capture.records.length);
    return ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Full raw trace'),
      subtitle: Text(
          '${sessions.length} session(s) | $recordCount retained records | no byte elision'),
      children: [
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Sensitive evidence: raw EMV data may contain payment identifiers. '
              'Keep it local and disclose it only within the authorised lab.',
            ),
          ),
        ),
        for (final session in sessions) ...[
          ListTile(
            title: Text(session.label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'scan ${session.capture.meta.scanId} | '
              '${session.capture.records.length} records | '
              '${session.capture.recordBytes.length} bytes | '
              '${session.capture.meta.elapsedMs} ms',
            ),
          ),
          _controlTrace(session.requestBytes, session.capture),
          for (final record in session.capture.records) _rawRecord(record),
        ],
      ],
    );
  }

  Widget _controlTrace(Uint8List? requestBytes, EmvTraceCapture capture) {
    final lines = <String>[
      if (requestBytes != null)
        'TX CMD 6007 EMV_TRACE_START data [${requestBytes.length}]: ${_hexBytes(requestBytes)}',
      if (capture.start != null)
        'RX CMD 6007 data [${capture.start!.rawBytes.length}]: ${_hexBytes(capture.start!.rawBytes)}',
      'TX CMD 6008 EMV_TRACE_META data [5]: ${_hexBytes(encodeEmvTraceSessionRequest(capture.meta.scanId))}',
      'RX CMD 6008 data [${capture.meta.rawBytes.length}]: ${_hexBytes(capture.meta.rawBytes)}',
      for (final page in capture.pages) ...[
        'TX CMD 6009 EMV_TRACE_GET data [11]: ${_hexBytes(encodeEmvTraceGetRequest(capture.meta.scanId, page.startRecord, 4096))}',
        'RX CMD 6009 data [${page.rawBytes.length}]: ${_hexBytes(page.rawBytes)}',
      ],
    ];
    return ExpansionTile(
      title: const Text('Chameleon command transport'),
      subtitle: const Text(
          'Command IDs and complete data payloads; SOF/LRC framing is not retained'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SelectableText(
            lines.join('\n\n'),
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _rawRecord(EmvTraceRecord record) {
    final payload = record.payload;
    final details = <String>[
      'sequence=${record.sequence}  type=${record.type.label}  stage=${record.stageName}',
      'application=${record.applicationIndex}  attempt=${record.attempt}  '
          'flags=0x${record.flags.toRadixString(16).padLeft(2, '0').toUpperCase()}  '
          'status=0x${record.status.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      'timestamp=${record.timestampMs} ms',
    ];
    if (payload is EmvTraceRfPayload) {
      details.add(
          'RF ${payload.readerToCard ? 'PCD -> PICC (sent)' : 'PICC -> PCD (received)'}  '
          '${payload.bitLength} bits  ${payload.data.length} bytes');
      details.add('FRAME: ${_hexBytes(payload.data)}');
    } else if (payload is EmvTraceApduPayload) {
      details.add('C-APDU SENT [${payload.command.length}]: '
          '${_hexBytes(payload.command)}');
      details.add('R-APDU RECEIVED [${payload.response.length}]: '
          '${_hexBytes(payload.response)}');
      details.add(
          'SW=${_hexWord(payload.statusWord)} (${emvStatusText(payload.statusWord)})');
    } else if (payload is EmvTraceApplicationPayload) {
      details.add('AID [${payload.aid.length}]: ${_hexBytes(payload.aid)}');
      details.add('priority=${payload.priority}');
    } else if (payload is EmvTraceSummaryPayload) {
      details.add('storedBeforeSummary=${payload.storedRecordsBeforeSummary}  '
          'observedBeforeSummary=${payload.observedRecordsBeforeSummary}  '
          'summaryFlags=0x${payload.flags.toRadixString(16).padLeft(8, '0').toUpperCase()}');
    }
    details.add('PAYLOAD [${record.payloadBytes.length}]: '
        '${_hexBytes(record.payloadBytes)}');
    details.add(
        'RAW RECORD [${record.rawBytes.length}]: ${_hexBytes(record.rawBytes)}');

    return ExpansionTile(
      dense: true,
      title: Text(
          '#${record.sequence} ${record.type.label} | ${record.stageName}'),
      subtitle:
          Text('${record.timestampMs} ms | app ${record.applicationIndex}'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SelectableText(
            details.join('\n'),
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _decodeTrace(
      List<
              ({
                String label,
                Uint8List? requestBytes,
                EmvTraceCapture capture,
              })>
          sessions) {
    return ExpansionTile(
      title: const Text('Descifrar traza'),
      subtitle: const Text('ISO 14443, ISO-DEP, APDU, SW and EMV BER-TLV'),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '“Descifrar” here means deterministic protocol decoding. The lab '
              'does not decrypt or cryptographically validate ARQC, TC, IAD, '
              'certificates, or issuer data without the required trusted keys.',
            ),
          ),
        ),
        for (final session in sessions) ...[
          ListTile(
            title: Text(session.label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              emvProtocolSummary(
                session.capture.meta.uid,
                session.capture.meta.atqa,
                session.capture.meta.sak,
                session.capture.meta.ats,
              ),
            ),
          ),
          _decodedApplications(session.capture),
          for (final record in session.capture.rfRecords)
            if (decodeTransitRfFrame(record).isNotEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.sensors),
                title: Text(
                    '#${record.sequence} ${record.payload is EmvTraceRfPayload && (record.payload as EmvTraceRfPayload).readerToCard ? 'TX' : 'RX'} ${record.stageName}'),
                subtitle: SelectableText(
                  decodeTransitRfFrame(record).join('\n'),
                  style:
                      const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
                ),
              ),
          for (final record in session.capture.apduRecords)
            _decodedApdu(record),
        ],
      ],
    );
  }

  Widget _decodedApplications(EmvTraceCapture capture) {
    final applications = decodeTransitTrace(capture.records);
    if (applications.isEmpty) {
      return const ListTile(title: Text('No logical APDU data to decode'));
    }
    return Column(
      children: [
        for (final application in applications)
          if (application.fields.isNotEmpty ||
              application.aip != null ||
              application.cryptogram.isNotEmpty)
            ExpansionTile(
              title:
                  Text('Decoded fields | app ${application.applicationIndex}'),
              subtitle: Text('${application.apdus.length} logical APDUs'),
              children: [
                if (application.fields.isNotEmpty)
                  _decodedMap('Known EMV fields', application.fields),
                if (application.aip case final aip?)
                  _decodedMap('AIP ${aip.raw}', {
                    'Relay resistance': switch (
                        emvAssessRrp(aip, application.aid)) {
                      EmvRrpAssessment.advertised => 'RRP advertised',
                      EmvRrpAssessment.notAdvertised =>
                        'Mastercard RRP not advertised',
                      EmvRrpAssessment.notApplicable =>
                        'Mastercard RRP indicator not applicable',
                      EmvRrpAssessment.unknownScheme =>
                        'Unknown; application AID unavailable',
                    },
                    'DDA': aip.dda ? 'advertised' : 'not advertised',
                    'CDA': aip.cda ? 'advertised' : 'not advertised',
                    'Features': aip.features.isEmpty
                        ? 'none decoded'
                        : aip.features.join('; '),
                  }),
                if (application.cryptogram.isNotEmpty)
                  _decodedMap('Cryptogram structure', application.cryptogram),
              ],
            ),
      ],
    );
  }

  Widget _decodedMap(String title, Map<String, String> values) {
    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: SelectableText(
        values.entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join('\n'),
        style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
      ),
    );
  }

  Widget _decodedApdu(EmvTraceRecord record) {
    final payload = record.payload as EmvTraceApduPayload;
    final trace = emvBuildTrace([(payload.command, payload.response)]).single;
    final command = payload.command;
    final lines = <String>[
      if (command.length >= 4)
        'CLA=${_hexByte(command[0])}  INS=${_hexByte(command[1])}  '
            'P1=${_hexByte(command[2])}  P2=${_hexByte(command[3])}',
      ...trace.commandDetails,
      'Status: SW ${trace.statusWord == null ? 'none' : _hexWord(trace.statusWord!)} '
          '(${trace.statusText})',
      if (trace.responseTlvs.isEmpty && trace.responseBody.isNotEmpty)
        'Response body is not a recognised BER-TLV structure.',
      for (final tlv in trace.responseTlvs)
        '${'  ' * tlv.depth}${tlv.tag} ${emvTagName(tlv.tag)} '
            '[${tlv.value.length}]${tlv.constructed ? ' (constructed)' : ''}: '
            '${_hexBytes(tlv.value)}',
    ];
    return ExpansionTile(
      dense: true,
      title: Text('#${record.sequence} ${trace.name}'),
      subtitle: Text(
          '${record.stageName} | SW ${_hexWord(payload.statusWord)} | ${record.timestampMs} ms'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SelectableText(
            lines.join('\n'),
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _instructions() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LOCKED-PHONE PROCEDURE',
              style:
                  TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          SizedBox(height: 8),
          Text('1. Close the wallet and lock the phone yourself.'),
          Text('2. Keep the screen off; do not authenticate during the test.'),
          Text('3. Approach the Chameleon antenna.'),
          Text(
              '4. Run the transaction directly, or use the optional discovery-only test first.'),
          SizedBox(height: 8),
          Text(
            'NFC cannot attest the phone lock state. A positive result means the '
            'wallet responded under the operator-declared conditions. London-style '
            'open-loop transit normally uses back-office/deferred authorization; '
            'the compatibility profile advertises ODA-for-online, but this lab does '
            'not validate ODA or reproduce the transport operator or issuer.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final assessment = _assessment;
    final capture = _transactionCapture ?? _discoveryCapture;
    final visibleCaptures = _visibleCaptures();
    final apduCount = visibleCaptures.fold<int>(
        0, (total, session) => total + session.capture.apduRecords.length);
    final rfCount = visibleCaptures.fold<int>(
        0, (total, session) => total + session.capture.rfRecords.length);
    final ecpCount = visibleCaptures.fold<int>(
        0, (total, session) => total + _ecpFrameCount(session.capture));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transit gate lab'),
        actions: [
          IconButton(
            tooltip: 'Replay copied transit report',
            onPressed: _replayCopiedReport,
            icon: const Icon(Icons.replay),
          ),
          if (assessment != null && capture != null)
            IconButton(
              tooltip: 'Copy verified report',
              onPressed: _copyReport,
              icon: const Icon(Icons.data_object),
            ),
        ],
      ),
      body: !_connected && assessment == null
          ? Center(child: Text(localizations.no_device))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _instructions(),
                  const SizedBox(height: 14),
                  if (_supported == false)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Firmware commands 6007-6009 are required. Update the '
                          'firmware; legacy command 6005 is intentionally not used '
                          'because it cannot provide a safe read-only first phase.',
                        ),
                      ),
                    ),
                  if (_replaySummary != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('Offline replay | $_replaySummary'),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _pollAttempts,
                          decoration: const InputDecoration(
                            labelText: 'Polling windows',
                            border: OutlineInputBorder(),
                          ),
                          items: const [3, 5, 10]
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value x 3 seconds'),
                                  ))
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) =>
                                  setState(() => _pollAttempts = value ?? 3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy || _supported != true
                              ? null
                              : _runLockedDiscovery,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.nfc),
                          label: Text(_busy &&
                                  !_runningTransaction &&
                                  _currentAttempt > 0
                              ? 'Polling $_currentAttempt/$_pollAttempts'
                              : 'Test locked wallet'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _amount,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Transit amount',
                            suffixText: 'GBP',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _cryptogramRequest,
                          decoration: const InputDecoration(
                            labelText: 'Cryptogram request',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 0x40,
                              child: Text('TC (offline)'),
                            ),
                            DropdownMenuItem(
                              value: 0x80,
                              child: Text('ARQC (deferred online)'),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => setState(
                                    () => _cryptogramRequest = value ?? 0x80,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<EmvTerminalProfile>(
                    initialValue: _terminalProfile,
                    decoration: const InputDecoration(
                      labelText: 'Terminal compatibility profile',
                      helperText:
                          'Sweep retries only 6985, 6986, or 6A80 and stops on success.',
                      border: OutlineInputBorder(),
                    ),
                    items: EmvTerminalProfile.values
                        .map((profile) => DropdownMenuItem(
                              value: profile,
                              child: Text(profile.ttqHex == null
                                  ? profile.label
                                  : '${profile.label} (${profile.ttqHex})'),
                            ))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _terminalProfile =
                            value ?? EmvTerminalProfile.compatibilitySweep),
                  ),
                  if (_terminalProfile == EmvTerminalProfile.custom) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customTtq,
                      enabled: !_busy,
                      maxLength: 8,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Custom TTQ',
                        helperText:
                            'Exactly four bytes as 8 hexadecimal digits.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<EmvPollingProfile>(
                    initialValue: _pollingProfile,
                    decoration: const InputDecoration(
                      labelText: 'ECP polling strategy',
                      border: OutlineInputBorder(),
                    ),
                    items: EmvPollingProfile.values
                        .map((profile) => DropdownMenuItem(
                              value: profile,
                              child: Text(profile.label),
                            ))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _pollingProfile =
                            value ?? EmvPollingProfile.balanced),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _adaptiveProfiles,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _adaptiveProfiles = value),
                    title: const Text('Scheme-adaptive profile order'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _separateProfileSessions,
                    onChanged: _busy
                        ? null
                        : (value) =>
                            setState(() => _separateProfileSessions = value),
                    title:
                        const Text('Run each profile in a separate RF session'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _reacquireProfiles,
                    onChanged: _busy || _separateProfileSessions
                        ? null
                        : (value) => setState(() => _reacquireProfiles = value),
                    title: const Text(
                        'Reacquire wallet between rejected profiles'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _directAidFallback,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _directAidFallback = value),
                    title: const Text(
                        'Known payment-AID fallback when PPSE is empty'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy || !_connected || _supported != true
                        ? null
                        : _runTransaction,
                    icon: _runningTransaction
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.directions_subway),
                    label: Text(_runningTransaction && _currentAttempt > 0
                        ? 'Running transaction session $_currentAttempt'
                        : 'Run transit transaction directly'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (assessment != null) ...[
                    const SizedBox(height: 16),
                    _gateStatus(assessment),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('APDUs $apduCount')),
                        Chip(label: Text('RF frames $rfCount')),
                        Chip(label: Text('ECP2 frames $ecpCount')),
                        if (_sessionResults.isNotEmpty)
                          Chip(
                              label:
                                  Text('Sessions ${_sessionResults.length}')),
                        if (capture?.meta.isTruncated == true)
                          const Chip(label: Text('Trace truncated')),
                        Chip(
                          label: Text(assessment.ppseSucceeded
                              ? 'PPSE 9000'
                              : 'PPSE unavailable'),
                        ),
                        Chip(
                          label: Text(assessment.gpoSucceeded
                              ? 'GPO 9000'
                              : 'No successful GPO'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...assessment.applications.map(_applicationCard),
                    if (visibleCaptures.isNotEmpty) ...[
                      _fullRawTrace(visibleCaptures),
                      _decodeTrace(visibleCaptures),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

int _ecpFrameCount(EmvTraceCapture capture) {
  const frame = [
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
  return capture.rfRecords.where((record) {
    final payload = record.payload;
    if (payload is! EmvTraceRfPayload ||
        payload.direction != 0 ||
        payload.data.length != frame.length) {
      return false;
    }
    for (var i = 0; i < frame.length; i++) {
      if (payload.data[i] != frame[i]) return false;
    }
    return true;
  }).length;
}

String _hexBytes(List<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

String _hexByte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();

String _hexWord(int value) =>
    value.toRadixString(16).padLeft(4, '0').toUpperCase();
