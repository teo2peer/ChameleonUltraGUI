import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart'
    show MifareClassicInfo;
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// One-click MIFARE Classic key recovery. Reuses the existing recovery engine
// (dictionary check -> darkside -> nested/hardnested/static/backdoor -> dump).
// When [dictionaryOnly] is true it stops after the dictionary phase (fchk).
class AutopwnPage extends StatefulWidget {
  final bool dictionaryOnly;
  const AutopwnPage({super.key, this.dictionaryOnly = false});

  @override
  AutopwnPageState createState() => AutopwnPageState();
}

class AutopwnPageState extends State<AutopwnPage> {
  MifareClassicInfo? mfcInfo;
  bool running = false;
  String message = '';

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _run() async {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    setState(() {
      running = true;
      message = '';
      mfcInfo = null;
    });
    try {
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

      // checkKeys() dereferences selectedDictionary; seed it (and the saved
      // dictionaries) the same way the Read Card screen does.
      mfc.recovery!.dictionaries =
          appState.sharedPreferencesProvider.getDictionaries(keyLength: 12);
      mfc.recovery!.dictionaries
          .insert(0, Dictionary(id: "", name: localizations.empty, keys: []));
      mfc.recovery!.selectedDictionary ??= mfc.recovery!.dictionaries[0];

      await mfc.recovery!.checkKeys();
      if (!widget.dictionaryOnly && !mfc.recovery!.allKeysExists) {
        await mfc.recovery!.recoverKeys();
      }
      if (mfc.recovery!.allKeysExists) {
        await mfc.recovery!.dumpData();
      }
      _refresh();
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  bool get _hasAnyKey =>
      mfcInfo?.recovery?.validKeys.any((k) => k.isNotEmpty) ?? false;

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final recovery = mfcInfo?.recovery;

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.dictionaryOnly
              ? localizations.dictionary_check
              : localizations.autopwn)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Center(
              child: ElevatedButton.icon(
                onPressed: running ? null : _run,
                icon: running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(widget.dictionaryOnly
                    ? localizations.run_dictionary_only
                    : localizations.start_autopwn),
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
              const SizedBox(height: 12),
              if (recovery.keyCheckProgress != null)
                LinearProgressIndicator(value: recovery.keyCheckProgress),
              if (recovery.hardnestedProgress != null && recovery.error.isEmpty)
                LinearProgressIndicator(value: recovery.hardnestedProgress),
              if (recovery.dumpProgress != 0)
                LinearProgressIndicator(value: recovery.dumpProgress),
              if (recovery.allKeysExists) ...[
                const SizedBox(height: 12),
                Text(localizations.all_keys_recovered,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold)),
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
