import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart'
    show MifareClassicInfo;
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Standalone Static-Encrypted Nested via factory backdoor (Fudan FM11RF08S,
// eprint 2024/1275): recover all A/B keys using the backdoor, no known key.
// Reuses MifareClassicRecovery.recoverBackdoor.
class BackdoorPage extends StatefulWidget {
  const BackdoorPage({super.key});

  @override
  BackdoorPageState createState() => BackdoorPageState();
}

class BackdoorPageState extends State<BackdoorPage> {
  MifareClassicInfo? mfcInfo;
  bool running = false;
  String message = '';

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
      if (!hfInfo.cardExist) {
        setState(() => message = localizations.no_card_found);
        return;
      }
      if (mfc.type == MifareClassicType.none || mfc.recovery == null) {
        setState(() => message = localizations.not_mifare_classic_slot);
        return;
      }
      setState(() => mfcInfo = mfc);
      await mfc.recovery!.recoverBackdoor();
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
      appBar: AppBar(title: const Text("Backdoor (RF08S)")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(localizations.backdoor_rf08s_description,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
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
