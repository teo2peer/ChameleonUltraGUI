import 'package:chameleonultragui/helpers/emulation_change.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EmulationChangeHistoryMenu extends StatefulWidget {
  const EmulationChangeHistoryMenu({super.key});

  @override
  State<EmulationChangeHistoryMenu> createState() =>
      _EmulationChangeHistoryMenuState();
}

class _EmulationChangeHistoryMenuState
    extends State<EmulationChangeHistoryMenu> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final preferences = context.read<SharedPreferencesProvider>();
    final history = preferences.getEmulationChangeHistory();
    final monitoring = preferences.getEmulationChangeMonitoring();
    final connected =
        appState.connector?.connected == true &&
        appState.connector?.isDFU == false;

    return AlertDialog(
      title: const Text('Emulated tag change history'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: monitoring,
              onChanged: (value) async {
                await appState.setEmulationChangeMonitoring(value);
                setState(() {});
              },
              title: const Text('Monitor active MIFARE Classic slot'),
              subtitle: Text(
                connected
                    ? 'Checks every 3 seconds, archives block differences on this phone, and saves the updated slot. Use Normal write mode for changes to survive a device restart.'
                    : 'Monitoring starts automatically on the next device connection.',
              ),
            ),
            const Divider(),
            Expanded(
              child: history.isEmpty
                  ? const Center(
                      child: Text(
                        'No changes recorded. Enable monitoring before emulating the tag.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) =>
                          _HistoryEntry(entry: history[index]),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: history.isEmpty
              ? null
              : () {
                  preferences.clearEmulationChangeHistory();
                  setState(() {});
                },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear history'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  final EmulationChangeEntry entry;

  const _HistoryEntry({required this.entry});

  String _timestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.history),
      title: Text(
        'Slot ${entry.slot + 1} | ${entry.changes.length} changed block${entry.changes.length == 1 ? '' : 's'}',
      ),
      subtitle: Text('${_timestamp(entry.timestamp)} | UID ${entry.uid}'),
      children: [
        for (final change in entry.changes)
          ListTile(
            dense: true,
            title: Text('Block ${change.block}'),
            subtitle: SelectableText(
              'Before ${bytesToHex(change.before).toUpperCase()}\n'
              'After  ${bytesToHex(change.after).toUpperCase()}',
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
      ],
    );
  }
}
