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
  const _Rule(this.label, this.cmd, this.resp);
}

class _Preset {
  final String label;
  final IconData icon;
  final List<_Rule> rules;
  const _Preset(this.label, this.icon, this.rules);
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

  static const String _ppse = '00A404000E';
  static const String _mcAid = '00A4040007A0000000041010';
  static const String _gpo = '80A80000';
  static const String _readRecord = '00B2';

  static String _hexFill(int value, int count) =>
      List.filled(count, value.toRadixString(16).padLeft(2, '0')).join();

  @override
  void dispose() {
    _cmd.dispose();
    _resp.dispose();
    _uid.dispose();
    super.dispose();
  }

  // A minimal, well-formed Mastercard test card with dummy test PAN data.
  static const List<_Rule> _testCard = [
    _Rule('SELECT PPSE', _ppse,
        '6F23840E325041592E5359532E4444463031A511BF0C0E610C4F07A00000000410108701019000'),
    _Rule('SELECT AID', _mcAid,
        '6F1D8407A0000000041010A512500A4D6173746572436172648701019F38009000'),
    _Rule('GPO format 1 AIP+AFL', _gpo, '80061200080101009000'),
    _Rule('READ RECORD dummy PAN', _readRecord,
        '70295A0855555555555544445F24032512315F34010157135555555555554444D25122011234567890123F9000'),
  ];

  static const List<_Rule> _syntheticRelayCard = [
    _Rule('SELECT private relay-lab AID', '00A4040007F0010203040506',
        '6F168407F0010203040506A50B500952454C4159204C41429000'),
    _Rule('Fixed challenge response (intentionally replayable)', 'F010000008',
        '8008A1A2A3A4A5A6A7A89000'),
    _Rule('Synthetic status', 'F030000000', 'DF0101019000'),
  ];

  // EMV/BER-TLV edge profiles for terminal robustness testing in an authorised
  // lab. These are standards-shaped failure modes, not vendor-specific exploits.
  static const List<_Rule> _malformedTlv = [
    _Rule('PPSE truncated FCI template', _ppse, '6F'),
    _Rule('SELECT AID truncated DF name', _mcAid, '6F058407A000'),
    _Rule('GPO invalid long-form length', _gpo, '77820020'),
    _Rule('READ RECORD truncated record template', _readRecord, '7081FF5A'),
  ];

  static const List<_Rule> _statusErrors = [
    _Rule('PPSE file not found', _ppse, '6A82'),
    _Rule('SELECT AID invalidated', _mcAid, '6283'),
    _Rule('GPO conditions not satisfied', _gpo, '6985'),
    _Rule('READ RECORD record not found', _readRecord, '6A83'),
  ];

  static const List<_Rule> _emptyAndShort = [
    _Rule('PPSE success with no FCI', _ppse, '9000'),
    _Rule('SELECT AID empty FCI', _mcAid, '6F009000'),
    _Rule('GPO empty response template', _gpo, '77009000'),
    _Rule('READ RECORD empty record template', _readRecord, '70009000'),
  ];

  static final List<_Rule> _oversized = [
    _Rule('PPSE max-size FCI body', _ppse, '6F81FF${_hexFill(0x00, 255)}9000'),
    _Rule('SELECT AID max-size FCI body', _mcAid,
        '6F81FF${_hexFill(0x41, 255)}9000'),
    _Rule(
        'GPO max-size response body', _gpo, '7781FF${_hexFill(0x00, 255)}9000'),
    _Rule('READ RECORD max-size record body', _readRecord,
        '7081FF${_hexFill(0x00, 255)}9000'),
  ];

  static const List<_Rule> _recordPressure = [
    _Rule('PPSE duplicate Mastercard AIDs', _ppse,
        '6F3D840E325041592E5359532E4444463031A52BBF0C2861124F07A000000004101087010161124F07A000000004101087010161044F07A00000000410109000'),
    _Rule('SELECT AID normal FCI', _mcAid,
        '6F1D8407A0000000041010A512500A4D6173746572436172648701019F38009000'),
    _Rule('GPO AFL extreme SFI/record range', _gpo,
        '770A820200009404F80101F89000'),
    _Rule('READ RECORD rejects every requested record', _readRecord, '6A83'),
  ];

  static final List<_Preset> _presets = [
    const _Preset('Synthetic relay lab', Icons.science, _syntheticRelayCard),
    const _Preset('Test card', Icons.credit_card, _testCard),
    const _Preset('Status errors', Icons.error_outline, _statusErrors),
    const _Preset('Empty/short data', Icons.hourglass_empty, _emptyAndShort),
    const _Preset('Malformed TLV', Icons.code, _malformedTlv),
    _Preset('Oversized APDUs', Icons.open_in_full, _oversized),
    const _Preset('Record pressure', Icons.repeat, _recordPressure),
  ];

  void _show(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  bool _isHex(String s) =>
      s.isNotEmpty && s.length.isEven && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s);

  void _loadRules(List<_Rule> rules) {
    setState(() {
      _rules
        ..clear()
        ..addAll(rules);
      _armed = false;
    });
  }

  Widget _presetButton(_Preset preset) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : () => _loadRules(preset.rules),
      icon: Icon(preset.icon),
      label: Text(preset.label),
    );
  }

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
      await _app.runSlotOperation(() async {
        final slot = await _app.communicator!.getActiveSlot();
        await _app.communicator!.setReaderDeviceMode(false);
        await _app.communicator!.setSlotType(slot, TagType.hf14a4);
        await _app.communicator!.setDefaultDataToSlot(slot, TagType.hf14a4);
        await _app.communicator!.enableSlot(slot, TagFrequency.hf, true);
        await _app.communicator!.activateSlot(slot);
        // SAK 0x20 => ISO14443-4; a small generic ATS.
        // ATQA in display order; the wrapper reverses to wire order like the
        // rest of the codebase (setMf1AntiCollision).
        await _app.communicator!.hf14a4SetAntiColl(
            uid,
            Uint8List.fromList([0x00, 0x04]),
            0x20,
            Uint8List.fromList([0x05, 0x78, 0x80, 0x70, 0x02]));
        await _app.communicator!.hf14a4ClearStaticResponses();
        for (final r in _rules) {
          await _app.communicator!.hf14a4AddStaticResponse(
              hexToBytes(r.cmd.replaceAll(' ', '')),
              hexToBytes(r.resp.replaceAll(' ', '')));
        }
      });
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
      await _app.runSlotOperation(
          () => _app.communicator!.hf14a4ClearStaticResponses());
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
                        color: Theme.of(context).colorScheme.tertiaryContainer,
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
                    children: _presets.map(_presetButton).toList(),
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
                                if (c.length ~/ 2 > 16 || r.length ~/ 2 > 260) {
                                  _show(
                                      'Firmware limit: prefix <=16 bytes, response <=260 bytes');
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
                    Text(
                        "${localizations.emv_emulator_rules} (${_rules.length})",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ..._rules.asMap().entries.map((e) => ListTile(
                          dense: true,
                          title: Text(e.value.label,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text("${e.value.cmd}  →  ${e.value.resp}",
                              style: const TextStyle(
                                  fontFamily: 'RobotoMono', fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _rules.removeAt(e.key)),
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
