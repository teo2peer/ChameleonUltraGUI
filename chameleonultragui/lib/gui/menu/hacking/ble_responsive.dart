import 'package:flutter/material.dart';

class BleResponsiveFieldGroup extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  const BleResponsiveFieldGroup({
    super.key,
    required this.children,
    this.breakpoint = 560,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) SizedBox(height: spacing),
                children[index],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) SizedBox(width: spacing),
              Expanded(child: children[index]),
            ],
          ],
        );
      },
    );
  }
}
