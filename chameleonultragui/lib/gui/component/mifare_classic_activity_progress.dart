import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:flutter/material.dart';

class MifareClassicActivityProgressIndicator extends StatelessWidget {
  const MifareClassicActivityProgressIndicator({
    super.key,
    required this.activity,
  });

  final MifareClassicRecoveryActivity? activity;

  @override
  Widget build(BuildContext context) {
    final value = activity;
    if (value == null) return const SizedBox.shrink();
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
        ],
      ),
    );
  }
}
