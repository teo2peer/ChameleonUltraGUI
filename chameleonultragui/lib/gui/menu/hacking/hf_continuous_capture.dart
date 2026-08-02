import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/helpers/hf_capture_controller.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
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
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.hf_capture_title)),
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
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(localizations.hf_capture_overflow_title),
                  subtitle: Text(localizations.hf_capture_overflow_description),
                ),
              ),
            ],
            if (controller.error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(localizations.hf_capture_warning),
                  subtitle: SelectableText(controller.error!),
                  trailing: IconButton(
                    tooltip: localizations.hf_capture_dismiss,
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
    final localizations = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final active = controller.isRunning;
    final draining = !active && controller.needsDrain;
    final finalizing = !active && !draining && controller.needsFinalize;
    final statusLabel = !controller.isConnected
        ? localizations.hf_capture_status_disconnected
        : active
        ? localizations.hf_capture_status_capturing
        : draining
        ? localizations.hf_capture_status_draining
        : finalizing
        ? localizations.hf_capture_status_finalizing
        : controller.isSupported == false
        ? localizations.hf_capture_status_unsupported
        : !controller.canStart
        ? localizations.hf_capture_status_blocked
        : localizations.hf_capture_status_ready;
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
                  localizations.hf_capture_stream_title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(localizations.hf_capture_stream_description),
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
                  label: Text(localizations.hf_capture_start),
                ),
                OutlinedButton.icon(
                  onPressed:
                      controller.isBusy || !active || !controller.isConnected
                      ? null
                      : () => _stop(controller),
                  icon: const Icon(Icons.stop),
                  label: Text(localizations.hf_capture_stop),
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
                    label: Text(localizations.hf_capture_retry),
                  ),
                if (active && controller.metadata?.mode == HfCaptureMode.reader)
                  OutlinedButton.icon(
                    onPressed: controller.isBusy || !controller.isConnected
                        ? null
                        : () => _probe(controller),
                    icon: const Icon(Icons.contactless),
                    label: Text(localizations.hf_capture_probe),
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
    final localizations = AppLocalizations.of(context)!;
    final selectedMode = controller.canStart
        ? _mode
        : controller.metadata?.mode ?? _mode;
    final descriptions = switch (selectedMode) {
      HfCaptureMode.emulation =>
        localizations.hf_capture_mode_emulation_description,
      HfCaptureMode.passive =>
        localizations.hf_capture_mode_passive_description,
      HfCaptureMode.reader => localizations.hf_capture_mode_reader_description,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.hf_capture_mode_title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<HfCaptureMode>(
                segments: [
                  ButtonSegment(
                    value: HfCaptureMode.emulation,
                    icon: const Icon(Icons.nfc),
                    label: Text(localizations.hf_capture_mode_emulation),
                  ),
                  ButtonSegment(
                    value: HfCaptureMode.passive,
                    icon: const Icon(Icons.hearing),
                    label: Text(localizations.hf_capture_mode_passive),
                  ),
                  ButtonSegment(
                    value: HfCaptureMode.reader,
                    icon: const Icon(Icons.sensors),
                    label: Text(localizations.hf_capture_mode_reader),
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
    final localizations = AppLocalizations.of(context)!;
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
          localizations.hf_capture_observed,
          '${metadata?.observedRecords ?? 0}',
          Icons.visibility,
        ),
        _metric(
          context,
          localizations.hf_capture_buffered,
          '${metadata?.storedRecords ?? 0}',
          Icons.memory,
        ),
        _metric(
          context,
          localizations.hf_capture_dropped,
          '${metadata?.droppedRecords ?? 0}',
          Icons.report,
        ),
        _metric(
          context,
          localizations.hf_capture_persisted,
          _formatBytes(controller.persistedBytes),
          Icons.save,
        ),
        if (controller.lastReaderCard != null)
          _metric(
            context,
            localizations.hf_capture_last_card,
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
                  Text(localizations.hf_capture_device_buffer),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: usage.clamp(0, 1)),
                  const SizedBox(height: 8),
                  Text(
                    localizations.hf_capture_buffer_bytes(
                      metadata?.usedBytes ?? 0,
                      metadata?.capacityBytes ?? 0,
                    ),
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
    final localizations = AppLocalizations.of(context)!;
    final retention = preferences.getHfCaptureRetentionDays();
    final retentionOptions = {7, 14, 30, 90, 180, 365, retention}.toList()
      ..sort();
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
                  localizations.hf_capture_storage_title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              controller.captureDirectory ??
                  localizations.hf_capture_storage_pending,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(localizations.hf_capture_retention_description),
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: retention,
                  items: retentionOptions
                      .map(
                        (days) => DropdownMenuItem(
                          value: days,
                          child: Text(
                            localizations.hf_capture_retention_days(days),
                          ),
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
    final localizations = AppLocalizations.of(context)!;
    final records = controller.recentRecords.reversed.take(100).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.hf_capture_recent_title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(localizations.hf_capture_recent_description),
            const SizedBox(height: 12),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(localizations.hf_capture_no_frames)),
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
    final localizations = AppLocalizations.of(context)!;
    final direction = switch (record.direction) {
      HfCaptureDirection.readerToCard =>
        localizations.hf_capture_reader_to_card,
      HfCaptureDirection.cardToReader =>
        localizations.hf_capture_card_to_reader,
      HfCaptureDirection.event => localizations.hf_capture_field_event,
    };
    final elapsedMs = (record.timestampTicks * 1000) ~/ 32768;
    final payload = record.type == HfCaptureRecordType.field
        ? (record.data.isNotEmpty && record.data.first == 1
              ? localizations.hf_capture_field_on
              : localizations.hf_capture_field_off)
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
          '${_formatElapsed(elapsedMs)}${record.hasRfError ? '\n${localizations.hf_capture_rf_error}' : ''}',
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
