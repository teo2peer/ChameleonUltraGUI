import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/relay_assessment.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/emv.dart';
import 'package:chameleonultragui/helpers/emv_trace.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
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
  String? _protocol;
  String? _traceInfo;
  Map<String, String>? _card;
  Map<String, String>? _crypto;
  EmvAip? _aip;
  List<EmvTlv> _tlvs = [];
  List<EmvApduTrace> _traces = [];

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
      _protocol = null;
      _traceInfo = null;
      _card = null;
      _crypto = null;
      _aip = null;
      _tlvs = [];
      _traces = [];
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
          final applicationIndexes = capture.applicationRecords
              .map((record) => record.applicationIndex)
              .toList(growable: false);
          final transactionApplication = capture.records
              .where((record) =>
                  record.type == EmvTraceRecordType.apdu && record.stage == 8)
              .map((record) => record.applicationIndex)
              .firstOrNull;
          final selectedApplication = transactionApplication ??
              (applicationIndexes.isEmpty ? 0 : applicationIndexes.first);
          apdus = [
            for (final record in capture.apduRecords)
              if (record.applicationIndex == selectedApplication)
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
      final tlvs = traces.expand((t) => t.responseTlvs).toList();
      final leaf = emvLeafMapFromTrace(traces); // shared by both extractors
      setState(() {
        _protocol = emvProtocolSummary(uid, atqa, sak, ats);
        _card = emvExtractFields(leaf);
        _crypto = emvExtractCryptogram(leaf);
        _aip = emvDecodeAip(leaf);
        _tlvs = tlvs;
        _traces = traces;
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

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontWeight: FontWeight.bold)),
            Flexible(
              child: SelectableText(v,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontFamily: 'RobotoMono', color: color)),
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

  String _cryptogramHint(AppLocalizations localizations) {
    EmvApduTrace? gac;
    for (final t in _traces) {
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

  Widget _partialScanHint() {
    final theme = Theme.of(context);
    final message = _traces.isEmpty
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
    return Scaffold(
      appBar: AppBar(title: Text(localizations.purchase_sim)),
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
                    Text(localizations.emv_reader,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_protocol != null) _row('Protocol', _protocol!),
                    if (_traceInfo != null) _row('Capture', _traceInfo!),
                    _row('APDUs captured', _traces.length.toString()),
                    if (_card!.isEmpty)
                      _partialScanHint()
                    else
                      ...(_card!.entries.map((e) => _row(e.key, e.value))),
                    const Divider(height: 24),
                    Text(localizations.purchase_sim,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_crypto!.isEmpty)
                      Text(_cryptogramHint(localizations),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline))
                    else
                      ...(_crypto!.entries.map((e) => _row(e.key, e.value,
                          color: Theme.of(context).colorScheme.primary))),
                    relayAssessmentCard(context, _aip),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: Text("EMV TLV (${_tlvs.length})"),
                      children: _tlvs.map(_tlvRow).toList(),
                    ),
                    ExpansionTile(
                      title: Text("APDU trace (${_traces.length})"),
                      children: _traces.map(_traceTile).toList(),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
