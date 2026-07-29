import 'dart:convert';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/relay_assessment.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/emv.dart';
import 'package:chameleonultragui/helpers/emv_trace.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class _EmvResult {
  final String uid;
  final String protocol;
  final String sak;
  final String atqa;
  final String ats;
  final List<EmvApduTrace> traces;
  final Map<String, String> fields;
  final List<EmvTlv> tlvs;
  final EmvAip? aip;
  final EmvTraceCapture? capture;
  final Map<int, String> applicationAids;
  final Map<int, List<EmvApduTrace>> applicationTraces;
  final Map<int, Map<String, String>> applicationFields;

  _EmvResult(
    this.uid,
    this.protocol,
    this.sak,
    this.atqa,
    this.ats,
    this.traces,
    this.fields,
    this.tlvs,
    this.aip, {
    this.capture,
    this.applicationAids = const {},
    this.applicationTraces = const {},
    this.applicationFields = const {},
  });
}

// Read an EMV contactless card (PPSE -> AID -> GPO -> READ RECORDs) and extract
// as many fields as possible via a full BER-TLV parse (see helpers/emv.dart).
class EmvReaderPage extends StatefulWidget {
  const EmvReaderPage({super.key});

  @override
  EmvReaderPageState createState() => EmvReaderPageState();
}

class EmvReaderPageState extends State<EmvReaderPage> {
  bool _busy = false;
  bool _maximumProcessing = false;
  bool? _traceSupported;
  int _selectedApplication = -1;
  String? _error;
  _EmvResult? _result;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCapabilities());
  }

  Future<void> _loadCapabilities() async {
    try {
      final capabilities = await _app.communicator!.getDeviceCapabilities();
      if (!mounted) return;
      setState(() {
        _traceSupported = const [
          ChameleonCommand.hf14a4EmvTraceStart,
          ChameleonCommand.hf14a4EmvTraceMeta,
          ChameleonCommand.hf14a4EmvTraceGet,
        ].every((command) => capabilities.contains(command.value));
      });
    } catch (_) {
      if (mounted) setState(() => _traceSupported = null);
    }
  }

  _EmvResult _parseLegacy(Uint8List d) {
    final scan = parseEmvScanBuffer(d); // bounds-checked; throws on truncation
    final traces = emvBuildTrace(scan.apdus);
    final tlvs = traces.expand((t) => t.responseTlvs).toList();
    final leaf = emvLeafMapFromTrace(traces); // shared by fields + AIP
    return _EmvResult(
      bytesToHexSpace(scan.uid).toUpperCase(),
      emvProtocolSummary(scan.uid, scan.atqa, scan.sak, scan.ats),
      scan.sak.toRadixString(16).padLeft(2, '0').toUpperCase(),
      bytesToHexSpace(scan.atqa).toUpperCase(),
      scan.ats.isEmpty ? '-' : bytesToHexSpace(scan.ats).toUpperCase(),
      traces,
      emvExtractFields(leaf),
      tlvs,
      emvDecodeAip(leaf),
    );
  }

  _EmvResult _parseTrace(EmvTraceCapture capture) {
    final groupedApdus = <int, List<(Uint8List, Uint8List)>>{};
    final aids = <int, String>{};
    for (final record in capture.records) {
      if (record.payload case final EmvTraceApduPayload apdu) {
        groupedApdus
            .putIfAbsent(record.applicationIndex, () => [])
            .add((apdu.command, apdu.response));
      } else if (record.payload case final EmvTraceApplicationPayload app) {
        aids[record.applicationIndex] = bytesToHex(app.aid).toUpperCase();
      }
    }

    final applicationTraces = <int, List<EmvApduTrace>>{};
    final applicationFields = <int, Map<String, String>>{};
    for (final entry in groupedApdus.entries) {
      final traces = emvBuildTrace(entry.value);
      applicationTraces[entry.key] = traces;
      applicationFields[entry.key] =
          emvExtractFields(emvLeafMapFromTrace(traces));
    }
    final traces = emvBuildTrace([
      for (final record in capture.apduRecords)
        (
          (record.payload as EmvTraceApduPayload).command,
          (record.payload as EmvTraceApduPayload).response,
        ),
    ]);
    final tlvs = traces.expand((trace) => trace.responseTlvs).toList();
    final leaf = emvLeafMapFromTrace(traces);
    final meta = capture.meta;
    return _EmvResult(
      bytesToHexSpace(meta.uid).toUpperCase(),
      emvProtocolSummary(meta.uid, meta.atqa, meta.sak, meta.ats),
      meta.sak.toRadixString(16).padLeft(2, '0').toUpperCase(),
      bytesToHexSpace(meta.atqa).toUpperCase(),
      meta.ats.isEmpty ? '-' : bytesToHexSpace(meta.ats).toUpperCase(),
      traces,
      emvExtractFields(leaf),
      tlvs,
      emvDecodeAip(leaf),
      capture: capture,
      applicationAids: aids,
      applicationTraces: applicationTraces,
      applicationFields: applicationFields,
    );
  }

  Future<void> _scan() async {
    var localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _selectedApplication = -1;
    });
    try {
      if (!await _app.communicator!.isReaderDeviceMode()) {
        await _app.communicator!.setReaderDeviceMode(true);
      }
      _EmvResult result;
      if (_traceSupported != false) {
        try {
          final maximum = _maximumProcessing;
          final capture = await _app.communicator!.hf14a4EmvTrace(
            EmvTraceRequest.readOnly(
              maximumProcessing: maximum,
              includeRf: true,
              scanRecordGrid: maximum,
              readTransactionLogs: maximum,
              maxAids: maximum ? 16 : 8,
              maxRecords: maximum ? 64 : 32,
              maxApdus: maximum ? 512 : 128,
              budgetMs: maximum ? 30000 : 12000,
            ),
          );
          if (capture.meta.uid.isEmpty) {
            if (mounted) {
              setState(() => _error = localizations.no_card_found);
            }
            return;
          }
          result = _parseTrace(capture);
        } on ChameleonCommandException catch (error) {
          if (error.status != 0x67 && error.status != 0x69) rethrow;
          if (mounted) setState(() => _traceSupported = false);
          result = await _legacyScan(localizations);
        }
      } else {
        result = await _legacyScan(localizations);
      }
      if (mounted) setState(() => _result = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_EmvResult> _legacyScan(AppLocalizations localizations) async {
    if (!_maximumProcessing) {
      throw const FormatException(
          'This firmware only supports legacy EMV scanning, which runs GPO. Enable maximum processing to acknowledge possible ATC/card-state changes, or update firmware.');
    }
    final data = await _app.communicator!.hf14a4EmvScan();
    if (data.isEmpty) throw localizations.no_card_found;
    return _parseLegacy(data);
  }

  Future<void> _setMaximumProcessing(bool enabled) async {
    if (!enabled) {
      setState(() => _maximumProcessing = false);
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enable maximum processing?'),
            content: const Text(
              'Maximum mode reselects every discovered AID and performs the '
              'record grid, standard-data, and transaction-log probes. It can '
              'run GPO, advance ATC or other card state, and '
              'take up to 30 seconds. Use it only on cards you are authorised '
              'to examine and keep the card on the antenna.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enable'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) setState(() => _maximumProcessing = true);
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void _copy(String v) {
    Clipboard.setData(ClipboardData(text: v));
    _toast(AppLocalizations.of(context)!.copied);
  }

  String? _captureJson() {
    final capture = _result?.capture;
    if (capture == null) return null;
    return const JsonEncoder.withIndent('  ').convert(capture.toJson());
  }

  Future<void> _copyJson() async {
    final json = _captureJson();
    if (json == null) return;
    final copied = AppLocalizations.of(context)!.copied;
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) _toast(copied);
  }

  Future<void> _exportJson() async {
    final capture = _result?.capture;
    final json = _captureJson();
    if (capture == null || json == null) return;
    final localizations = AppLocalizations.of(context)!;
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final output = await FilePicker.saveFile(
      dialogTitle: '${localizations.output_file}:',
      fileName: 'emv-trace-${capture.meta.scanId}-$timestamp.json',
      bytes: const Utf8Encoder().convert(json),
    );
    if (output != null && mounted) _toast(localizations.save_to_file);
  }

  Widget _field(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontWeight: FontWeight.bold)),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SelectableText(v,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontFamily: 'RobotoMono')),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: MaterialLocalizations.of(context).copyButtonLabel,
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => _copy(v),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _tlvRow(EmvTlv t) {
    final printable =
        !t.constructed && t.value.every((c) => c >= 0x20 && c < 0x7F);
    final ascii = printable ? String.fromCharCodes(t.value) : null;
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + t.depth * 14.0, top: 3, bottom: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${t.tag}  ${emvTagName(t.tag)}",
              style: TextStyle(
                  fontWeight: t.constructed ? FontWeight.bold : FontWeight.w600,
                  fontSize: 12,
                  color: t.constructed
                      ? Theme.of(context).colorScheme.primary
                      : null)),
          if (!t.constructed)
            SelectableText(
                "${bytesToHexSpace(t.value).toUpperCase()}${ascii != null && ascii.trim().isNotEmpty ? '   "$ascii"' : ''}",
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12)),
        ],
      ),
    );
  }

  Widget _traceTile(EmvApduTrace t) {
    final sw = t.statusWord == null
        ? '--'
        : t.statusWord!.toRadixString(16).padLeft(4, '0').toUpperCase();
    final ok = t.statusWord == 0x9000;
    return ExpansionTile(
      title: Text('[${t.index}] ${t.name}'),
      subtitle: Text('SW $sw - ${t.statusText}',
          style: TextStyle(
              color: ok ? Theme.of(context).colorScheme.primary : null)),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      children: [
        for (final d in t.commandDetails)
          Align(alignment: Alignment.centerLeft, child: Text(d)),
        const SizedBox(height: 6),
        SelectableText('CMD ${bytesToHexSpace(t.command).toUpperCase()}',
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12)),
        SelectableText('RSP ${bytesToHexSpace(t.response).toUpperCase()}',
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12)),
        if (t.responseTlvs.isNotEmpty) ...[
          const Divider(height: 16),
          ...t.responseTlvs.map(_tlvRow),
        ],
      ],
    );
  }

  Widget _rfTile(EmvTraceRecord record) {
    final rf = record.payload as EmvTraceRfPayload;
    final direction = rf.readerToCard ? 'Reader -> card' : 'Card -> reader';
    return ExpansionTile(
      title: Text('#${record.sequence}  $direction'),
      subtitle: Text(
        '${record.stageName} | ${rf.bitLength} bits | '
        '${record.timestampMs} ms | status ${record.status}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            bytesToHexSpace(rf.data).toUpperCase(),
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _captureStatus(EmvTraceCapture capture) {
    final meta = capture.meta;
    final warnings = <String>[
      if ((meta.flags & emvTraceFlagTimeout) != 0) 'time budget reached',
      if ((meta.flags & emvTraceFlagLogTruncated) != 0) 'records dropped',
      if ((meta.flags & emvTraceFlagRfTruncated) != 0) 'RF frames dropped',
      if ((meta.flags & emvTraceFlagResponseTruncated) != 0)
        'APDU response truncated',
      if ((meta.flags & emvTraceFlagAppLimit) != 0) 'AID limit reached',
      if ((meta.flags & emvTraceFlagTransportError) != 0) 'transport error',
    ];
    final complete = meta.isComplete && !meta.isTruncated;
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: complete ? colors.primaryContainer : colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                    label:
                        Text(meta.isComplete ? 'Complete' : meta.state.label)),
                Chip(
                    label: Text(
                        meta.isTruncated ? 'Truncated' : 'No capture loss')),
                const Chip(label: Text('CRC-32 verified')),
                if (meta.maximumProcessing)
                  const Chip(label: Text('Maximum processing')),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${meta.storedRecords}/${meta.observedRecords} records | '
              '${meta.storedBytes}/${meta.requiredBytes} bytes | '
              '${meta.elapsedMs} ms | ${meta.applicationCount} AIDs | '
              'result 0x${meta.resultStatus.toRadixString(16).padLeft(2, '0').toUpperCase()}',
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Indicators: ${warnings.join(', ')}'),
            ],
          ],
        ),
      ),
    );
  }

  List<int> _applicationScopes(_EmvResult result) {
    final scopes = <int>{
      ...result.applicationTraces.keys,
      ...result.applicationAids.keys,
    }.toList()
      ..sort();
    return scopes;
  }

  String _scopeLabel(_EmvResult result, int index) {
    if (index == -1) return 'All AIDs';
    if (index == 0) return 'Session / PPSE';
    final aid = result.applicationAids[index];
    return aid == null ? 'Application $index' : 'Application $index | $aid';
  }

  Widget _partialScanHint(_EmvResult r) {
    final theme = Theme.of(context);
    final message = r.traces.isEmpty
        ? 'ISO-DEP target detected, but no EMV APDU response was captured. For phone wallets, unlock the wallet and keep the phone on the antenna until the scan finishes.'
        : 'No PAN/expiry was decoded from the APDU trace. Phone wallets often expose only tokenized or limited payment data, and may require wallet unlock/CDCVM plus a complete terminal profile.';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message,
          style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final r = _result;
    final scopedTraces = r == null || _selectedApplication == -1
        ? r?.traces ?? const <EmvApduTrace>[]
        : r.applicationTraces[_selectedApplication] ?? const <EmvApduTrace>[];
    final scopedFields = r == null || _selectedApplication == -1
        ? r?.fields ?? const <String, String>{}
        : r.applicationFields[_selectedApplication] ?? const <String, String>{};
    final scopedTlvs = scopedTraces
        .expand((trace) => trace.responseTlvs)
        .toList(growable: false);
    final scopedAip = _selectedApplication == -1
        ? r?.aip
        : emvDecodeAip(emvLeafMapFromTrace(scopedTraces));
    final scopedAid = _selectedApplication == -1
        ? (r?.applicationAids.length == 1
            ? r!.applicationAids.values.single
            : null)
        : r?.applicationAids[_selectedApplication];
    final scopedRf = r?.capture?.rfRecords
            .where((record) =>
                _selectedApplication == -1 ||
                record.applicationIndex == _selectedApplication)
            .toList(growable: false) ??
        const <EmvTraceRecord>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.emv_reader),
        actions: [
          if (r?.capture != null)
            IconButton(
              tooltip: 'Copy lossless JSON',
              icon: const Icon(Icons.data_object),
              onPressed: _copyJson,
            ),
          if (r?.capture != null)
            IconButton(
              tooltip: 'Export lossless JSON',
              icon: const Icon(Icons.download),
              onPressed: _exportJson,
            ),
        ],
      ),
      body: !_connected
          ? Center(child: Text(localizations.no_device))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _scan,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.contactless),
                      label: Text(localizations.emv_reader),
                    ),
                  ),
                  CheckboxListTile(
                    value: _maximumProcessing,
                    onChanged: _busy || _traceSupported == false
                        ? null
                        : (value) => _setMaximumProcessing(value ?? false),
                    title: const Text('Maximum processing'),
                    subtitle: Text(
                      _traceSupported == false
                          ? 'Unavailable on this firmware; legacy EMV scan will be used.'
                          : 'All AIDs, record grid, standard data, transaction logs, APDU and RF trace.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (r != null) ...[
                    if (r.capture case final capture?)
                      _captureStatus(capture)
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Legacy command 6005 fallback. APDU data is available, but retained RF frames, per-AID scope, completeness counters, and CRC verification are not.',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline),
                          ),
                        ),
                      ),
                    _field('UID', r.uid),
                    _field('Protocol', r.protocol),
                    _field('SAK', r.sak),
                    _field('ATQA', r.atqa),
                    _field('ATS', r.ats),
                    _field('APDUs captured', r.traces.length.toString()),
                    if (r.capture != null &&
                        _applicationScopes(r).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedApplication,
                        decoration: const InputDecoration(
                          labelText: 'Output scope',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: -1,
                            child: Text(_scopeLabel(r, -1)),
                          ),
                          for (final index in _applicationScopes(r))
                            DropdownMenuItem(
                              value: index,
                              child: Text(_scopeLabel(r, index)),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () => _selectedApplication = value ?? -1,
                        ),
                      ),
                    ],
                    const Divider(height: 24),
                    if (scopedFields.isEmpty)
                      _partialScanHint(r)
                    else
                      ...scopedFields.entries
                          .map((e) => _field(e.key, e.value)),
                    relayAssessmentCard(context, scopedAip, aid: scopedAid),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: Text("EMV TLV (${scopedTlvs.length})"),
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      children: scopedTlvs.map(_tlvRow).toList(),
                    ),
                    ExpansionTile(
                      title: Text("APDU trace (${scopedTraces.length})"),
                      children: scopedTraces.map(_traceTile).toList(),
                    ),
                    if (r.capture != null)
                      ExpansionTile(
                        title: Text('RF frames (${scopedRf.length})'),
                        children: scopedRf.map(_rfTile).toList(),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
