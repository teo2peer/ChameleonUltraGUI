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

// Standalone Darkside attack: recover a first key (sector 0 key B) from a
// weak-PRNG card with no prior key. Reuses MifareClassicRecovery.recoverDarkside.
class DarksidePage extends StatefulWidget {
  const DarksidePage({super.key});

  @override
  DarksidePageState createState() => DarksidePageState();
}

class DarksidePageState extends State<DarksidePage> {
  MifareClassicInfo? mfcInfo;
  bool running = false;
  String message = '';
  MifareClassicRecovery? _activeRecovery;

  @override
  void dispose() {
    _activeRecovery?.cancel();
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
      await recovery.recoverDarkside();
      if (!mounted || recovery.isCancelled) return;
      _refresh();
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

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final recovery = mfcInfo?.recovery;
    return Scaffold(
      appBar: AppBar(title: const Text("Darkside")),
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
