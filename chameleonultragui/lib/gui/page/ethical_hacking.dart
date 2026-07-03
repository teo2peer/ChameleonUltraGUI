import 'package:chameleonultragui/gui/component/element_button.dart';
import 'package:chameleonultragui/gui/menu/hacking/apdu_terminal.dart';
import 'package:chameleonultragui/gui/menu/hacking/auth_trace.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn.dart';
import 'package:chameleonultragui/gui/menu/hacking/backdoor.dart';
import 'package:chameleonultragui/gui/menu/hacking/darkside.dart';
import 'package:chameleonultragui/gui/menu/hacking/desfire_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/mfkey_manual.dart';
import 'package:chameleonultragui/gui/menu/hacking/nested.dart';
import 'package:chameleonultragui/gui/menu/hacking/ntag_password_capture.dart';
import 'package:chameleonultragui/gui/menu/hacking/value_block.dart';
import 'package:chameleonultragui/gui/menu/hacking/wiegand.dart';
import 'package:chameleonultragui/gui/menu/pages/mfkey32.dart';
import 'package:chameleonultragui/gui/menu/tools/hf_sniffing.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/reader_keys.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class _Attack {
  final String name;
  final String description;
  final IconData icon;
  final bool deviceRequired;
  final void Function(BuildContext) open;
  _Attack(this.name, this.description, this.icon, this.open,
      {this.deviceRequired = false});
}

class EthicalHackingPage extends StatefulWidget {
  const EthicalHackingPage({super.key});

  @override
  EthicalHackingPageState createState() => EthicalHackingPageState();
}

class EthicalHackingPageState extends State<EthicalHackingPage> {
  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _dialog(BuildContext context, Widget dialog) {
    showDialog(context: context, builder: (_) => dialog);
  }

  Widget _tile(BuildContext context, _Attack a, int index) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    final disconnected = a.deviceRequired && !appState.connector!.connected;
    return Stack(
      children: [
        ElementButton(
          icon: a.icon,
          iconColor: Theme.of(context).colorScheme.primary,
          firstLine: a.name,
          secondLine: a.description,
          itemIndex: index,
          maxLineLines: 3,
          onPressed: (!a.deviceRequired || appState.connector!.connected)
              ? () => a.open(context)
              : null,
          children: const [],
        ),
        if (disconnected)
          Positioned(
            top: 8,
            right: 8,
            child: _badge(context, localizations.device_required),
          ),
      ],
    );
  }

  Widget _badge(BuildContext context, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.inversePrimary,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );

  Widget _section(BuildContext context, String title, List<_Attack> attacks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
        ),
        AlignedGridView.count(
          clipBehavior: Clip.antiAlias,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 2 : 1,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          itemCount: attacks.length,
          shrinkWrap: true,
          itemBuilder: (context, index) => _tile(context, attacks[index], index),
        ),
      ],
    );
  }

  Widget _disclaimer(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gpp_maybe,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(localizations.ethical_hacking_disclaimer_title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(localizations.ethical_hacking_disclaimer,
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                appState.sharedPreferencesProvider.setEthicalHackingAck(true);
                setState(() {});
              },
              child: Text(localizations.accept),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    if (!appState.sharedPreferencesProvider.getEthicalHackingAck()) {
      return Scaffold(
        appBar: AppBar(title: Text(localizations.ethical_hacking)),
        body: _disclaimer(context),
      );
    }

    final mfc = <_Attack>[
      _Attack(localizations.autopwn, localizations.autopwn_description,
          Icons.bolt, (c) => _push(c, const AutopwnPage()),
          deviceRequired: true),
      _Attack(
          localizations.dictionary_check,
          localizations.dictionary_check_description,
          Icons.menu_book,
          (c) => _push(c, const AutopwnPage(dictionaryOnly: true)),
          deviceRequired: true),
      _Attack("Darkside", localizations.darkside_description, Icons.dark_mode,
          (c) => _push(c, const DarksidePage()),
          deviceRequired: true),
      _Attack("Nested", localizations.nested_description, Icons.layers,
          (c) => _push(c, const NestedPage()),
          deviceRequired: true),
      _Attack("Static Nested", localizations.static_nested_description,
          Icons.lock_clock,
          (c) => _push(c, const NestedPage(variant: NestedVariant.staticNonce)),
          deviceRequired: true),
      _Attack("Hardnested", localizations.hardnested_description, Icons.memory,
          (c) => _push(c, const NestedPage(variant: NestedVariant.hard)),
          deviceRequired: true),
      _Attack("Backdoor (RF08S)", localizations.backdoor_rf08s_description,
          Icons.door_back_door, (c) => _push(c, const BackdoorPage()),
          deviceRequired: true),
      _Attack(localizations.read_card, localizations.recover_keys,
          Icons.sensors, (c) => _push(c, const ReadCardPage()),
          deviceRequired: true),
      _Attack(localizations.mfkey_manual, localizations.mfkey_manual_description,
          Icons.vpn_key, (c) => _dialog(c, const MfkeyManualMenu())),
    ];

    final capture = <_Attack>[
      _Attack(
          localizations.reader_keys_capture,
          localizations.mfkey_manual_description,
          Icons.wifi_tethering,
          (c) => _push(c, const ReaderKeysPage()),
          deviceRequired: true),
      _Attack(localizations.hf_sniffing, localizations.hf_sniffing_description,
          Icons.radar, (c) => _dialog(c, const HfSniffingMenu()),
          deviceRequired: true),
      _Attack(localizations.ntag_password_capture,
          localizations.ntag_password_capture_description, Icons.password,
          (c) => _push(c, const NtagPasswordCapturePage()),
          deviceRequired: true),
      _Attack("MFKey32", localizations.mfkey_manual_description, Icons.key,
          (c) => _push(c, const Mfkey32Menu()),
          deviceRequired: true),
    ];

    final emulation = <_Attack>[
      _Attack(localizations.value_block_tool,
          localizations.value_block_description, Icons.exposure,
          (c) => _dialog(c, const ValueBlockMenu()),
          deviceRequired: true),
      _Attack(localizations.write_card, localizations.write_card,
          Icons.system_update_alt, (c) => _push(c, const WriteCardPage()),
          deviceRequired: true),
      _Attack(localizations.wiegand_decoder,
          localizations.wiegand_decoder_description, Icons.numbers,
          (c) => _dialog(c, const WiegandMenu())),
    ];

    final diagnostics = <_Attack>[
      _Attack(localizations.auth_trace, localizations.auth_trace_description,
          Icons.timeline, (c) => _push(c, const AuthTracePage()),
          deviceRequired: true),
      _Attack(localizations.apdu_terminal, localizations.apdu_terminal_description,
          Icons.terminal, (c) => _push(c, const ApduTerminalPage()),
          deviceRequired: true),
      _Attack(localizations.emv_reader, localizations.emv_reader_description,
          Icons.contactless, (c) => _push(c, const EmvReaderPage()),
          deviceRequired: true),
      _Attack(localizations.desfire_reader, localizations.desfire_reader_description,
          Icons.storage, (c) => _push(c, const DesfireReaderPage()),
          deviceRequired: true),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(localizations.ethical_hacking)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(context, localizations.mfc_attacks, mfc),
            _section(context, localizations.capture_sniffing, capture),
            _section(context, localizations.emulation_magic, emulation),
            _section(context, localizations.diagnostics, diagnostics),
          ],
        ),
      ),
    );
  }
}
