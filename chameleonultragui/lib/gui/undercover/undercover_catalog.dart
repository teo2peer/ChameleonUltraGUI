import 'package:chameleonultragui/gui/undercover/undercover_dashboards.dart';
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
  return [
    UndercoverMenuScreen(
      id: 'home',
      title: 'Home',
      subtitle: 'Your lists for today',
      icon: Icons.home_filled,
      accent: const Color(0xFF0A84FF),
      dashboardBuilder: (_) => const UndercoverSlotsDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'markets',
      title: 'Progress',
      subtitle: 'Weekly review and completed items',
      icon: Icons.checklist_rounded,
      accent: const Color(0xFF30D158),
      dashboardBuilder: (_) => const UndercoverRecoveryDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'recorder',
      title: 'Journal',
      subtitle: 'Notes and recent activity',
      icon: Icons.edit_note_rounded,
      accent: const Color(0xFFFF453A),
      dashboardBuilder: (_) => const UndercoverCaptureDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'studio',
      title: 'Routines',
      subtitle: 'Plans you can start anytime',
      icon: Icons.event_repeat_rounded,
      accent: const Color(0xFFBF5AF2),
      dashboardBuilder: (_) => const UndercoverEmulationDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'signals',
      title: 'Activity',
      subtitle: 'A simple history of updates',
      icon: Icons.history_rounded,
      accent: const Color(0xFF64D2FF),
      dashboardBuilder: (_) => const UndercoverSniffDashboard(),
    ),
  ];
}
