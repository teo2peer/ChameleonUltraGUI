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
  final Map<String, String> fields; // human-readable extracted fields
  _EmvResult(this.uid, this.sak, this.atqa, this.ats, this.apdus, this.fields);
}

// Read an EMV contactless card in one shot (PPSE -> AID -> GPO -> READ RECORDs)
// and extract PAN / expiry / cardholder / AID from the BER-TLV responses.
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

  // Flatten BER-TLV into a leaf tag -> value map (recurses constructed tags).
  void _walkTlv(Uint8List d, Map<String, Uint8List> out) {
    int i = 0;
    while (i < d.length) {
      if (d[i] == 0x00 || d[i] == 0xFF) {
        i++;
        continue;
      }
      final tagStart = i;
      final first = d[i];
      i++;
      final constructed = (first & 0x20) != 0;
      if ((first & 0x1F) == 0x1F) {
        while (i < d.length && (d[i] & 0x80) != 0) {
          i++;
        }
        if (i < d.length) i++;
      }
      final tag = bytesToHex(d.sublist(tagStart, i)).toUpperCase();
      if (i >= d.length) break;
      int len = d[i];
      i++;
      if ((len & 0x80) != 0) {
        final n = len & 0x7F;
        len = 0;
        for (int k = 0; k < n && i < d.length; k++) {
          len = (len << 8) | d[i];
          i++;
        }
      }
      if (i + len > d.length) len = d.length - i;
      final value = d.sublist(i, i + len);
      if (constructed) {
        _walkTlv(value, out);
      } else {
        out[tag] = value;
      }
      i += len;
    }
  }

  String _asciiOf(Uint8List b) =>
      String.fromCharCodes(b.where((c) => c >= 0x20 && c < 0x7F)).trim();

  Map<String, String> _extractFields(Map<String, Uint8List> tlv) {
    final f = <String, String>{};
    // Track 2 equivalent (57): PAN 'D' YYMM service ...
    if (tlv.containsKey('57')) {
      final t2 = bytesToHex(tlv['57']!).toUpperCase();
      final sep = t2.indexOf('D');
      if (sep > 0) {
        f['PAN'] = t2.substring(0, sep);
        final rest = t2.substring(sep + 1);
        if (rest.length >= 4) {
          f['Expiry'] = "${rest.substring(2, 4)}/${rest.substring(0, 2)}"; // MM/YY
        }
      }
    }
    if (!f.containsKey('PAN') && tlv.containsKey('5A')) {
      f['PAN'] = bytesToHex(tlv['5A']!).toUpperCase().replaceAll('F', '');
    }
    if (!f.containsKey('Expiry') && tlv.containsKey('5F24')) {
      final e = bytesToHex(tlv['5F24']!); // YYMMDD
      if (e.length >= 4) f['Expiry'] = "${e.substring(2, 4)}/${e.substring(0, 2)}";
    }
    if (tlv.containsKey('5F20')) f['Cardholder'] = _asciiOf(tlv['5F20']!);
    if (tlv.containsKey('50')) f['Application'] = _asciiOf(tlv['50']!);
    if (tlv.containsKey('4F')) f['AID'] = bytesToHex(tlv['4F']!).toUpperCase();
    if (tlv.containsKey('5F28')) {
      f['Country'] = bytesToHex(tlv['5F28']!); // country code (numeric)
    }
    return f;
  }

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
    final tlv = <String, Uint8List>{};
    for (int k = 0; k < num; k++) {
      final cmdLen = d[i++];
      final cmd = d.sublist(i, i + cmdLen);
      i += cmdLen;
      final respLen = d[i] | (d[i + 1] << 8);
      i += 2;
      final resp = d.sublist(i, i + respLen);
      i += respLen;
      apdus.add(_EmvApdu(cmd, resp));
      // Drop the trailing SW1SW2 (2 bytes) before TLV parsing.
      if (resp.length > 2) _walkTlv(resp.sublist(0, resp.length - 2), tlv);
    }
    return _EmvResult(
      bytesToHexSpace(uid).toUpperCase(),
      sak.toRadixString(16).padLeft(2, '0').toUpperCase(),
      bytesToHexSpace(atqa).toUpperCase(),
      ats.isEmpty ? '-' : bytesToHexSpace(ats).toUpperCase(),
      apdus,
      _extractFields(tlv),
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
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: v)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

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
                    const SizedBox(height: 12),
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
