import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:flutter/material.dart';

class MifareClassicActivityProgressIndicator extends StatelessWidget {
  const MifareClassicActivityProgressIndicator({
    super.key,
    required this.activity,
  });

  final MifareClassicRecoveryActivity? activity;

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds.remainder(60).toString().padLeft(2, '0')}s';
  }

  String _formatRate(double rate) =>
      rate >= 10 ? rate.toStringAsFixed(0) : rate.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final value = activity;
    if (value == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final rate = value.itemsPerSecond(now);
    final eta = value.estimatedRemaining(now);
    final percent = (value.progress * 100).round();
    return Semantics(
      label:
          '${value.label}: ${value.completed} of ${value.total}, $percent percent',
      child: Column(
        key: const Key('mifare-classic-activity-progress'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  value.label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Text('${value.completed}/${value.total}'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: value.progress,
            minHeight: 6,
            color: Theme.of(context).colorScheme.secondary,
          ),
          if (eta != null) ...[
            const SizedBox(height: 4),
            Text(
              '${value.unit == 'keys' ? 'Key scan ETA' : 'ETA'} ${_formatDuration(eta)}'
              '${rate == null ? '' : ' | ${_formatRate(rate)} ${value.unit}/s'}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}
