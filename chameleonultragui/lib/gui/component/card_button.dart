import 'package:flutter/material.dart';
import 'package:chameleonultragui/main.dart';

ButtonStyle customCardButtonStyle(ChameleonGUIState appState) {
  final base = appState.sharedPreferencesProvider.getThemeComplementaryColor();
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith<Color>(
      (Set<WidgetState> states) {
        // Slight tint on hover/press so the tile visibly reacts.
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.hovered)) {
          return Color.alphaBlend(const Color(0x24808080), base);
        }
        return base;
      },
    ),
    // Raised, lifts on hover, presses in on tap — reads as a real button.
    elevation: WidgetStateProperty.resolveWith<double>(
      (Set<WidgetState> states) {
        if (states.contains(WidgetState.pressed)) return 0.0;
        if (states.contains(WidgetState.hovered)) return 4.0;
        return 1.5;
      },
    ),
    side: WidgetStateProperty.all<BorderSide>(
      const BorderSide(color: Color(0x33808080)),
    ),
    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
      ),
    ),
  );
}
