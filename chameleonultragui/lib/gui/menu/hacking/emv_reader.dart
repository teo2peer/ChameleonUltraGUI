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
  _EmvResult(this.uid, this.sak, this.atqa, this.ats, this.apdus, this.fields,
      this.tlvs);
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
    int i = 0;
    final uidLen = d[i++];
    final uid = d.sublist(i, i + uidLen);
    i += uidLen;
    final atqa = d.sublist(i, i + 2);
    i += 2;
    final sak = d[i++];
    final atsLen = d[i++];
    final ats = d.sublist(i, i + atsLen);
    i += atsLen;
    final num = d[i++];
    final apdus = <_EmvApdu>[];
    final tlvs = <EmvTlv>[];
    for (int k = 0; k < num; k++) {
      final cmdLen = d[i++];
      final cmd = d.sublist(i, i + cmdLen);
      i += cmdLen;
      final respLen = d[i] | (d[i + 1] << 8);
      i += 2;
      final resp = d.sublist(i, i + respLen);
      i += respLen;
      apdus.add(_EmvApdu(cmd, resp));
      if (resp.length > 2) {
        tlvs.addAll(parseEmvTlv(resp.sublist(0, resp.length - 2)));
      }
    }
    return _EmvResult(
      bytesToHexSpace(uid).toUpperCase(),
      sak.toRadixString(16).padLeft(2, '0').toUpperCase(),
      bytesToHexSpace(atqa).toUpperCase(),
      ats.isEmpty ? '-' : bytesToHexSpace(ats).toUpperCase(),
      apdus,
      emvExtractFields(tlvs),
      tlvs,
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
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => Clipboard.setData(ClipboardData(text: v)),
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

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.emv_reader)),
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
