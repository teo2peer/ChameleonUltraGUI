import 'package:flutter/material.dart';

/// Small pill-shaped status badge (e.g. "Device required" / "WIP") shown
/// overlaid on hub tiles. Extracted from the inline copies that used to live
/// in ethical_hacking.dart and tools.dart so every hub renders them
/// identically.
class StatusBadge extends StatelessWidget {
  final String text;

  const StatusBadge(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.inversePrimary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
