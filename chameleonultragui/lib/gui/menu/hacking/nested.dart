import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart' show MifareClassicInfo;
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Standalone weak-PRNG Nested attack: recover a target sector key from a known
// key. Reuses MifareClassicRecovery.recoverNestedSingle.
class NestedPage extends StatefulWidget {
  const NestedPage({super.key});

  @override
  NestedPageState createState() => NestedPageState();
}

class NestedPageState extends State<NestedPage> {
  final _knownKey = TextEditingController(text: 'FFFFFFFFFFFF');
  final _knownSector = TextEditingController(text: '0');
  final _targetSector = TextEditingController(text: '1');
  int _knownKeyType = 0; // 0=A, 1=B
  int _targetKeyType = 0;

  MifareClassicInfo? mfcInfo;
  bool running = false;
  String message = '';

  @override
  void dispose() {
    _knownKey.dispose();
    _knownSector.dispose();
    _targetSector.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _run() async {
    var localizations = AppLocalizations.of(context)!;
    setState(() {
      running = true;
      message = '';
      mfcInfo = null;
    });
    try {
      final key = hexToBytes(_knownKey.text.trim().replaceAll(' ', ''));
      if (key.length != 6) {
        setState(() => message = localizations.invalid_hex_input);
        return;
      }
      final knownSector = int.parse(_knownSector.text.trim());
      final targetSector = int.parse(_targetSector.text.trim());

      var (hfInfo, mfc, _) = await readHFInfo(context, _refresh);
      if (!hfInfo.cardExist) {
        setState(() => message = localizations.no_card_found);
        return;
      }
      if (mfc.type == MifareClassicType.none || mfc.recovery == null) {
        setState(() => message = localizations.not_mifare_classic_slot);
        return;
      }
      setState(() => mfcInfo = mfc);
      await mfc.recovery!.recoverNestedSingle(
          key, knownSector, _knownKeyType, targetSector, _targetKeyType);
      _refresh();
    } on FormatException {
      setState(() => message = localizations.invalid_hex_input);
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  bool get _hasAnyKey =>
      mfcInfo?.recovery?.validKeys.any((k) => k.isNotEmpty) ?? false;

  Widget _keyTypeToggle(int value, ValueChanged<int> onChanged) =>
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text("A")),
          ButtonSegment(value: 1, label: Text("B")),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final recovery = mfcInfo?.recovery;
    return Scaffold(
      appBar: AppBar(title: const Text("Nested")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _knownKey,
              decoration: InputDecoration(
                  labelText: "${localizations.recover_key} (known key)",
                  hintText: 'FFFFFFFFFFFF',
                  border: const OutlineInputBorder()),
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _knownSector,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: "${localizations.sector} (known)",
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                _keyTypeToggle(
                    _knownKeyType, (v) => setState(() => _knownKeyType = v)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _targetSector,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: "${localizations.sector} (target)",
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                _keyTypeToggle(
                    _targetKeyType, (v) => setState(() => _targetKeyType = v)),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: running ? null : _run,
                icon: running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(localizations.recover_key),
              ),
            ),
            const SizedBox(height: 16),
            if (message.isNotEmpty) ErrorMessage(errorMessage: message),
            if (recovery != null) ...[
              KeyCheckMarks(
                checkMarks: recovery.checkMarks,
                validKeys: recovery.validKeys,
                checkmarkCount: mfClassicGetSectorCount(recovery.mifareClassicType,
                    isEV1: recovery.isMifareClassicEV1),
              ),
              if (recovery.error.isNotEmpty) ...[
                const SizedBox(height: 12),
                ErrorMessage(errorMessage: recovery.error),
              ],
              if (recovery.state.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(recovery.state, textAlign: TextAlign.center),
              ],
              if (_hasAnyKey) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog<String>(
                      context: context,
                      builder: (context) => DictionaryExportMenu(
                          keys: recovery.validKeys
                              .where((k) => k.isNotEmpty)
                              .toList()),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: Text(localizations.save_recovered_keys),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
