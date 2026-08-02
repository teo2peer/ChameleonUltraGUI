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
      subtitle: 'Eight positions · live allocation',
      icon: Icons.home_filled,
      accent: const Color(0xFF0A84FF),
      dashboardBuilder: (_) => const UndercoverSlotsDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'markets',
      title: 'Markets',
      subtitle: 'Portfolio health · sector weather',
      icon: Icons.candlestick_chart_rounded,
      accent: const Color(0xFF30D158),
      dashboardBuilder: (_) => const UndercoverRecoveryDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'recorder',
      title: 'Recorder',
      subtitle: 'Continuous observations · three modes',
      icon: Icons.graphic_eq_rounded,
      accent: const Color(0xFFFF453A),
      dashboardBuilder: (_) => const UndercoverCaptureDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'studio',
      title: 'Studio',
      subtitle: 'Contactless positions · live broadcast',
      icon: Icons.contactless_rounded,
      accent: const Color(0xFFBF5AF2),
      dashboardBuilder: (_) => const UndercoverEmulationDashboard(),
    ),
    UndercoverMenuScreen(
      id: 'signals',
      title: 'Signals',
      subtitle: 'Passive timeline · protocol outlook',
      icon: Icons.waves_rounded,
      accent: const Color(0xFF64D2FF),
      dashboardBuilder: (_) => const UndercoverSniffDashboard(),
    ),
  ];
}
