import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/apdu_terminal.dart';
import 'package:chameleonultragui/gui/menu/hacking/auth_trace.dart';
import 'package:chameleonultragui/gui/menu/hacking/authorized_relay_lab.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn_plus.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn_v2.dart';
import 'package:chameleonultragui/gui/menu/hacking/backdoor.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_advertising_lab.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_app.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_audit.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_radio_identity.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_stress.dart';
import 'package:chameleonultragui/gui/menu/hacking/darkside.dart';
import 'package:chameleonultragui/gui/menu/hacking/desfire_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_emulator.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_transaction.dart';
import 'package:chameleonultragui/gui/menu/hacking/keyboard_payload.dart';
import 'package:chameleonultragui/gui/menu/hacking/nested.dart';
import 'package:chameleonultragui/gui/menu/hacking/ntag_password_capture.dart';
import 'package:chameleonultragui/gui/menu/hacking/relay_resistance_lab.dart';
import 'package:chameleonultragui/gui/menu/hacking/transit_gate_test.dart';
import 'package:chameleonultragui/gui/menu/tools/pm3_tools.dart';
import 'package:chameleonultragui/gui/page/data_sync.dart';
import 'package:chameleonultragui/gui/undercover/undercover_launcher.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:flutter/material.dart';

typedef UndercoverRootOpener =
    void Function(int index, String label, {required bool requiresConnection});
typedef UndercoverPageOpener =
    void Function(
      BuildContext context,
      String label,
      ModuleId moduleId,
      Widget page, {
      required bool requiresConnection,
      required bool requiresEthicalAck,
    });

List<UndercoverMenuScreen> buildUndercoverCatalog(
  BuildContext context, {
  required UndercoverRootOpener openRoot,
  required UndercoverPageOpener openPage,
}) {
  final localizations = AppLocalizations.of(context)!;

  UndercoverAppEntry root({
    required String id,
    required String title,
    required String menu,
    required IconData icon,
    required Color accent,
    required int index,
    bool requiresConnection = false,
  }) => UndercoverAppEntry(
    id: id,
    title: title,
    menuPath: menu,
    icon: icon,
    accent: accent,
    requiresConnection: requiresConnection,
    onOpen: () =>
        openRoot(index, title, requiresConnection: requiresConnection),
  );

  UndercoverAppEntry page({
    required String id,
    required String title,
    required String menu,
    required IconData icon,
    required Color accent,
    required ModuleId moduleId,
    required Widget child,
    bool requiresConnection = true,
    bool requiresEthicalAck = true,
  }) => UndercoverAppEntry(
    id: id,
    title: title,
    menuPath: menu,
    icon: icon,
    accent: accent,
    requiresConnection: requiresConnection,
    onOpen: () => openPage(
      context,
      title,
      moduleId,
      child,
      requiresConnection: requiresConnection,
      requiresEthicalAck: requiresEthicalAck,
    ),
  );

  final ethical = localizations.ethical_hacking;
  final recovery = '$ethical / MIFARE Classic';
  final capture = '$ethical / Capture';
  final diagnostics = '$ethical / ${localizations.diagnostics}';

  return [
    UndercoverMenuScreen(
      id: 'device',
      title: localizations.home,
      subtitle: 'Device, slots, reading, writing and reader capture',
      icon: Icons.memory_rounded,
      accent: const Color(0xFF38BDF8),
      apps: [
        root(
          id: 'home',
          title: localizations.home,
          menu: localizations.home,
          icon: Icons.dashboard_rounded,
          accent: const Color(0xFF38BDF8),
          index: 0,
        ),
        root(
          id: 'slot-manager',
          title: localizations.slot_manager,
          menu: localizations.home,
          icon: Icons.grid_view_rounded,
          accent: const Color(0xFF818CF8),
          index: 1,
          requiresConnection: true,
        ),
        root(
          id: 'read-card',
          title: localizations.read_card,
          menu: localizations.home,
          icon: Icons.sensors_rounded,
          accent: const Color(0xFF22C55E),
          index: 3,
          requiresConnection: true,
        ),
        root(
          id: 'write-card',
          title: localizations.write_card,
          menu: localizations.home,
          icon: Icons.system_update_alt_rounded,
          accent: const Color(0xFFF59E0B),
          index: 4,
          requiresConnection: true,
        ),
        root(
          id: 'reader-keys',
          title: localizations.reader_keys_capture,
          menu: localizations.home,
          icon: Icons.vpn_key_rounded,
          accent: const Color(0xFFE879F9),
          index: 7,
          requiresConnection: true,
        ),
      ],
    ),
    UndercoverMenuScreen(
      id: 'library',
      title: localizations.saved_cards,
      subtitle: 'Cards, dictionaries, portable data and application settings',
      icon: Icons.folder_copy_rounded,
      accent: const Color(0xFF60A5FA),
      apps: [
        root(
          id: 'saved-cards',
          title: localizations.saved_cards,
          menu: localizations.saved_cards,
          icon: Icons.auto_awesome_motion_rounded,
          accent: const Color(0xFF60A5FA),
          index: 2,
        ),
        root(
          id: 'settings',
          title: localizations.settings,
          menu: localizations.saved_cards,
          icon: Icons.tune_rounded,
          accent: const Color(0xFF94A3B8),
          index: 6,
        ),
        page(
          id: 'data-sync',
          title: 'Data Sync',
          menu: '${localizations.saved_cards} / Data Sync',
          icon: Icons.sync_rounded,
          accent: const Color(0xFF2DD4BF),
          moduleId: ModuleId.dataSync,
          child: const DataSyncPage(),
          requiresConnection: false,
          requiresEthicalAck: false,
        ),
      ],
    ),
    UndercoverMenuScreen(
      id: 'recovery',
      title: 'Recovery',
      subtitle: 'MIFARE Classic recovery workflows and verified evidence',
      icon: Icons.key_rounded,
      accent: const Color(0xFFF97316),
      apps: [
        root(
          id: 'ethical-hacking',
          title: ethical,
          menu: ethical,
          icon: Icons.security_rounded,
          accent: const Color(0xFFEF4444),
          index: 8,
        ),
        page(
          id: 'autopwn',
          title: 'Autopwn',
          menu: recovery,
          icon: Icons.bolt_rounded,
          accent: const Color(0xFFF97316),
          moduleId: ModuleId.autopwn,
          child: const AutopwnPage(),
        ),
        page(
          id: 'autopwn-plus',
          title: 'Autopwn+',
          menu: recovery,
          icon: Icons.auto_awesome_rounded,
          accent: const Color(0xFFFB7185),
          moduleId: ModuleId.autopwnPlus,
          child: const AutopwnPlusPage(),
        ),
        page(
          id: 'autopwn-v2',
          title: 'Autopwn v2',
          menu: recovery,
          icon: Icons.account_tree_rounded,
          accent: const Color(0xFFA78BFA),
          moduleId: ModuleId.autopwnV2,
          child: const AutopwnV2Page(),
        ),
        page(
          id: 'dictionary-check',
          title: 'Dictionary Check',
          menu: recovery,
          icon: Icons.menu_book_rounded,
          accent: const Color(0xFF38BDF8),
          moduleId: ModuleId.dictionaryCheck,
          child: const AutopwnPage(dictionaryOnly: true),
        ),
        page(
          id: 'darkside',
          title: 'Darkside',
          menu: recovery,
          icon: Icons.dark_mode_rounded,
          accent: const Color(0xFF64748B),
          moduleId: ModuleId.darkside,
          child: const DarksidePage(),
        ),
        page(
          id: 'nested',
          title: 'Nested',
          menu: recovery,
          icon: Icons.layers_rounded,
          accent: const Color(0xFF22C55E),
          moduleId: ModuleId.nested,
          child: const NestedPage(),
        ),
        page(
          id: 'static-nested',
          title: 'Static Nested',
          menu: recovery,
          icon: Icons.layers_clear_rounded,
          accent: const Color(0xFF14B8A6),
          moduleId: ModuleId.staticNested,
          child: const NestedPage(variant: NestedVariant.staticNonce),
        ),
        page(
          id: 'hardnested',
          title: 'Hardnested',
          menu: recovery,
          icon: Icons.hub_rounded,
          accent: const Color(0xFFEAB308),
          moduleId: ModuleId.hardnested,
          child: const NestedPage(variant: NestedVariant.hard),
        ),
        page(
          id: 'backdoor',
          title: 'RF08S Backdoor',
          menu: recovery,
          icon: Icons.meeting_room_rounded,
          accent: const Color(0xFFEC4899),
          moduleId: ModuleId.backdoorRf08s,
          child: const BackdoorPage(),
        ),
      ],
    ),
    UndercoverMenuScreen(
      id: 'capture',
      title: 'Capture & Emulation',
      subtitle: 'Reader capture, payloads, emulation and wireless tools',
      icon: Icons.radar_rounded,
      accent: const Color(0xFF2DD4BF),
      apps: [
        root(
          id: 'capture-reader-keys',
          title: localizations.reader_keys_capture,
          menu: capture,
          icon: Icons.key_rounded,
          accent: const Color(0xFF2DD4BF),
          index: 7,
          requiresConnection: true,
        ),
        page(
          id: 'ntag-password',
          title: 'NTAG Password Capture',
          menu: capture,
          icon: Icons.password_rounded,
          accent: const Color(0xFF38BDF8),
          moduleId: ModuleId.ntagPasswordCapture,
          child: const NtagPasswordCapturePage(),
        ),
        page(
          id: 'keyboard-payload',
          title: 'Keyboard Payload',
          menu: '$ethical / Emulation',
          icon: Icons.keyboard_rounded,
          accent: const Color(0xFFA78BFA),
          moduleId: ModuleId.keyboardPayload,
          child: const KeyboardPayloadPage(),
        ),
        page(
          id: 'emv-emulator',
          title: 'EMV Emulator',
          menu: '$ethical / Emulation',
          icon: Icons.credit_card_rounded,
          accent: const Color(0xFFF59E0B),
          moduleId: ModuleId.emvEmulator,
          child: const EmvEmulatorPage(),
        ),
        page(
          id: 'bluetooth-app',
          title: localizations.bluetooth_app,
          menu: '$ethical / ${localizations.bluetooth}',
          icon: Icons.bluetooth_rounded,
          accent: const Color(0xFF60A5FA),
          moduleId: ModuleId.bleAudit,
          child: const BleAppPage(
            auditTab: BleAuditPage(embedded: true),
            radioIdentityTab: BleRadioIdentityPage(embedded: true),
            advertisingLabTab: BleAdvertisingLabPage(embedded: true),
            stressBroadcastTab: BleStressPage(embedded: true),
          ),
        ),
      ],
    ),
    UndercoverMenuScreen(
      id: 'tools',
      title: localizations.tools,
      subtitle: 'General utilities, PM3 workflows and offline analysis',
      icon: Icons.handyman_rounded,
      accent: const Color(0xFF84CC16),
      apps: [
        root(
          id: 'tools-root',
          title: localizations.tools,
          menu: localizations.tools,
          icon: Icons.build_circle_rounded,
          accent: const Color(0xFF84CC16),
          index: 5,
        ),
        page(
          id: 'pm3-tools',
          title: 'PM3 Tools',
          menu: '${localizations.tools} / PM3',
          icon: Icons.terminal_rounded,
          accent: const Color(0xFF22C55E),
          moduleId: ModuleId.pm3Catalog,
          child: const Pm3ToolsPage(),
          requiresConnection: false,
        ),
        root(
          id: 'tools-settings',
          title: localizations.settings,
          menu: localizations.tools,
          icon: Icons.widgets_rounded,
          accent: const Color(0xFF94A3B8),
          index: 6,
        ),
        page(
          id: 'tools-data-sync',
          title: 'Data Sync',
          menu: '${localizations.tools} / Data Sync',
          icon: Icons.cloud_sync_rounded,
          accent: const Color(0xFF06B6D4),
          moduleId: ModuleId.dataSync,
          child: const DataSyncPage(),
          requiresConnection: false,
          requiresEthicalAck: false,
        ),
      ],
    ),
    UndercoverMenuScreen(
      id: 'diagnostics',
      title: localizations.diagnostics,
      subtitle: 'Protocol, payment, relay and smart-card diagnostics',
      icon: Icons.monitor_heart_rounded,
      accent: const Color(0xFFFB7185),
      apps: [
        page(
          id: 'auth-trace',
          title: 'Auth Trace',
          menu: diagnostics,
          icon: Icons.timeline_rounded,
          accent: const Color(0xFF38BDF8),
          moduleId: ModuleId.authTrace,
          child: const AuthTracePage(),
        ),
        page(
          id: 'apdu-terminal',
          title: 'APDU Terminal',
          menu: diagnostics,
          icon: Icons.code_rounded,
          accent: const Color(0xFF22C55E),
          moduleId: ModuleId.apduTerminal,
          child: const ApduTerminalPage(),
        ),
        page(
          id: 'emv-reader',
          title: 'EMV Reader',
          menu: diagnostics,
          icon: Icons.contactless_rounded,
          accent: const Color(0xFF60A5FA),
          moduleId: ModuleId.emvReader,
          child: const EmvReaderPage(),
        ),
        page(
          id: 'emv-transaction',
          title: 'EMV Transaction',
          menu: diagnostics,
          icon: Icons.point_of_sale_rounded,
          accent: const Color(0xFFF59E0B),
          moduleId: ModuleId.emvTransaction,
          child: const EmvTransactionPage(),
        ),
        page(
          id: 'transit-gate',
          title: 'Transit Gate Lab',
          menu: diagnostics,
          icon: Icons.directions_transit_rounded,
          accent: const Color(0xFFA78BFA),
          moduleId: ModuleId.transitGate,
          child: const TransitGateTestPage(),
        ),
        page(
          id: 'desfire-reader',
          title: 'DESFire Reader',
          menu: diagnostics,
          icon: Icons.nfc_rounded,
          accent: const Color(0xFF2DD4BF),
          moduleId: ModuleId.desfireReader,
          child: const DesfireReaderPage(),
        ),
        page(
          id: 'authorized-relay',
          title: 'Authorized Relay',
          menu: diagnostics,
          icon: Icons.cable_rounded,
          accent: const Color(0xFFEF4444),
          moduleId: ModuleId.authorizedRelay,
          child: const AuthorizedRelayLabPage(),
        ),
        page(
          id: 'relay-resistance',
          title: 'Relay Resistance',
          menu: diagnostics,
          icon: Icons.speed_rounded,
          accent: const Color(0xFFFB7185),
          moduleId: ModuleId.relayResistance,
          child: const RelayResistanceLabPage(),
        ),
      ],
    ),
  ];
}
