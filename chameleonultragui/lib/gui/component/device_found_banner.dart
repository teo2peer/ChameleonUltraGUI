import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Compact app-wide chip shown while disconnected when a device is discovered
/// on a screen other than the Connect page. Offers a one-tap Connect that
/// connects in place (without leaving the current screen). Anchored at the
/// bottom of the content, inside a SafeArea, so it never overlaps the notch,
/// the window controls, or the page AppBar.
class DeviceFoundBanner extends StatelessWidget {
  final Chameleon device;
  final VoidCallback onConnect;
  final VoidCallback onDismiss;

  const DeviceFoundBanner({
    super.key,
    required this.device,
    required this.onConnect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(
                  device.type == ConnectionType.ble
                      ? Icons.bluetooth
                      : Icons.usb,
                  size: 18,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    localizations.device_available(
                      chameleonDeviceName(device.device),
                      device.port?.toString() ?? '',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onConnect,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(localizations.connect),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: localizations.close,
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
