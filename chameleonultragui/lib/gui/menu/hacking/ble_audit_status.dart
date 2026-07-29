import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter/material.dart';

class BleAuditStatus extends StatelessWidget {
  final BleCentralState state;
  final int mtu;

  const BleAuditStatus({
    super.key,
    required this.state,
    required this.mtu,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final connectionStates = [
      localizations.ble_status_idle,
      localizations.ble_status_connecting,
      localizations.ble_status_connected,
      localizations.ble_status_disconnected,
      localizations.ble_status_cancelling,
      localizations.ble_status_disconnecting,
    ];
    final discoveryStates = [
      localizations.ble_status_idle,
      localizations.ble_status_discovering,
      localizations.ble_status_done,
      localizations.ble_status_error,
    ];
    final fuzzStates = [
      localizations.ble_status_idle,
      localizations.ble_status_running,
      localizations.ble_status_stopped,
    ];
    final probeStates = [
      localizations.ble_status_idle,
      localizations.ble_status_probing,
      localizations.ble_status_done,
      localizations.ble_status_error,
    ];
    final operationStates = [
      localizations.ble_status_idle,
      localizations.ble_status_running,
      localizations.ble_status_done,
      localizations.ble_status_error,
    ];
    String statusAt(List<String> states, int index) =>
        index >= 0 && index < states.length ? states[index] : '$index';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localizations.ble_status_connection(
            statusAt(connectionStates, state.connState),
          )),
          Text(localizations.ble_status_discovery(
            state.charCount,
            statusAt(discoveryStates, state.discState),
          )),
          Text(localizations.ble_status_fuzz(
            state.fuzzSent,
            statusAt(fuzzStates, state.fuzzState),
          )),
          if (state.hasOperationState) ...[
            Text(localizations.ble_status_flood(
              state.floodSent,
              statusAt(fuzzStates, state.floodState),
            )),
            Text(localizations.ble_status_read(
              statusAt(operationStates, state.readState),
            )),
            Text(localizations.ble_status_write(
              statusAt(operationStates, state.writeState),
            )),
            Text(localizations.ble_status_notifications(
              state.notificationCount,
            )),
          ],
          Text(localizations.ble_status_target_up(
            state.targetAlive ? localizations.yes : localizations.no,
          )),
          if (state.connState == 2) Text(localizations.ble_status_att_mtu(mtu)),
          Text(state.probeState == 3
              ? localizations.ble_status_link_probe_error(
                  '0x${state.probeResult.toRadixString(16)}',
                  statusAt(probeStates, state.probeState),
                )
              : localizations.ble_status_link_probe(
                  statusAt(probeStates, state.probeState),
                )),
          if (state.lastReason != 0)
            Text(localizations.ble_status_disconnect_reason(
              '0x${state.lastReason.toRadixString(16).padLeft(2, '0')}',
            )),
        ],
      ),
    );
  }
}
