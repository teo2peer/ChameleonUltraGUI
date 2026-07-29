import 'package:chameleonultragui/helpers/emv.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/gui/component/apdu_cheatsheet.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// ISO14443-4 (T=CL) APDU terminal: select a real card (with RATS) and send a
// raw APDU, showing the response. Uses the firmware HF14A_4_READER_APDU command.
class ApduTerminalPage extends StatefulWidget {
  const ApduTerminalPage({super.key});

  @override
  ApduTerminalPageState createState() => ApduTerminalPageState();
}

class ApduTerminalPageState extends State<ApduTerminalPage> {
  // Default: SELECT PPSE (2PAY.SYS.DDF01) — a harmless probe for contactless.
  final _apdu =
      TextEditingController(text: '00A404000E325041592E5359532E4444463031');
  bool _busy = false;
  String? _response;
  String? _decoded;
  List<EmvTlv> _tlvs = [];
  String? _error;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _apdu.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    var localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _response = null;
      _decoded = null;
      _tlvs = [];
      _error = null;
    });
    try {
      final apdu = hexToBytes(_apdu.text.trim().replaceAll(' ', ''));
      if (apdu.isEmpty) {
        setState(() => _error = localizations.invalid_hex_input);
        return;
      }
      if (!await _app.communicator!.isReaderDeviceMode()) {
        await _app.communicator!.setReaderDeviceMode(true);
      }
      final resp = await _app.communicator!.hf14a4ReaderApdu(apdu);
      final sw =
          resp.length >= 2 ? (resp[resp.length - 2] << 8) | resp.last : null;
      final body = resp.length >= 2 ? resp.sublist(0, resp.length - 2) : resp;
      setState(() {
        _response = bytesToHexSpace(resp).toUpperCase();
        _decoded =
            '${emvDescribeCommand(apdu)} | SW ${sw == null ? '--' : sw.toRadixString(16).padLeft(4, '0').toUpperCase()} - ${emvStatusText(sw)}';
        _tlvs = parseEmvTlv(body);
      });
    } on FormatException {
      setState(() => _error = localizations.invalid_hex_input);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tlvRow(EmvTlv t) {
    final printable =
        !t.constructed && t.value.every((c) => c >= 0x20 && c < 0x7F);
    final ascii = printable ? String.fromCharCodes(t.value) : null;
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + t.depth * 14.0, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${t.tag}  ${emvTagName(t.tag)}',
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

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.apdu_terminal)),
      body: !_connected
          ? Center(child: Text(localizations.no_device))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ApduCheatSheet(
                    onExampleSelected: (example) => setState(() {
                      _apdu.text = example;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apdu,
                    maxLines: 2,
                    decoration: InputDecoration(
                        labelText: "APDU (hex)",
                        border: const OutlineInputBorder()),
                    style: const TextStyle(fontFamily: 'RobotoMono'),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _send,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send),
                      label: Text(localizations.send),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (_response != null) ...[
                    if (_decoded != null) ...[
                      Text(_decoded!,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(localizations.response,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => Clipboard.setData(
                              ClipboardData(text: _response!)),
                        ),
                      ],
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(_response!,
                          style: const TextStyle(
                              fontFamily: 'RobotoMono', fontSize: 14)),
                    ),
                    if (_tlvs.isNotEmpty)
                      ExpansionTile(
                        title: Text('Response TLV (${_tlvs.length})'),
                        children: _tlvs.map(_tlvRow).toList(),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
