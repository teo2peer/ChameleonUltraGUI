import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class _Rule {
  final String label;
  final String cmd; // hex prefix to match
  final String resp; // hex response
  _Rule(this.label, this.cmd, this.resp);
}

// Emulate an ISO14443-4 (EMV) card so a terminal you own / are authorised to
// test can read it. For lab use: load a well-formed test card, or edge-case
// responses to check how YOUR terminal handles malformed data. Uses the
// firmware HF14A_4 static-response emulation.
class EmvEmulatorPage extends StatefulWidget {
  const EmvEmulatorPage({super.key});

  @override
  EmvEmulatorPageState createState() => EmvEmulatorPageState();
}

class EmvEmulatorPageState extends State<EmvEmulatorPage> {
  final _cmd = TextEditingController();
  final _resp = TextEditingController();
  final _uid = TextEditingController(text: '11223344');
  bool _busy = false;
  bool _armed = false;
  final List<_Rule> _rules = [];

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _cmd.dispose();
    _resp.dispose();
    _uid.dispose();
    super.dispose();
  }

  // A minimal, well-formed Mastercard test card (PPSE / SELECT AID / GPO).
  static final List<_Rule> _testCard = [
    _Rule('SELECT PPSE', '00A404000E325041592E5359532E4444463031',
        '6F23840E325041592E5359532E4444463031A511BF0C0E610C4F07A00000000410108701019000'),
    _Rule('SELECT AID', '00A4040007A0000000041010',
        '6F1D8407A0000000041010A512500A4D6173746572436172648701019F38009000'),
    _Rule('GPO', '80A80000', '6985'),
  ];

  // Edge-case responses for terminal robustness testing (own/authorised lab).
  static final List<_Rule> _robustness = [
    _Rule('PPSE oversized length', '00A404000E325041592E5359532E4444463031',
        '6F81FF84'),
    _Rule('SELECT AID truncated TLV', '00A4040007A0000000041010', '6F'),
    _Rule('GPO error 6A80', '80A80000', '6A80'),
    _Rule('READ RECORD huge length', '00B2', '70820FFF'),
  ];

  void _show(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  bool _isHex(String s) =>
      s.isNotEmpty && s.length.isEven && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s);

  Future<void> _arm() async {
    var localizations = AppLocalizations.of(context)!;
    if (_rules.isEmpty) {
      _show(localizations.emv_emulator_no_rules);
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = hexToBytes(_uid.text.trim().replaceAll(' ', ''));
      if (![4, 7, 10].contains(uid.length)) {
        _show(localizations.invalid_uid_bytes);
        setState(() => _busy = false);
        return;
      }
      final slot = await _app.communicator!.getActiveSlot();
      await _app.communicator!.setReaderDeviceMode(false);
      await _app.communicator!.setSlotType(slot, TagType.hf14a4);
      // SAK 0x20 => ISO14443-4; a small generic ATS.
      // ATQA in display order; the wrapper reverses to wire order like the
      // rest of the codebase (setMf1AntiCollision).
      await _app.communicator!.hf14a4SetAntiColl(
          uid,
          Uint8List.fromList([0x00, 0x04]),
          0x20,
          Uint8List.fromList([0x78, 0x77, 0x80, 0x02]));
      await _app.communicator!.hf14a4ClearStaticResponses();
      for (final r in _rules) {
        await _app.communicator!.hf14a4AddStaticResponse(
            hexToBytes(r.cmd.replaceAll(' ', '')),
            hexToBytes(r.resp.replaceAll(' ', '')));
      }
      await _app.communicator!.activateSlot(slot);
      if (!mounted) return;
      setState(() => _armed = true);
      _show(localizations.emv_emulator_armed);
    } on FormatException {
      _show(localizations.invalid_hex_input);
    } on RangeError {
      _show(localizations.invalid_hex_input);
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await _app.communicator!.hf14a4ClearStaticResponses();
      setState(() {
        _rules.clear();
        _armed = false;
      });
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.emv_emulator)),
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
                        color:
                            Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(localizations.emv_emulator_banner,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _uid,
                    decoration: InputDecoration(
                        labelText: localizations.uid,
                        border: const OutlineInputBorder()),
                    style: const TextStyle(fontFamily: 'RobotoMono'),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _rules
                                    ..clear()
                                    ..addAll(_testCard);
                                }),
                        icon: const Icon(Icons.credit_card),
                        label: Text(localizations.emv_emulator_test_card),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _rules
                                    ..clear()
                                    ..addAll(_robustness);
                                }),
                        icon: const Icon(Icons.bug_report),
                        label: Text(localizations.emv_emulator_robustness),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Custom rule
                  TextField(
                    controller: _cmd,
                    decoration: const InputDecoration(
                        labelText: 'Command prefix (hex)',
                        border: OutlineInputBorder()),
                    style: const TextStyle(fontFamily: 'RobotoMono'),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _resp,
                          decoration: const InputDecoration(
                              labelText: 'Response (hex)',
                              border: OutlineInputBorder()),
                          style: const TextStyle(fontFamily: 'RobotoMono'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _busy
                            ? null
                            : () {
                                final c = _cmd.text.trim().replaceAll(' ', '');
                                final r = _resp.text.trim().replaceAll(' ', '');
                                if (c.isEmpty || r.isEmpty) return;
                                if (!_isHex(c) || !_isHex(r)) {
                                  _show(localizations.invalid_hex_input);
                                  return;
                                }
                                setState(() {
                                  _rules.add(_Rule('custom', c, r));
                                  _cmd.clear();
                                  _resp.clear();
                                });
                              },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_rules.isNotEmpty) ...[
                    Text("${localizations.emv_emulator_rules} (${_rules.length})",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ..._rules.asMap().entries.map((e) => ListTile(
                          dense: true,
                          title: Text(e.value.label,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                              "${e.value.cmd}  →  ${e.value.resp}",
                              style: const TextStyle(
                                  fontFamily: 'RobotoMono', fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            onPressed: _busy
                                ? null
                                : () =>
                                    setState(() => _rules.removeAt(e.key)),
                          ),
                        )),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _arm,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(localizations.emv_emulator_arm),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _clear,
                        icon: const Icon(Icons.clear),
                        label: Text(localizations.clear),
                      ),
                    ],
                  ),
                  if (_armed) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Text(localizations.emv_emulator_armed_hint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontStyle: FontStyle.italic)),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
