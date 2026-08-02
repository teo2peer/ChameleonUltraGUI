import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

String formatMifareClassicNonceHistoryBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

class MifareClassicNonceHistoryPage extends StatefulWidget {
  const MifareClassicNonceHistoryPage({super.key});

  @override
  State<MifareClassicNonceHistoryPage> createState() =>
      _MifareClassicNonceHistoryPageState();
}

class _MifareClassicNonceHistoryPageState
    extends State<MifareClassicNonceHistoryPage> {
  Future<void> _removeCard(MifareClassicNonceHistorySummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recovery history?'),
        content: Text(
          'Delete ${summary.nonceSampleCount} stored nonce samples and '
          '${summary.failedKeyCount} failed keys for UID '
          '${summary.cardUid} (${formatMifareClassicNonceHistoryBytes(summary.byteSize)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context
          .read<ChameleonGUIState>()
          .sharedPreferencesProvider
          .clearMifareClassicNonceHistoryForCard(summary.cardUid);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider;
    final entries = preferences.getMifareClassicNonceHistorySummaries();
    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.byteSize,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('MIFARE Classic recovery history')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Stored locally as SHA-256 fingerprints. No nonce values or keys are kept in plaintext.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            '${entries.length} cards | ${formatMifareClassicNonceHistoryBytes(totalBytes)}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No MIFARE Classic recovery history is stored.'),
              ),
            ),
          for (final entry in entries)
            Card(
              child: ListTile(
                leading: const Icon(Icons.contactless),
                title: Text('UID ${entry.cardUid}'),
                subtitle: Text(
                  '${entry.nonceSampleCount} nonce samples | ${entry.failedKeyCount} failed keys | ${formatMifareClassicNonceHistoryBytes(entry.byteSize)}',
                ),
                trailing: IconButton(
                  tooltip: 'Delete history for this card',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeCard(entry),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
