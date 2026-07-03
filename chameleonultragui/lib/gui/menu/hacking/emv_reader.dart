import 'package:chameleonultragui/helpers/emv.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class _EmvApdu {
  final Uint8List cmd;
  final Uint8List resp;
  _EmvApdu(this.cmd, this.resp);
}

class _EmvResult {
  final String uid;
  final String sak;
  final String atqa;
  final String ats;
  final List<_EmvApdu> apdus;
  final Map<String, String> fields;
  final List<EmvTlv> tlvs;
  final EmvAip? aip;
  _EmvResult(this.uid, this.sak, this.atqa, this.ats, this.apdus, this.fields,
      this.tlvs, this.aip);
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
  String? _error;
  _EmvResult? _result;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  _EmvResult _parse(Uint8List d) {
    final scan = parseEmvScanBuffer(d); // bounds-checked; throws on truncation
    final apdus = <_EmvApdu>[];
    final tlvs = <EmvTlv>[];
    for (final (cmd, resp) in scan.apdus) {
      apdus.add(_EmvApdu(cmd, resp));
      if (resp.length > 2) {
        tlvs.addAll(parseEmvTlv(resp.sublist(0, resp.length - 2)));
      }
    }
    final leaf = emvLeafMap(tlvs); // single pass, shared by fields + AIP
    return _EmvResult(
      bytesToHexSpace(scan.uid).toUpperCase(),
      scan.sak.toRadixString(16).padLeft(2, '0').toUpperCase(),
      bytesToHexSpace(scan.atqa).toUpperCase(),
      scan.ats.isEmpty ? '-' : bytesToHexSpace(scan.ats).toUpperCase(),
      apdus,
      emvExtractFields(leaf),
      tlvs,
      emvDecodeAip(leaf),
    );
  }

  Future<void> _scan() async {
    var localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      if (!await _app.communicator!.isReaderDeviceMode()) {
        await _app.communicator!.setReaderDeviceMode(true);
      }
      final data = await _app.communicator!.hf14a4EmvScan();
      if (!mounted) return;
      if (data.isEmpty) {
        setState(() => _error = localizations.no_card_found);
        return;
      }
      setState(() => _result = _parse(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  // Copy the whole parsed card (tag info + fields + relay verdict) as text —
  // handy for a report / CTF writeup.
  void _copyAll() {
    final r = _result;
    if (r == null) return;
    final b = StringBuffer()
      ..writeln('UID: ${r.uid}')
      ..writeln('ATQA: ${r.atqa}  SAK: ${r.sak}  ATS: ${r.ats}');
    for (final e in r.fields.entries) {
      b.writeln('${e.key}: ${e.value}');
    }
    if (r.aip != null) {
      b.writeln('AIP: ${r.aip!.raw} (${r.aip!.features.join(", ")})');
      b.writeln('Relay resistance (RRP): ${r.aip!.rrp ? "yes" : "no"}');
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    _toast(AppLocalizations.of(context)!.copied);
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
                  fontWeight:
                      t.constructed ? FontWeight.bold : FontWeight.w600,
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

  // Relay-resistance assessment from the AIP (tag 82): tells you, defensively,
  // whether this card would block a relay attack (RRP) and whether it resists
  // cloning (DDA/CDA) — plus remediation guidance.
  Widget _relaySection(BuildContext context, EmvAip? aip) {
    final l = AppLocalizations.of(context)!;
    if (aip == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(l.relay_no_aip,
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final protected = aip.rrp;
    final bg = protected ? scheme.primaryContainer : scheme.errorContainer;
    final fg = protected ? scheme.onPrimaryContainer : scheme.onErrorContainer;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(protected ? Icons.verified_user : Icons.gpp_bad, color: fg),
            const SizedBox(width: 8),
            Expanded(
                child: Text(l.relay_assessment,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: fg))),
          ]),
          const SizedBox(height: 6),
          Text(protected ? l.relay_protected : l.relay_exposed,
              style: TextStyle(color: fg)),
          const SizedBox(height: 6),
          Text(aip.dda || aip.cda ? l.relay_clone_ok : l.relay_clone_weak,
              style: TextStyle(color: fg, fontSize: 12)),
          const SizedBox(height: 8),
          SelectableText("AIP ${aip.raw}: ${aip.features.join(', ')}",
              style: TextStyle(
                  color: fg, fontSize: 11, fontFamily: 'RobotoMono')),
          const SizedBox(height: 8),
          Text(l.relay_remediation,
              style: TextStyle(
                  color: fg, fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final r = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.emv_reader),
        actions: [
          if (r != null)
            IconButton(
              tooltip: MaterialLocalizations.of(context).copyButtonLabel,
              icon: const Icon(Icons.copy_all),
              onPressed: _copyAll,
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
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (r != null) ...[
                    _field('UID', r.uid),
                    _field('SAK', r.sak),
                    _field('ATQA', r.atqa),
                    _field('ATS', r.ats),
                    const Divider(height: 24),
                    if (r.fields.isEmpty)
                      Text(localizations.no_card_found,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline))
                    else
                      ...r.fields.entries.map((e) => _field(e.key, e.value)),
                    _relaySection(context, r.aip),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: Text("EMV TLV (${r.tlvs.length})"),
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      children: r.tlvs.map(_tlvRow).toList(),
                    ),
                    ExpansionTile(
                      title: Text("APDU (${r.apdus.length})"),
                      children: r.apdus
                          .map((a) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                        "→ ${bytesToHexSpace(a.cmd).toUpperCase()}",
                                        style: const TextStyle(
                                            fontFamily: 'RobotoMono',
                                            fontSize: 12)),
                                    SelectableText(
                                        "← ${bytesToHexSpace(a.resp).toUpperCase()}",
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
