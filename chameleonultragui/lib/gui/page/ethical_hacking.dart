import 'package:chameleonultragui/gui/component/element_button.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/menu/hacking/apdu_terminal.dart';
import 'package:chameleonultragui/gui/menu/hacking/auth_trace.dart';
import 'package:chameleonultragui/gui/menu/hacking/authorized_relay_lab.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn_plus.dart';
import 'package:chameleonultragui/gui/menu/hacking/backdoor.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_app.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_audit.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_advertising_lab.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_radio_identity.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_stress.dart';
import 'package:chameleonultragui/gui/menu/hacking/category_page.dart';
import 'package:chameleonultragui/gui/menu/hacking/darkside.dart';
import 'package:chameleonultragui/gui/menu/hacking/desfire_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_emulator.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_transaction.dart';
import 'package:chameleonultragui/gui/menu/hacking/keyboard_payload.dart';
import 'package:chameleonultragui/gui/menu/hacking/mfkey_manual.dart';
import 'package:chameleonultragui/gui/menu/hacking/nested.dart';
import 'package:chameleonultragui/gui/menu/hacking/ntag_password_capture.dart';
import 'package:chameleonultragui/gui/menu/hacking/relay_resistance_lab.dart';
import 'package:chameleonultragui/gui/menu/hacking/transit_gate_test.dart';
import 'package:chameleonultragui/gui/menu/hacking/value_block.dart';
import 'package:chameleonultragui/gui/menu/hacking/wiegand.dart';
import 'package:chameleonultragui/gui/menu/pages/mfkey32.dart';
import 'package:chameleonultragui/gui/menu/tools/hf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/pm3_tools.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/reader_keys.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// A top-level Ethical-Hacking category. Tapping the tile drills into the
/// tools it groups (a [HackingCategoryPage], or a dedicated hub such as the
/// BLE app).
class _Category {
  final String name;
  final IconData icon;
  final int count;
  final void Function(BuildContext) open;

  _Category(this.name, this.icon, this.open, {required this.count});
}

class EthicalHackingPage extends StatefulWidget {
  const EthicalHackingPage({super.key});

  @override
  EthicalHackingPageState createState() => EthicalHackingPageState();
}

class EthicalHackingPageState extends State<EthicalHackingPage> {
  void _push(BuildContext context, Widget page, {required ModuleId moduleId}) {
    Navigator.push(
      context,
      ModulePageRoute(moduleId: moduleId, builder: (_) => page),
    );
  }

  void _dialog(BuildContext context, Widget dialog, ModuleId moduleId) {
    showDialog(
      context: context,
      routeSettings: RouteSettings(arguments: moduleId),
      builder: (_) => dialog,
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
            Icon(
              Icons.gpp_maybe,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              localizations.ethical_hacking_disclaimer_title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              localizations.ethical_hacking_disclaimer,
              textAlign: TextAlign.center,
            ),
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

    final mfc = <HackingAttack>[
      HackingAttack(
        localizations.autopwn,
        localizations.autopwn_description,
        Icons.bolt,
        (c) => _push(c, const AutopwnPage(), moduleId: ModuleId.autopwn),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.autopwn_plus,
        localizations.autopwn_plus_description,
        Icons.auto_awesome,
        (c) =>
            _push(c, const AutopwnPlusPage(), moduleId: ModuleId.autopwnPlus),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.dictionary_check,
        localizations.dictionary_check_description,
        Icons.menu_book,
        (c) => _push(
          c,
          const AutopwnPage(dictionaryOnly: true),
          moduleId: ModuleId.dictionaryCheck,
        ),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.darkside,
        localizations.darkside_description,
        Icons.dark_mode,
        (c) => _push(c, const DarksidePage(), moduleId: ModuleId.darkside),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.nested,
        localizations.nested_description,
        Icons.layers,
        (c) => _push(c, const NestedPage(), moduleId: ModuleId.nested),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.static_nested,
        localizations.static_nested_description,
        Icons.lock_clock,
        (c) => _push(
          c,
          const NestedPage(variant: NestedVariant.staticNonce),
          moduleId: ModuleId.staticNested,
        ),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.hardnested,
        localizations.hardnested_description,
        Icons.memory,
        (c) => _push(
          c,
          const NestedPage(variant: NestedVariant.hard),
          moduleId: ModuleId.hardnested,
        ),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.backdoor_rf08s,
        localizations.backdoor_rf08s_description,
        Icons.door_back_door,
        (c) => _push(c, const BackdoorPage(), moduleId: ModuleId.backdoorRf08s),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.read_card,
        localizations.recover_keys,
        Icons.sensors,
        (c) => _push(c, const ReadCardPage(), moduleId: ModuleId.readCard),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.mfkey_manual,
        localizations.mfkey_manual_description,
        Icons.vpn_key,
        (c) => _dialog(c, const MfkeyManualMenu(), ModuleId.mfkeyManual),
      ),
    ];

    final capture = <HackingAttack>[
      HackingAttack(
        localizations.reader_keys_capture,
        localizations.mfkey_manual_description,
        Icons.wifi_tethering,
        (c) => _push(
          c,
          const ReaderKeysPage(),
          moduleId: ModuleId.readerKeysCapture,
        ),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.hf_sniffing,
        localizations.hf_sniffing_description,
        Icons.radar,
        (c) => _dialog(c, const HfSniffingMenu(), ModuleId.hfSniffing),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.ntag_password_capture,
        localizations.ntag_password_capture_description,
        Icons.password,
        (c) => _push(
          c,
          const NtagPasswordCapturePage(),
          moduleId: ModuleId.ntagPasswordCapture,
        ),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.mfkey32,
        localizations.mfkey_manual_description,
        Icons.key,
        (c) => _push(c, const Mfkey32Menu(), moduleId: ModuleId.mfkey32),
        deviceRequired: true,
      ),
    ];

    final emulation = <HackingAttack>[
      HackingAttack(
        localizations.value_block_tool,
        localizations.value_block_description,
        Icons.exposure,
        (c) => _dialog(c, const ValueBlockMenu(), ModuleId.valueBlock),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.write_card,
        localizations.write_card,
        Icons.system_update_alt,
        (c) => _push(c, const WriteCardPage(), moduleId: ModuleId.writeCard),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.wiegand_decoder,
        localizations.wiegand_decoder_description,
        Icons.numbers,
        (c) => _dialog(c, const WiegandMenu(), ModuleId.wiegand),
      ),
      HackingAttack(
        localizations.emv_emulator,
        localizations.emv_emulator_description,
        Icons.sim_card,
        (c) =>
            _push(c, const EmvEmulatorPage(), moduleId: ModuleId.emvEmulator),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.keyboard_payload,
        localizations.keyboard_payload_description,
        Icons.keyboard,
        (c) => _push(
          c,
          const KeyboardPayloadPage(),
          moduleId: ModuleId.keyboardPayload,
        ),
        deviceRequired: true,
      ),
    ];

    final diagnostics = <HackingAttack>[
      HackingAttack(
        localizations.authorized_relay_title,
        localizations.authorized_relay_description,
        Icons.account_balance_wallet,
        (c) => _push(
          c,
          const AuthorizedRelayLabPage(),
          moduleId: ModuleId.authorizedRelay,
        ),
      ),
      HackingAttack(
        'Synthetic relay-resistance lab',
        'Private-AID Android HCE forwarding with strict payment-traffic rejection and timing reports',
        Icons.security,
        (c) => _push(
          c,
          const RelayResistanceLabPage(),
          moduleId: ModuleId.relayResistance,
        ),
      ),
      HackingAttack(
        localizations.auth_trace,
        localizations.auth_trace_description,
        Icons.timeline,
        (c) => _push(c, const AuthTracePage(), moduleId: ModuleId.authTrace),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.apdu_terminal,
        localizations.apdu_terminal_description,
        Icons.terminal,
        (c) =>
            _push(c, const ApduTerminalPage(), moduleId: ModuleId.apduTerminal),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.emv_reader,
        localizations.emv_reader_description,
        Icons.contactless,
        (c) => _push(c, const EmvReaderPage(), moduleId: ModuleId.emvReader),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.purchase_sim,
        localizations.purchase_sim_description,
        Icons.point_of_sale,
        (c) => _push(
          c,
          const EmvTransactionPage(),
          moduleId: ModuleId.emvTransaction,
        ),
        deviceRequired: true,
      ),
      HackingAttack(
        'Transit gate lab',
        'Test whether an operator-locked phone exposes an EMV wallet and '
            'capture one authorised transit-profile transaction attempt',
        Icons.directions_subway,
        (c) => _push(
          c,
          const TransitGateTestPage(),
          moduleId: ModuleId.transitGate,
        ),
        deviceRequired: true,
      ),
      HackingAttack(
        localizations.desfire_reader,
        localizations.desfire_reader_description,
        Icons.storage,
        (c) => _push(
          c,
          const DesfireReaderPage(),
          moduleId: ModuleId.desfireReader,
        ),
        deviceRequired: true,
      ),
    ];

    final categories = <_Category>[
      _Category(
        localizations.pm3_tools,
        Icons.developer_board,
        (c) => _push(c, const Pm3ToolsPage(), moduleId: ModuleId.pm3Catalog),
        count: pm3OperationalToolCount,
      ),
      _Category(
        localizations.mfc_attacks,
        Icons.vpn_key,
        (c) => _push(
          c,
          HackingCategoryPage(title: localizations.mfc_attacks, attacks: mfc),
          moduleId: ModuleId.mifareClassicAttacks,
        ),
        count: mfc.length,
      ),
      _Category(
        localizations.capture_sniffing,
        Icons.wifi_tethering,
        (c) => _push(
          c,
          HackingCategoryPage(
            title: localizations.capture_sniffing,
            attacks: capture,
          ),
          moduleId: ModuleId.captureAndSniffing,
        ),
        count: capture.length,
      ),
      _Category(
        localizations.emulation_magic,
        Icons.auto_fix_high,
        (c) => _push(
          c,
          HackingCategoryPage(
            title: localizations.emulation_magic,
            attacks: emulation,
          ),
          moduleId: ModuleId.emulationAndMagic,
        ),
        count: emulation.length,
      ),
      _Category(
        localizations.diagnostics,
        Icons.troubleshoot,
        (c) => _push(
          c,
          HackingCategoryPage(
            title: localizations.diagnostics,
            attacks: diagnostics,
          ),
          moduleId: ModuleId.protocolDiagnostics,
        ),
        count: diagnostics.length,
      ),
      _Category(
        localizations.bluetooth,
        Icons.bluetooth,
        (c) => _push(
          c,
          const BleAppPage(
            auditTab: BleAuditPage(embedded: true),
            radioIdentityTab: BleRadioIdentityPage(embedded: true),
            advertisingLabTab: BleAdvertisingLabPage(embedded: true),
            stressBroadcastTab: BleStressPage(embedded: true),
          ),
          moduleId: ModuleId.bleAudit,
        ),
        count: 4,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(localizations.ethical_hacking)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: AlignedGridView.count(
          clipBehavior: Clip.antiAlias,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 2 : 1,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          itemCount: categories.length,
          shrinkWrap: true,
          itemBuilder: (context, index) {
            final cat = categories[index];
            return ElementButton(
              icon: cat.icon,
              iconColor: Theme.of(context).colorScheme.primary,
              firstLine: cat.name,
              secondLine: localizations.tools_count(cat.count),
              itemIndex: index,
              maxLineLines: 2,
              onPressed: () => cat.open(context),
              children: const [],
            );
          },
        ),
      ),
    );
  }
}
