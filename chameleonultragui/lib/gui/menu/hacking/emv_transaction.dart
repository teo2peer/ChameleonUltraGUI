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

// Offline EMV purchase simulation: drives the full terminal flow (PPSE -> AID
// -> GPO with an amount -> READ RECORDS -> GENERATE AC) and shows the card's
// cryptogram. The cryptogram is NEVER sent to a bank, so nothing is authorised
// and no funds move. Uses the firmware EMV scan in transaction mode.
class EmvTransactionPage extends StatefulWidget {
  const EmvTransactionPage({super.key});

  @override
  EmvTransactionPageState createState() => EmvTransactionPageState();
}

class EmvTransactionPageState extends State<EmvTransactionPage> {
  final _amount = TextEditingController(text: '1.00');
  bool _busy = false;
  bool _maximumProcessing = false;
  bool? _traceSupported;
  String? _error;
  String? _uid;
  String? _protocol;
  String? _sak;
  String? _atqa;
  String? _ats;
  String? _traceInfo;
  Map<String, String>? _card;
  Map<String, String>? _crypto;
  EmvAip? _aip;
  List<EmvApduTrace> _traces = [];
  EmvTraceCapture? _capture;
  int _selectedApplication = -1;
  Map<int, String> _applicationAids = const {};
  Map<int, List<EmvApduTrace>> _applicationTraces = const {};

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

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  // Amount (e.g. "12.34") -> 12-digit n12 BCD, 6 bytes.
  Uint8List _amountBcd(String s) {
    final normalized = s.replaceAll(',', '.').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) {
      throw const FormatException('invalid amount');
    }
    final whole = match.group(1)!;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    final digits = '$whole$fraction'.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.length > 12) {
      throw const FormatException('amount too large');
    }
    final safe = digits.padLeft(12, '0');
    final out = Uint8List(6);
    for (int i = 0; i < 6; i++) {
      out[i] = (int.parse(safe[2 * i]) << 4) | int.parse(safe[2 * i + 1]);
    }
    return out;
  }

  Future<void> _simulate() async {
    var localizations = AppLocalizations.of(context)!;
    if (!_maximumProcessing) {
      setState(() => _error =
          'Enable maximum processing to acknowledge that GPO/GENERATE AC may advance ATC or other card state.');
      return;
    }
    late final Uint8List amount;
    try {
      amount = _amountBcd(_amount.text.trim());
    } on FormatException {
      setState(() => _error = localizations.invalid_amount);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _uid = null;
      _protocol = null;
      _sak = null;
      _atqa = null;
      _ats = null;
      _traceInfo = null;
      _card = null;
      _crypto = null;
      _aip = null;
      _traces = [];
      _capture = null;
      _selectedApplication = -1;
      _applicationAids = const {};
      _applicationTraces = const {};
    });
    try {
      if (!await _app.communicator!.isReaderDeviceMode()) {
        await _app.communicator!.setReaderDeviceMode(true);
      }
      List<(Uint8List, Uint8List)> apdus;
      Uint8List uid;
      Uint8List atqa;
      Uint8List ats;
      int sak;
      EmvTraceCapture? retainedCapture;
      var selectedApplication = -1;
      var applicationAids = <int, String>{};
      var applicationTraces = <int, List<EmvApduTrace>>{};
      if (_traceSupported != false) {
        try {
          final maximum = _maximumProcessing;
          final capture = await _app.communicator!.hf14a4EmvTrace(
            EmvTraceRequest(
              maximumProcessing: maximum,
              includeRf: true,
              scanRecordGrid: maximum,
              readTransactionLogs: maximum,
              maxAids: maximum ? 16 : 8,
              maxRecords: maximum ? 64 : 32,
              maxApdus: maximum ? 512 : 128,
              budgetMs: maximum ? 30000 : 12000,
              amount: amount,
              country: Uint8List.fromList([0x02, 0x50]),
              currency: Uint8List.fromList([0x09, 0x78]),
              date: emvTraceDate(DateTime.now()),
              cryptogramType: 0x80,
            ),
          );
          if (capture.meta.uid.isEmpty) {
            if (mounted) {
              setState(() => _error = localizations.no_card_found);
            }
            return;
          }
          if (!capture.meta.isComplete || capture.meta.resultStatus != 0x00) {
            throw FormatException(
                'EMV trace aborted (state ${capture.meta.state.label}, status 0x${capture.meta.resultStatus.toRadixString(16)})');
          }
          retainedCapture = capture;
          for (final record in capture.applicationRecords) {
            final application = record.payload as EmvTraceApplicationPayload;
            applicationAids[record.applicationIndex] =
                bytesToHex(application.aid).toUpperCase();
          }
          final groupedApdus = <int, List<(Uint8List, Uint8List)>>{};
          for (final record in capture.apduRecords) {
            final payload = record.payload as EmvTraceApduPayload;
            groupedApdus
                .putIfAbsent(record.applicationIndex, () => [])
                .add((payload.command, payload.response));
          }
          applicationTraces = {
            for (final entry in groupedApdus.entries)
              entry.key: emvBuildTrace(entry.value),
          };
          final applicationIndexes = applicationAids.keys.toList()..sort();
          final transactionApplication = capture.records
              .where((record) =>
                  record.type == EmvTraceRecordType.apdu && record.stage == 8)
              .map((record) => record.applicationIndex)
              .firstOrNull;
          selectedApplication = transactionApplication ??
              (applicationIndexes.isEmpty ? 0 : applicationIndexes.first);
          apdus = [
            for (final record in capture.apduRecords)
              (
                (record.payload as EmvTraceApduPayload).command,
                (record.payload as EmvTraceApduPayload).response,
              ),
          ];
          uid = capture.meta.uid;
          atqa = capture.meta.atqa;
          sak = capture.meta.sak;
          ats = capture.meta.ats;
          _traceInfo =
              '${capture.meta.storedRecords}/${capture.meta.observedRecords} records, app $selectedApplication, CRC-32 verified${capture.meta.isTruncated ? ', truncated' : ', complete'}';
        } on ChameleonCommandException catch (error) {
          if (error.status != 0x67 && error.status != 0x69) rethrow;
          if (mounted) setState(() => _traceSupported = false);
          final legacy = await _legacyTransaction(amount, localizations);
          (uid, atqa, sak, ats, apdus) = legacy;
          _traceInfo = 'Legacy command 6005 fallback';
        }
      } else {
        final legacy = await _legacyTransaction(amount, localizations);
        (uid, atqa, sak, ats, apdus) = legacy;
        _traceInfo = 'Legacy command 6005 fallback';
      }
      final traces = emvBuildTrace(apdus);
      final leaf = emvLeafMapFromTrace(traces); // shared by both extractors
      setState(() {
        _uid = bytesToHexSpace(uid).toUpperCase();
        _protocol = emvProtocolSummary(uid, atqa, sak, ats);
        _sak = sak.toRadixString(16).padLeft(2, '0').toUpperCase();
        _atqa = bytesToHexSpace(atqa).toUpperCase();
        _ats = ats.isEmpty ? '-' : bytesToHexSpace(ats).toUpperCase();
        _card = emvExtractFields(leaf);
        _crypto = emvExtractCryptogram(leaf);
        _aip = emvDecodeAip(leaf);
        _traces = traces;
        _capture = retainedCapture;
        _selectedApplication = selectedApplication;
        _applicationAids = Map.unmodifiable(applicationAids);
        _applicationTraces = Map.unmodifiable(applicationTraces);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<(Uint8List, Uint8List, int, Uint8List, List<(Uint8List, Uint8List)>)>
      _legacyTransaction(
          Uint8List amount, AppLocalizations localizations) async {
    final data = await _app.communicator!.hf14a4EmvScan(amount: amount);
    if (data.isEmpty) throw localizations.no_card_found;
    final scan = parseEmvScanBuffer(data);
    return (scan.uid, scan.atqa, scan.sak, scan.ats, scan.apdus);
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
              'Maximum mode runs the transaction flow for every discovered AID '
              'and adds record-grid and transaction-log probes. It can take up '
              'to 30 seconds. Keep the authorised test card on the antenna.',
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

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    _toast(AppLocalizations.of(context)!.copied);
  }

  String? _captureJson() {
    final capture = _capture;
    if (capture == null) return null;
    final decodedApplications = <Map<String, Object?>>[];
    final scopes = _applicationTraces.keys.toList()..sort();
    for (final index in scopes) {
      final traces = _applicationTraces[index]!;
      final leaf = emvLeafMapFromTrace(traces);
      decodedApplications.add({
        'index': index,
        'aid': _applicationAids[index],
        'fields': emvExtractFields(leaf),
        'cryptogram': emvExtractCryptogram(leaf),
        'aip': emvDecodeAip(leaf)?.raw,
      });
    }
    final report = {
      'system': 'chameleon-emv-purchase-simulation',
      'notice':
          'Offline evidence only; no acquirer, network, or issuer was contacted.',
      'requestedAmount': _amount.text.trim(),
      'requestedCurrency': 'EUR',
      'selectedApplication': _selectedApplication,
      'selectedAid': _applicationAids[_selectedApplication],
      'decodedCard': _card,
      'decodedCryptogram': _crypto,
      'decodedApplications': decodedApplications,
      'trace': capture.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(report);
  }

  Future<void> _copyJson() async {
    final json = _captureJson();
    if (json == null) return;
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) _toast(AppLocalizations.of(context)!.copied);
  }

  Future<void> _exportJson() async {
    final capture = _capture;
    final json = _captureJson();
    if (capture == null || json == null) return;
    final localizations = AppLocalizations.of(context)!;
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final output = await FilePicker.saveFile(
      dialogTitle: '${localizations.output_file}:',
      fileName: 'emv-purchase-${capture.meta.scanId}-$timestamp.json',
      bytes: const Utf8Encoder().convert(json),
    );
    if (output != null && mounted) _toast(localizations.save_to_file);
  }

  Widget _row(String k, String v, {Color? color}) => Padding(
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
                    child: SelectableText(
                      v,
                      textAlign: TextAlign.end,
                      style: TextStyle(fontFamily: 'RobotoMono', color: color),
                    ),
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
      padding: EdgeInsets.only(left: 8.0 + t.depth * 14.0, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${t.tag}  ${emvTagName(t.tag)}",
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      t.constructed ? FontWeight.bold : FontWeight.w600)),
          if (!t.constructed)
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    "${bytesToHexSpace(t.value).toUpperCase()}${ascii != null && ascii.trim().isNotEmpty ? '   "$ascii"' : ''}",
                    style:
                        const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: MaterialLocalizations.of(context).copyButtonLabel,
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () =>
                      _copy(bytesToHexSpace(t.value).toUpperCase()),
                ),
              ],
            ),
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _copy(
              'CMD ${bytesToHexSpace(t.command).toUpperCase()}\n'
              'RSP ${bytesToHexSpace(t.response).toUpperCase()}',
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy exchange'),
          ),
        ),
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
    final hex = bytesToHexSpace(rf.data).toUpperCase();
    return ExpansionTile(
      title: Text('#${record.sequence}  $direction'),
      subtitle: Text(
        '${record.stageName} | app ${record.applicationIndex} | '
        '${rf.bitLength} bits | ${record.timestampMs} ms | '
        'status 0x${record.status.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _copy(hex),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy frame'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            hex,
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
              'scan ${meta.scanId} | '
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

  List<int> _applicationScopes() {
    final scopes = <int>{
      ..._applicationTraces.keys,
      ..._applicationAids.keys,
    }.toList()
      ..sort();
    return scopes;
  }

  String _scopeLabel(int index) {
    if (index == -1) return 'All AIDs';
    if (index == 0) return 'Session / PPSE';
    final aid = _applicationAids[index];
    return aid == null ? 'Application $index' : 'Application $index | $aid';
  }

  String _cryptogramHint(
      AppLocalizations localizations, List<EmvApduTrace> traces) {
    EmvApduTrace? gac;
    for (final t in traces) {
      if (t.command.length >= 2 && t.command[1] == 0xAE) {
        gac = t;
      }
    }
    if (gac == null) {
      return '${localizations.purchase_sim_no_cryptogram}\nGENERATE AC was not present in the APDU trace.';
    }
    final sw = gac.statusWord == null
        ? '--'
        : gac.statusWord!.toRadixString(16).padLeft(4, '0').toUpperCase();
    return '${localizations.purchase_sim_no_cryptogram}\nGENERATE AC returned SW $sw - ${gac.statusText}.';
  }

  Widget _partialScanHint(List<EmvApduTrace> traces) {
    final theme = Theme.of(context);
    final message = traces.isEmpty
        ? 'ISO-DEP target detected, but no payment APDU response was captured. Unlock the phone wallet and keep it on the antenna until the scan finishes.'
        : 'No PAN/expiry or cryptogram was decoded. Phone wallets often return tokenized or limited data, and may require CDCVM plus a complete terminal profile.';
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
    final scopedTraces = _selectedApplication == -1
        ? _traces
        : _applicationTraces[_selectedApplication] ?? const <EmvApduTrace>[];
    final scopedLeaf = emvLeafMapFromTrace(scopedTraces);
    final scopedCard = _selectedApplication == -1
        ? _card ?? const <String, String>{}
        : emvExtractFields(scopedLeaf);
    final scopedCrypto = _selectedApplication == -1
        ? _crypto ?? const <String, String>{}
        : emvExtractCryptogram(scopedLeaf);
    final scopedTlvs = scopedTraces
        .expand((trace) => trace.responseTlvs)
        .toList(growable: false);
    final scopedAip =
        _selectedApplication == -1 ? _aip : emvDecodeAip(scopedLeaf);
    final scopedAid = _selectedApplication == -1
        ? (_applicationAids.length == 1 ? _applicationAids.values.single : null)
        : _applicationAids[_selectedApplication];
    final scopedRf = _capture?.rfRecords
            .where((record) =>
                _selectedApplication == -1 ||
                record.applicationIndex == _selectedApplication)
            .toList(growable: false) ??
        const <EmvTraceRecord>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.purchase_sim),
        actions: [
          if (_capture != null)
            IconButton(
              tooltip: 'Copy lossless purchase JSON',
              icon: const Icon(Icons.data_object),
              onPressed: _copyJson,
            ),
          if (_capture != null)
            IconButton(
              tooltip: 'Export lossless purchase JSON',
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
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(localizations.purchase_sim_banner,
                                style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: localizations.value_amount,
                              suffixText: 'EUR',
                              border: const OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _simulate,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.point_of_sale),
                        label: Text(localizations.simulate_purchase),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    value: _maximumProcessing,
                    onChanged: _busy || _traceSupported == false
                        ? null
                        : (value) => _setMaximumProcessing(value ?? false),
                    title: const Text('Maximum processing'),
                    subtitle: Text(
                      _traceSupported == false
                          ? 'Unavailable on this firmware; the legacy transaction scan will be used.'
                          : 'Run every discovered AID with record-grid and transaction-log probes.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (_card != null) ...[
                    if (_capture case final capture?)
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
                    Text(localizations.emv_reader,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_uid != null) _row('UID', _uid!),
                    if (_protocol != null) _row('Protocol', _protocol!),
                    if (_sak != null) _row('SAK', _sak!),
                    if (_atqa != null) _row('ATQA', _atqa!),
                    if (_ats != null) _row('ATS', _ats!),
                    if (_traceInfo != null) _row('Capture', _traceInfo!),
                    _row('APDUs captured', scopedTraces.length.toString()),
                    if (_capture != null &&
                        _applicationScopes().isNotEmpty) ...[
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
                            child: Text(_scopeLabel(-1)),
                          ),
                          for (final index in _applicationScopes())
                            DropdownMenuItem(
                              value: index,
                              child: Text(_scopeLabel(index)),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () => _selectedApplication = value ?? -1,
                        ),
                      ),
                    ],
                    if (scopedCard.isEmpty)
                      _partialScanHint(scopedTraces)
                    else
                      ...(scopedCard.entries.map((e) => _row(e.key, e.value))),
                    const Divider(height: 24),
                    Text(localizations.purchase_sim,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (scopedCrypto.isEmpty)
                      Text(_cryptogramHint(localizations, scopedTraces),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline))
                    else
                      ...(scopedCrypto.entries.map((e) => _row(e.key, e.value,
                          color: Theme.of(context).colorScheme.primary))),
                    relayAssessmentCard(context, scopedAip, aid: scopedAid),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: Text("EMV TLV (${scopedTlvs.length})"),
                      children: scopedTlvs.map(_tlvRow).toList(),
                    ),
                    ExpansionTile(
                      title: Text("APDU trace (${scopedTraces.length})"),
                      children: scopedTraces.map(_traceTile).toList(),
                    ),
                    if (_capture != null)
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
