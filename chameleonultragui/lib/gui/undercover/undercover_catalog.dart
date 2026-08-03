import 'package:chameleonultragui/gui/undercover/undercover_dashboards.dart';
import 'package:chameleonultragui/gui/undercover/undercover_launcher.dart';
import 'package:chameleonultragui/gui/page/ethical_hacking.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
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
  return [
    UndercoverMenuScreen(
      id: 'home',
      title: 'Select Card',
      subtitle: 'Your lists for today',
      icon: Icons.home_filled,
      accent: const Color(0xFF0A84FF),
      dashboardBuilder: (_) => const UndercoverSlotsDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'markets',
      title: 'Key Recovery',
      subtitle: 'Weekly review and completed items',
      icon: Icons.checklist_rounded,
      accent: const Color(0xFF30D158),
      dashboardBuilder: (_) => const UndercoverRecoveryDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'recorder',
      title: 'HF Capture',
      subtitle: 'Notes and recent activity',
      icon: Icons.edit_note_rounded,
      accent: const Color(0xFFFF453A),
      dashboardBuilder: (_) => const UndercoverCaptureDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'studio',
      title: 'Emulation',
      subtitle: 'Plans you can start anytime',
      icon: Icons.event_repeat_rounded,
      accent: const Color(0xFFBF5AF2),
      dashboardBuilder: (_) => const UndercoverEmulationDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'signals',
      title: 'HF Sniffing',
      subtitle: 'A simple history of updates',
      icon: Icons.history_rounded,
      accent: const Color(0xFF64D2FF),
      dashboardBuilder: (_) => const UndercoverSniffDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'tools',
      title: localizations.tools,
      subtitle: 'Tool folders by category',
      icon: Icons.folder_rounded,
      accent: const Color(0xFFFF9F0A),
      apps: [
        UndercoverAppEntry(
          id: 'folder-pm3',
          title: localizations.pm3_tools,
          menuPath: localizations.tools,
          icon: Icons.folder_rounded,
          accent: const Color(0xFF0A84FF),
          opensDirectly: true,
          onOpen: () => openPage(
            context,
            localizations.pm3_tools,
            ModuleId.pm3Catalog,
            const EthicalHackingPage(initialSection: EthicalHackingSection.pm3),
            requiresConnection: false,
            requiresEthicalAck: true,
          ),
        ),
        UndercoverAppEntry(
          id: 'folder-mifare',
          title: localizations.mfc_attacks,
          menuPath: localizations.tools,
          icon: Icons.folder_rounded,
          accent: const Color(0xFFBF5AF2),
          opensDirectly: true,
          onOpen: () => openPage(
            context,
            localizations.mfc_attacks,
            ModuleId.mifareClassicAttacks,
            const EthicalHackingPage(
              initialSection: EthicalHackingSection.mifareClassic,
            ),
            requiresConnection: false,
            requiresEthicalAck: true,
          ),
        ),
        UndercoverAppEntry(
          id: 'folder-capture',
          title: localizations.capture_sniffing,
          menuPath: localizations.tools,
          icon: Icons.folder_rounded,
          accent: const Color(0xFFFF453A),
          opensDirectly: true,
          onOpen: () => openPage(
            context,
            localizations.capture_sniffing,
            ModuleId.captureAndSniffing,
            const EthicalHackingPage(
              initialSection: EthicalHackingSection.captureAndSniffing,
            ),
            requiresConnection: false,
            requiresEthicalAck: true,
          ),
        ),
        UndercoverAppEntry(
          id: 'folder-emulation',
          title: localizations.emulation_magic,
          menuPath: localizations.tools,
          icon: Icons.folder_rounded,
          accent: const Color(0xFF30D158),
          opensDirectly: true,
          onOpen: () => openPage(
            context,
            localizations.emulation_magic,
            ModuleId.emulationAndMagic,
            const EthicalHackingPage(
              initialSection: EthicalHackingSection.emulationAndMagic,
            ),
            requiresConnection: false,
            requiresEthicalAck: true,
          ),
        ),
        UndercoverAppEntry(
          id: 'folder-diagnostics',
          title: localizations.diagnostics,
          menuPath: localizations.tools,
          icon: Icons.folder_rounded,
          accent: const Color(0xFFFF9F0A),
          opensDirectly: true,
          onOpen: () => openPage(
            context,
            localizations.diagnostics,
            ModuleId.protocolDiagnostics,
            const EthicalHackingPage(
              initialSection: EthicalHackingSection.protocolDiagnostics,
            ),
            requiresConnection: false,
            requiresEthicalAck: true,
          ),
        ),
        UndercoverAppEntry(
          id: 'folder-bluetooth',
          title: localizations.bluetooth,
          menuPath: localizations.tools,
          icon: Icons.folder_rounded,
          accent: const Color(0xFF64D2FF),
          opensDirectly: true,
          onOpen: () => openPage(
            context,
            localizations.bluetooth,
            ModuleId.bluetoothLab,
            const EthicalHackingPage(
              initialSection: EthicalHackingSection.bluetooth,
            ),
            requiresConnection: false,
            requiresEthicalAck: true,
          ),
        ),
      ],
    ),
  ];
}
