import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/helpers/hf_capture_controller.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HfContinuousCapturePage extends StatefulWidget {
  const HfContinuousCapturePage({super.key});

  @override
  State<HfContinuousCapturePage> createState() =>
      _HfContinuousCapturePageState();
}

class _HfContinuousCapturePageState extends State<HfContinuousCapturePage> {
  HfCaptureMode _mode = HfCaptureMode.emulation;

  Future<void> _start(HfCaptureController controller) async {
    try {
      await controller.start(_mode);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _stop(HfCaptureController controller) async {
    try {
      await controller.stop();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _retryDrain(HfCaptureController controller) async {
    try {
      await controller.retryDrain();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _probe(HfCaptureController controller) async {
    try {
      await controller.probeReader();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _setRetention(
    ChameleonGUIState appState,
    HfCaptureController controller,
    int days,
  ) async {
    try {
      await appState.sharedPreferencesProvider.setHfCaptureRetentionDays(days);
      await controller.applyRetention();
      appState.changesMade();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<ChameleonGUIState>();
    final controller = appState.hfCaptureController;
    return Scaffold(
      appBar: AppBar(title: const Text('Continuous HF capture')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHero(context, controller),
            const SizedBox(height: 16),
            _buildModeSelector(controller),
            const SizedBox(height: 16),
            _buildMetrics(context, controller),
            if (controller.metadata?.overflowed == true) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const ListTile(
                  leading: Icon(Icons.warning_amber),
                  title: Text('Device buffer overflow detected'),
                  subtitle: Text(
                    'The dropped-record counter is authoritative. Persisted pages remain CRC-validated and ordered.',
                  ),
                ),
              ),
            ],
            if (controller.error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Capture warning'),
                  subtitle: SelectableText(controller.error!),
                  trailing: IconButton(
                    tooltip: 'Dismiss',
                    onPressed: controller.clearError,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildStorage(context, appState, controller),
            const SizedBox(height: 16),
            _buildRecentFrames(context, controller),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, HfCaptureController controller) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = controller.isRunning;
    final draining = !active && controller.needsDrain;
    final finalizing = !active && !draining && controller.needsFinalize;
    final statusLabel = !controller.isConnected
        ? 'DISCONNECTED'
        : active
        ? 'CAPTURING'
        : draining
        ? 'DRAINING'
        : finalizing
        ? 'FINALIZING'
        : controller.isSupported == false
        ? 'UNSUPPORTED'
        : !controller.canStart
        ? 'BLOCKED'
        : 'READY';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.tertiaryContainer.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final status = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      active
                          ? Icons.fiber_manual_record
                          : draining
                          ? Icons.downloading
                          : finalizing
                          ? Icons.save
                          : Icons.radar,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Loss-aware ISO14443-A evidence stream',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Frames are written to app storage before acknowledgement. USB and BLE use the same sequence and CRC checks.',
                ),
              ],
            );
            final actions = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed:
                      controller.isBusy ||
                          controller.isSupported == false ||
                          !controller.isConnected ||
                          !controller.canStart
                      ? null
                      : () => _start(controller),
                  icon: controller.isBusy && !active
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Start capture'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      controller.isBusy || !active || !controller.isConnected
                      ? null
                      : () => _stop(controller),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop and drain'),
                ),
                if (!active &&
                    (controller.needsDrain || controller.needsFinalize))
                  OutlinedButton.icon(
                    onPressed:
                        controller.isBusy ||
                            (controller.needsDrain && !controller.isConnected)
                        ? null
                        : () => _retryDrain(controller),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry drain'),
                  ),
                if (active && controller.metadata?.mode == HfCaptureMode.reader)
                  OutlinedButton.icon(
                    onPressed: controller.isBusy || !controller.isConnected
                        ? null
                        : () => _probe(controller),
                    icon: const Icon(Icons.contactless),
                    label: const Text('Probe card'),
                  ),
              ],
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [status, const SizedBox(height: 18), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 24),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildModeSelector(HfCaptureController controller) {
    final selectedMode = controller.canStart
        ? _mode
        : controller.metadata?.mode ?? _mode;
    final descriptions = switch (selectedMode) {
      HfCaptureMode.emulation =>
        'Capture reader commands and emulated-card responses. Best for complete authentication transcripts.',
      HfCaptureMode.passive =>
        'Listen without transmitting. On one Ultra this guarantees reader-to-card traffic only.',
      HfCaptureMode.reader =>
        'Trace Ultra reader exchanges with an external card. Use Probe card here or run another reader operation while capture remains active.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Acquisition mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<HfCaptureMode>(
                segments: const [
                  ButtonSegment(
                    value: HfCaptureMode.emulation,
                    icon: Icon(Icons.nfc),
                    label: Text('Emulation'),
                  ),
                  ButtonSegment(
                    value: HfCaptureMode.passive,
                    icon: Icon(Icons.hearing),
                    label: Text('Passive'),
                  ),
                  ButtonSegment(
                    value: HfCaptureMode.reader,
                    icon: Icon(Icons.sensors),
                    label: Text('Reader'),
                  ),
                ],
                selected: {selectedMode},
                onSelectionChanged: !controller.canStart || controller.isBusy
                    ? null
                    : (selection) => setState(() => _mode = selection.single),
              ),
            ),
            const SizedBox(height: 12),
            Text(descriptions),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(BuildContext context, HfCaptureController controller) {
    final metadata = controller.metadata;
    final usage = metadata == null || metadata.capacityBytes == 0
        ? 0.0
        : metadata.usedBytes / metadata.capacityBytes;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metric(
          context,
          'Observed',
          '${metadata?.observedRecords ?? 0}',
          Icons.visibility,
        ),
        _metric(
          context,
          'Buffered',
          '${metadata?.storedRecords ?? 0}',
          Icons.memory,
        ),
        _metric(
          context,
          'Dropped',
          '${metadata?.droppedRecords ?? 0}',
          Icons.report,
        ),
        _metric(
          context,
          'Persisted',
          _formatBytes(controller.persistedBytes),
          Icons.save,
        ),
        if (controller.lastReaderCard != null)
          _metric(
            context,
            'Last card',
            bytesToHex(controller.lastReaderCard!.uid).toUpperCase(),
            Icons.contactless,
          ),
        SizedBox(
          width: 230,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Device buffer'),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: usage.clamp(0, 1)),
                  const SizedBox(height: 8),
                  Text(
                    '${metadata?.usedBytes ?? 0} / ${metadata?.capacityBytes ?? 0} bytes',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) => SizedBox(
    width: 170,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildStorage(
    BuildContext context,
    ChameleonGUIState appState,
    HfCaptureController controller,
  ) {
    final preferences = appState.sharedPreferencesProvider;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open),
                const SizedBox(width: 8),
                Text(
                  'Durable session storage',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              controller.captureDirectory ??
                  'A directory is created when capture starts.',
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Retention applies to completed local capture directories. Active capture data and recovered keys are never exported with settings.',
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: preferences.getHfCaptureRetentionDays(),
                  items: const [7, 14, 30, 90, 180, 365]
                      .map(
                        (days) => DropdownMenuItem(
                          value: days,
                          child: Text('$days days'),
                        ),
                      )
                      .toList(),
                  onChanged: (days) async {
                    if (days == null) return;
                    await _setRetention(appState, controller, days);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentFrames(
    BuildContext context,
    HfCaptureController controller,
  ) {
    final records = controller.recentRecords.reversed.take(100).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent evidence',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Latest 100 records are shown; every validated page remains on disk.',
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No frames captured yet')),
              )
            else
              for (final record in records) ...[
                _recordTile(context, record),
                const Divider(height: 1),
              ],
          ],
        ),
      ),
    );
  }

  Widget _recordTile(BuildContext context, HfCaptureRecord record) {
    final direction = switch (record.direction) {
      HfCaptureDirection.readerToCard => 'reader -> card',
      HfCaptureDirection.cardToReader => 'card -> reader',
      HfCaptureDirection.event => 'RF field event',
    };
    final elapsedMs = (record.timestampTicks * 1000) ~/ 32768;
    final payload = record.type == HfCaptureRecordType.field
        ? (record.data.isNotEmpty && record.data.first == 1
              ? 'field on'
              : 'field off')
        : bytesToHexSpace(record.data).toUpperCase();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        child: Text(
          '#${record.sequence}',
          style: const TextStyle(fontSize: 10),
        ),
      ),
      title: Text(direction),
      subtitle: SelectableText(
        payload,
        maxLines: 3,
        style: const TextStyle(fontFamily: 'RobotoMono'),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 110),
        child: Text(
          '${_formatElapsed(elapsedMs)}${record.hasRfError ? '\nRF error' : ''}',
          textAlign: TextAlign.end,
          style: TextStyle(
            color: record.hasRfError
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  String _formatElapsed(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final remainder = milliseconds % 1000;
    final minutes = seconds ~/ 60;
    final secondPart = seconds % 60;
    if (minutes == 0) {
      return '$secondPart.${remainder.toString().padLeft(3, '0')} s';
    }
    return '$minutes:${secondPart.toString().padLeft(2, '0')}.${remainder.toString().padLeft(3, '0')}';
  }
}
