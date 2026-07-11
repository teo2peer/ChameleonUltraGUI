import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/ble/ble_presentation.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter/material.dart';

class BleCharacteristicTile extends StatelessWidget {
  final BleCharacteristic characteristic;
  final String? readValue;
  final bool notifying;
  final bool readSupported;
  final bool writeSupported;
  final bool fuzzSupported;
  final bool notifySupported;
  final VoidCallback onRead;
  final VoidCallback onWrite;
  final VoidCallback onSelectFuzz;
  final VoidCallback onToggleNotify;

  const BleCharacteristicTile({
    super.key,
    required this.characteristic,
    required this.readValue,
    required this.notifying,
    this.readSupported = true,
    this.writeSupported = true,
    this.fuzzSupported = true,
    this.notifySupported = true,
    required this.onRead,
    required this.onWrite,
    required this.onSelectFuzz,
    required this.onToggleNotify,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final uuidName = bleUuidName(characteristic.uuid);
    final handle =
        '0x${characteristic.handle.toRadixString(16).padLeft(4, '0')}';
    final uuid = '0x${characteristic.uuid.toRadixString(16).padLeft(4, '0')}';
    final properties = <String>[
      if (characteristic.props & 0x02 != 0) localizations.read,
      if (characteristic.props & 0x04 != 0)
        localizations.ble_property_write_no_response,
      if (characteristic.props & 0x08 != 0) localizations.write,
      if (characteristic.props & 0x10 != 0) localizations.ble_notify,
      if (characteristic.props & 0x20 != 0) localizations.ble_property_indicate,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          isThreeLine: readValue != null,
          title: Text(
            uuidName.isEmpty
                ? localizations.ble_characteristic_row(handle, uuid)
                : localizations.ble_characteristic_named_row(
                    handle,
                    uuid,
                    uuidName,
                  ),
            style: const TextStyle(fontFamily: 'RobotoMono'),
          ),
          subtitle: Text(
            (properties.isEmpty ? '-' : properties.join(', ')) +
                (readValue == null ? '' : '\n= $readValue'),
            style: const TextStyle(fontFamily: 'RobotoMono'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (readSupported && characteristic.props & 0x02 != 0)
                TextButton(
                  onPressed: onRead,
                  child: Text(localizations.read),
                ),
              if (writeSupported &&
                  bleCanWriteWithResponse(characteristic.props))
                TextButton(
                  onPressed: onWrite,
                  child: Text(localizations.write),
                ),
              if (fuzzSupported &&
                  bleCanFuzzWithoutResponse(characteristic.props))
                TextButton(
                  onPressed: onSelectFuzz,
                  child: Text(localizations.ble_select_fuzz),
                ),
              if (notifySupported && characteristic.props & 0x30 != 0)
                TextButton(
                  onPressed: onToggleNotify,
                  child: Text(notifying
                      ? localizations.ble_stop
                      : localizations.ble_notify),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
