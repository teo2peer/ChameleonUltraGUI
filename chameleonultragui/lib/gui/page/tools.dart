import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/compare_cards.dart';
import 'package:chameleonultragui/gui/menu/tools/dictionary_download.dart';
import 'package:chameleonultragui/gui/menu/tools/emulation_change_history.dart';
import 'package:chameleonultragui/gui/menu/tools/hf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/lf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/pm3_tools.dart';
import 'package:chameleonultragui/gui/menu/tools/t55xx_password_cleaner.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:chameleonultragui/gui/component/element_button.dart';
import 'package:chameleonultragui/gui/component/status_badge.dart';
import 'package:provider/provider.dart';

class ToolItem {
  final String name;
  final String description;
  final IconData icon;
  final ModuleId moduleId;
  final bool isDeviceRequired;
  final bool showWipBadge;
  final bool openAsPage;
  final Widget? onPressed;

  ToolItem({
    required this.name,
    required this.description,
    required this.icon,
    required this.moduleId,
    this.isDeviceRequired = false,
    this.showWipBadge = false,
    this.openAsPage = false,
    this.onPressed,
  });
}

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  ToolsPageState createState() => ToolsPageState();
}

class ToolsPageState extends State<ToolsPage> {
  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    List<ToolItem> tools = [
      ToolItem(
        name: localizations.compare_cards,
        description: localizations.compare_cards_description,
        icon: Icons.difference,
        moduleId: ModuleId.compareCards,
        onPressed: const CompareCardsMenu(),
      ),
      ToolItem(
        name: localizations.dictionary_download,
        description: localizations.dictionary_download_description,
        icon: Icons.key,
        moduleId: ModuleId.dictionaryDownload,
        onPressed: const DictionaryDownloadMenu(),
      ),
      ToolItem(
        name: 'Emulated tag history',
        description:
            'Monitor reader-written MIFARE Classic changes and keep block-level history on this phone.',
        icon: Icons.history,
        moduleId: ModuleId.emulationHistory,
        onPressed: const EmulationChangeHistoryMenu(),
      ),
      ToolItem(
        name: localizations.pm3_tools,
        description: localizations.pm3_tools_description,
        icon: Icons.developer_board,
        moduleId: ModuleId.pm3Catalog,
        onPressed: const Pm3ToolsPage(),
        openAsPage: true,
      ),
      ToolItem(
        name: localizations.t55xx_password_cleaner,
        description: localizations.t55xx_password_cleaner_description,
        icon: Icons.password,
        moduleId: ModuleId.t55xxPasswordCleaner,
        onPressed: const T55XXPasswordCleanerMenu(),
        isDeviceRequired: true,
      ),
      ToolItem(
        name: localizations.lf_sniffing,
        description: localizations.lf_sniffing_description,
        icon: Icons.graphic_eq,
        moduleId: ModuleId.lfSniffing,
        onPressed: const LfSniffingMenu(),
        isDeviceRequired: true,
      ),
      ToolItem(
        name: localizations.hf_sniffing,
        description: localizations.hf_sniffing_description,
        icon: Icons.radar,
        moduleId: ModuleId.hfSniffing,
        onPressed: const HfSniffingMenu(),
        showWipBadge: true,
        isDeviceRequired: true,
      ),
      ToolItem(
        name: localizations.mifare_classic_gen4,
        description: localizations.mifare_classic_gen4_description,
        icon: Icons.settings,
        moduleId: ModuleId.mifareClassicGen4,
        isDeviceRequired: true,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(localizations.tools)),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: AlignedGridView.count(
            clipBehavior: Clip.antiAlias,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 2 : 1,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            itemCount: tools.length,
            shrinkWrap: true,
            itemBuilder: (BuildContext context, int index) {
              final tool = tools[index];
              final disconnected =
                  tool.isDeviceRequired && !appState.connector!.connected;
              return Stack(
                children: [
                  ElementButton(
                    icon: tool.icon,
                    iconColor: Theme.of(context).colorScheme.primary,
                    firstLine: tool.name,
                    secondLine: tool.description,
                    itemIndex: index,
                    maxLineLines: 3,
                    onPressed:
                        tool.onPressed != null &&
                            (!tool.isDeviceRequired ||
                                appState.connector!.connected)
                        ? () {
                            if (tool.openAsPage) {
                              Navigator.push(
                                context,
                                ModulePageRoute(
                                  moduleId: tool.moduleId,
                                  builder: (_) => tool.onPressed!,
                                ),
                              );
                            } else {
                              showDialog(
                                context: context,
                                routeSettings: RouteSettings(
                                  arguments: tool.moduleId,
                                ),
                                builder: (BuildContext context) {
                                  return tool.onPressed!;
                                },
                              );
                            }
                          }
                        : null,
                    children: [],
                  ),
                  if (tool.showWipBadge || tool.onPressed == null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: StatusBadge(localizations.wip),
                    ),
                  if (disconnected)
                    Positioned(
                      top: tool.showWipBadge || tool.onPressed == null ? 32 : 8,
                      right: 8,
                      child: StatusBadge(localizations.device_required),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
