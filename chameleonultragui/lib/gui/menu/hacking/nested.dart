import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart'
    show MifareClassicInfo;
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

enum NestedVariant { weak, staticNonce, staticEncryptedNonce, hard }

// Standalone Nested-family attack. Static-encrypted recovery uses the RF08S
// factory backdoor; the other variants recover a target key from a known key.
class NestedPage extends StatefulWidget {
  final NestedVariant variant;
  const NestedPage({super.key, this.variant = NestedVariant.weak});

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
  MifareClassicRecovery? _activeRecovery;

  bool get _usesKnownKey =>
      widget.variant != NestedVariant.staticEncryptedNonce;

  @override
  void dispose() {
    _activeRecovery?.cancel();
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
      final key = _usesKnownKey
          ? hexToBytes(_knownKey.text.trim().replaceAll(' ', ''))
          : null;
      if (_usesKnownKey && key!.length != 6) {
        setState(() => message = localizations.invalid_hex_input);
        return;
      }
      final knownSector = _usesKnownKey
          ? int.parse(_knownSector.text.trim())
          : null;
      final targetSector = _usesKnownKey
          ? int.parse(_targetSector.text.trim())
          : null;

      var (hfInfo, mfc, _) = await readHFInfo(context, _refresh);
      if (!mounted) return;
      if (!hfInfo.cardExist) {
        setState(() => message = localizations.no_card_found);
        return;
      }
      if (mfc.type == MifareClassicType.none || mfc.recovery == null) {
        setState(() => message = localizations.not_mifare_classic_slot);
        return;
      }
      final recovery = mfc.recovery!;
      _activeRecovery = recovery;
      setState(() => mfcInfo = mfc);
      switch (widget.variant) {
        case NestedVariant.weak:
          await recovery.recoverNestedSingle(
              key!, knownSector!, _knownKeyType, targetSector!, _targetKeyType);
        case NestedVariant.staticNonce:
          await recovery.recoverStaticNestedSingle(
              key!, knownSector!, _knownKeyType, targetSector!, _targetKeyType);
        case NestedVariant.staticEncryptedNonce:
          await recovery.recoverBackdoor();
        case NestedVariant.hard:
          await recovery.recoverHardnestedSingle(
              key!, knownSector!, _knownKeyType, targetSector!, _targetKeyType);
      }
      if (!mounted || recovery.isCancelled) return;
      _refresh();
    } on FormatException {
      if (mounted) setState(() => message = localizations.invalid_hex_input);
    } on MifareClassicRecoveryCancelled {
      // Page was left; stop quietly after the current command returns.
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
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

  String get _title => switch (widget.variant) {
        NestedVariant.weak => "Nested",
        NestedVariant.staticNonce => "Static Nested",
        NestedVariant.staticEncryptedNonce => "Static Encrypted Nested",
        NestedVariant.hard => "Hardnested",
      };

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final recovery = mfcInfo?.recovery;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_usesKnownKey)
              TextField(
                controller: _knownKey,
                decoration: InputDecoration(
                  labelText: "${localizations.recover_key} (known key)",
                  hintText: 'FFFFFFFFFFFF',
                  border: const OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
            if (_usesKnownKey) const SizedBox(height: 10),
            if (_usesKnownKey)
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
            if (_usesKnownKey) const SizedBox(height: 10),
            if (_usesKnownKey)
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
            if (!_usesKnownKey)
              Text(localizations.backdoor_rf08s_description,
                  textAlign: TextAlign.center),
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
                checkmarkCount: mfClassicGetSectorCount(
                    recovery.mifareClassicType,
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
              if (recovery.hardnestedProgress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: recovery.hardnestedProgress),
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
