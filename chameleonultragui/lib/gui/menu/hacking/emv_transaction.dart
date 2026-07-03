import 'package:chameleonultragui/helpers/emv.dart';
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
  String? _error;
  Map<String, String>? _card;
  Map<String, String>? _crypto;
  List<EmvTlv> _tlvs = [];
  List<(Uint8List, Uint8List)> _apdus = [];

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  // Amount (e.g. "12.34") -> 12-digit n12 BCD, 6 bytes.
  Uint8List _amountBcd(String s) {
    // Non-negative; reject empty/garbage (double.parse throws -> invalid_amount).
    final cents = ((double.parse(s.replaceAll(',', '.')) * 100).round()).abs();
    final digits = cents.toString().padLeft(12, '0');
    final safe = digits.length > 12 ? digits.substring(digits.length - 12) : digits;
    final out = Uint8List(6);
    for (int i = 0; i < 6; i++) {
      out[i] = (int.parse(safe[2 * i]) << 4) | int.parse(safe[2 * i + 1]);
    }
    return out;
  }

  Future<void> _simulate() async {
    var localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _card = null;
      _crypto = null;
      _tlvs = [];
      _apdus = [];
    });
    try {
      final amount = _amountBcd(_amount.text.trim());
      if (!await _app.communicator!.isReaderDeviceMode()) {
        await _app.communicator!.setReaderDeviceMode(true);
      }
      final data = await _app.communicator!.hf14a4EmvScan(amount: amount);
      if (!mounted) return;
      if (data.isEmpty) {
        setState(() => _error = localizations.no_card_found);
        return;
      }
      // Bounds-checked parse -> TLV (shared helper).
      final scan = parseEmvScanBuffer(data);
      final tlvs = <EmvTlv>[];
      for (final (_, resp) in scan.apdus) {
        if (resp.length > 2) {
          tlvs.addAll(parseEmvTlv(resp.sublist(0, resp.length - 2)));
        }
      }
      final leaf = emvLeafMap(tlvs); // single pass, shared by both extractors
      setState(() {
        _card = emvExtractFields(leaf);
        _crypto = emvExtractCryptogram(leaf);
        _tlvs = tlvs;
        _apdus = scan.apdus;
      });
    } on FormatException {
      setState(() => _error = localizations.invalid_amount);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                      color: Theme.of(context)
                          .colorScheme
                          .tertiaryContainer,
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
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (_card != null) ...[
                    Text(localizations.emv_reader,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...(_card!.entries.map((e) => _row(e.key, e.value))),
                    const Divider(height: 24),
                    Text(localizations.purchase_sim,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_crypto!.isEmpty)
                      Text(localizations.purchase_sim_no_cryptogram,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline))
                    else
                      ...(_crypto!.entries.map((e) => _row(e.key, e.value,
                          color: Theme.of(context).colorScheme.primary))),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: Text("EMV TLV (${_tlvs.length})"),
                      children: _tlvs
                          .map((t) => Padding(
                                padding: EdgeInsets.only(
                                    left: 8.0 + t.depth * 14.0,
                                    top: 2,
                                    bottom: 2),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text("${t.tag}  ${emvTagName(t.tag)}",
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: t.constructed
                                                ? FontWeight.bold
                                                : FontWeight.w600)),
                                    if (!t.constructed)
                                      SelectableText(
                                          bytesToHexSpace(t.value)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                              fontFamily: 'RobotoMono',
                                              fontSize: 12)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                    ExpansionTile(
                      title: Text("APDU (${_apdus.length})"),
                      children: _apdus
                          .map((a) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                        "→ ${bytesToHexSpace(a.$1).toUpperCase()}",
                                        style: const TextStyle(
                                            fontFamily: 'RobotoMono',
                                            fontSize: 12)),
                                    SelectableText(
                                        "← ${bytesToHexSpace(a.$2).toUpperCase()}",
                                        style: const TextStyle(
                                            fontFamily: 'RobotoMono',
                                            fontSize: 12)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
