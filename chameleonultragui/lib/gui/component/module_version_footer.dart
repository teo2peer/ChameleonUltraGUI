import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:flutter/material.dart';

class ModuleVersionFooter extends StatelessWidget {
  final ModuleId moduleId;

  const ModuleVersionFooter({required this.moduleId, super.key});

  @override
  Widget build(BuildContext context) {
    final module = moduleReleaseFor(moduleId);
    final details = 'Version ${module.version} / Updated ${module.updatedAt}';
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Semantics(
          container: true,
          excludeSemantics: true,
          label: '${module.name}. $details',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 4,
              children: [
                SelectableText(module.name, style: textTheme.labelLarge),
                SelectableText(
                  details,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
