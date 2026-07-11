import 'package:chameleonultragui/gui/component/element_button.dart';
import 'package:chameleonultragui/gui/component/status_badge.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// A single tool entry inside an Ethical-Hacking category. Used both to build
/// the category sub-pages and (via the count) the top-level category hub.
class HackingAttack {
  final String name;
  final String description;
  final IconData icon;
  final bool deviceRequired;
  final void Function(BuildContext) open;

  const HackingAttack(this.name, this.description, this.icon, this.open,
      {this.deviceRequired = false});
}

/// Responsive grid of hacking tool tiles (1 col < 700px, 2 col otherwise),
/// shared by every category sub-page. Handles the device-required
/// disable + badge behavior. Watches [ChameleonGUIState] so tiles enable /
/// disable live as the device connects or disconnects.
class HackingToolGrid extends StatelessWidget {
  final List<HackingAttack> attacks;

  const HackingToolGrid({super.key, required this.attacks});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final connected = appState.connector!.connected;

    return AlignedGridView.count(
      clipBehavior: Clip.antiAlias,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 2 : 1,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      itemCount: attacks.length,
      shrinkWrap: true,
      itemBuilder: (context, index) {
        final a = attacks[index];
        final disconnected = a.deviceRequired && !connected;
        return Stack(
          children: [
            ElementButton(
              icon: a.icon,
              iconColor: Theme.of(context).colorScheme.primary,
              firstLine: a.name,
              secondLine: a.description,
              itemIndex: index,
              maxLineLines: 3,
              onPressed: (!a.deviceRequired || connected)
                  ? () => a.open(context)
                  : null,
              children: const [],
            ),
            if (disconnected)
              Positioned(
                top: 8,
                right: 8,
                child: StatusBadge(localizations.device_required),
              ),
          ],
        );
      },
    );
  }
}

/// A sub-page listing every tool inside one Ethical-Hacking category.
class HackingCategoryPage extends StatelessWidget {
  final String title;
  final List<HackingAttack> attacks;

  const HackingCategoryPage(
      {super.key, required this.title, required this.attacks});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: HackingToolGrid(attacks: attacks),
      ),
    );
  }
}
