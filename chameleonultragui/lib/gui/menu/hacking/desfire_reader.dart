import 'package:chameleonultragui/helpers/emv.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class _DesfireApp {
  final String aid;
  final List<String> fileIds;
  final String? keySettings; // GetKeySettings summary
  final Map<String, String> fileSettings = {}; // fileId -> decoded settings
  _DesfireApp(this.aid, this.fileIds, [this.keySettings]);
}

class _DesfireResult {
  final String uid;
  final Map<String, String> info; // vendor, hw/sw version, storage
  final List<_DesfireApp> apps;
  final List<(Uint8List, Uint8List)> apdus;
  _DesfireResult(this.uid, this.info, this.apps, this.apdus);
}

// Enumerate a MIFARE DESFire card (read-only): version, UID, applications and
// their file IDs. Uses the firmware HF14A_4_DESFIRE_SCAN one-shot command.
class DesfireReaderPage extends StatefulWidget {
  const DesfireReaderPage({super.key});

  @override
  DesfireReaderPageState createState() => DesfireReaderPageState();
}

class DesfireReaderPageState extends State<DesfireReaderPage> {
  bool _busy = false;
  String? _error;
  _DesfireResult? _result;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  String _storageLabel(int code) {
    // DESFire storage size is 2^(n>>1); an odd LSB means "between this and the
    // next size". Bound the shift so a bogus byte can't overflow.
    final shift = (code >> 1) & 0x1F;
    final bytes = 1 << shift;
    final approx = (code & 1) != 0 ? "> " : "";
    return "0x${code.toRadixString(16).padLeft(2, '0').toUpperCase()} ($approx$bytes B)";
  }

  // Decode a DESFire GetFileSettings response: type, comm mode, size.
  String _decodeFileSettings(List<int> b) {
    const types = [
      'Standard data',
      'Backup data',
      'Value',
      'Linear record',
      'Cyclic record'
    ];
    final type = b[0] < types.length
        ? types[b[0]]
        : 'type 0x${b[0].toRadixString(16).padLeft(2, '0')}';
    final comm = b.length > 1
        ? const ['plain', 'MAC', '?', 'encrypted'][b[1] & 0x03]
        : '?';
    var extra = '';
    if ((b[0] == 0x00 || b[0] == 0x01) && b.length >= 7) {
      final size = b[4] | (b[5] << 8) | (b[6] << 16);
      extra = ' · $size B';
    }
    return '$type · $comm$extra';
  }

  _DesfireResult _parse(Uint8List d) {
    final scan = parseEmvScanBuffer(d); // bounds-checked; throws on truncation
    final tagUid = scan.uid;

    final apdus = <(Uint8List, Uint8List)>[];
    final version = <int>[];
    final apps = <_DesfireApp>[];
    List<int> aids = [];
    List<int> freeMemory = [];
    String? currentAid;
    String? pendingKeySettings;

    for (final (cmd, resp) in scan.apdus) {
      apdus.add((cmd, resp));

      final ins = cmd.length > 1 ? cmd[1] : 0;
      final body = resp.length >= 2 ? resp.sublist(0, resp.length - 2) : resp;
      if (ins == 0x60 || ins == 0xAF) {
        version.addAll(body);
      } else if (ins == 0x6E) {
        freeMemory = body; // 3-byte little-endian free EEPROM
      } else if (ins == 0x6A) {
        aids = body; // N * 3 bytes
      } else if (ins == 0x5A) {
        // AID is in the command: 90 5A 00 00 03 <aid0 aid1 aid2> 00
        if (cmd.length >= 8) {
          currentAid = bytesToHex(cmd.sublist(5, 8)).toUpperCase();
        }
        pendingKeySettings = null;
      } else if (ins == 0x45) {
        // GetKeySettings: body[0]=settings byte, body[1]=key count
        if (body.length >= 2) {
          pendingKeySettings =
              "0x${body[0].toRadixString(16).padLeft(2, '0').toUpperCase()} · ${body[1] & 0x0F} keys";
        }
      } else if (ins == 0x6F) {
        final files = body
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .toList();
        apps.add(_DesfireApp(currentAid ?? '??????', files, pendingKeySettings));
      } else if (ins == 0xF5) {
        // GetFileSettings for the file id in the command (byte 5)
        if (apps.isNotEmpty && cmd.length >= 6 && body.isNotEmpty) {
          apps.last.fileSettings[
                  cmd[5].toRadixString(16).padLeft(2, '0').toUpperCase()] =
              _decodeFileSettings(body);
        }
      }
    }

    // Applications with no GetFileIDs response (or before select mapping)
    if (apps.isEmpty && aids.length >= 3) {
      for (int a = 0; a + 3 <= aids.length; a += 3) {
        apps.add(_DesfireApp(
            bytesToHex(Uint8List.fromList(aids.sublist(a, a + 3))).toUpperCase(),
            const []));
      }
    }

    final info = <String, String>{};
    String uid = bytesToHexSpace(tagUid).toUpperCase();
    if (version.length >= 21) {
      info['Vendor'] = version[0] == 0x04
          ? 'NXP (0x04)'
          : '0x${version[0].toRadixString(16).padLeft(2, '0')}';
      info['HW version'] = '${version[3]}.${version[4]}';
      info['Storage'] = _storageLabel(version[5]);
      info['SW version'] = '${version[10]}.${version[11]}';
      uid = bytesToHexSpace(Uint8List.fromList(version.sublist(14, 21)))
          .toUpperCase();
    }
    if (freeMemory.length >= 3) {
      info['Free memory'] =
          '${freeMemory[0] | (freeMemory[1] << 8) | (freeMemory[2] << 16)} B';
    }
    return _DesfireResult(uid, info, apps, apdus);
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
      final data = await _app.communicator!.hf14a4DesfireScan();
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

  Widget _row(String k, String v) => Padding(
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
                    onPressed: () => Clipboard.setData(ClipboardData(text: v)),
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
      appBar: AppBar(title: Text(localizations.desfire_reader)),
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
                          : const Icon(Icons.memory),
                      label: Text(localizations.desfire_reader),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (r != null) ...[
                    _row('UID', r.uid),
                    ...r.info.entries.map((e) => _row(e.key, e.value)),
                    const Divider(height: 24),
                    Text(
                        "${localizations.applications} (${r.apps.length})",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...r.apps.map((a) => Card(
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    SelectableText("AID ${a.aid}",
                                        style: const TextStyle(
                                            fontFamily: 'RobotoMono',
                                            fontWeight: FontWeight.bold)),
                                    if (a.keySettings != null)
                                      Text(a.keySettings!,
                                          style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                                if (a.fileIds.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text('no files',
                                        style: TextStyle(fontSize: 12)),
                                  )
                                else
                                  ...a.fileIds.map((fid) => Padding(
                                        padding: const EdgeInsets.only(
                                            top: 4, left: 8),
                                        child: Text(
                                            a.fileSettings[fid] != null
                                                ? "· file $fid:  ${a.fileSettings[fid]}"
                                                : "· file $fid",
                                            style: const TextStyle(
                                                fontFamily: 'RobotoMono',
                                                fontSize: 12)),
                                      )),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: Text("APDU (${r.apdus.length})"),
                      children: r.apdus
                          .map((p) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                        "→ ${bytesToHexSpace(p.$1).toUpperCase()}",
                                        style: const TextStyle(
                                            fontFamily: 'RobotoMono',
                                            fontSize: 12)),
                                    SelectableText(
                                        "← ${bytesToHexSpace(p.$2).toUpperCase()}",
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
