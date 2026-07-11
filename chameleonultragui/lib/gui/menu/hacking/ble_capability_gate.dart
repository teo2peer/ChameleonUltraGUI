import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BleCapabilityGate extends StatelessWidget {
  final Widget child;
  final String feature;
  final List<ChameleonCommand> requiredCommands;

  const BleCapabilityGate({
    super.key,
    required this.child,
    required this.feature,
    required this.requiredCommands,
  });

  @override
  Widget build(BuildContext context) {
    final communicator = context.watch<ChameleonGUIState>().communicator;
    final unsupported = communicator != null &&
        requiredCommands.any(
            (command) => communicator.supportsCommandSync(command) == false);
    if (!unsupported) return child;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context)!
              .ble_firmware_feature_unsupported(feature),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
