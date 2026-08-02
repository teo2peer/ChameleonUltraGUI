import 'dart:ui';

import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UndercoverShell extends StatelessWidget {
  const UndercoverShell({
    super.key,
    required this.child,
    required this.activeModule,
    required this.overlayActive,
    required this.rootLabel,
    required this.connected,
    required this.onBack,
    required this.onLauncher,
  });

  final Widget child;
  final ValueListenable<ModuleId> activeModule;
  final ValueListenable<bool> overlayActive;
  final String rootLabel;
  final bool connected;
  final VoidCallback onBack;
  final VoidCallback onLauncher;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _undercoverTheme(Theme.of(context)),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: const Color(0xFF171A35),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Stack(
          key: const Key('undercover-shell'),
          fit: StackFit.expand,
          children: [
            const _ShellWallpaper(),
            SafeArea(
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: overlayActive,
                    builder: (context, blocked, _) {
                      return IgnorePointer(
                        ignoring: blocked,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: blocked ? 0.18 : 1,
                          child: ValueListenableBuilder<ModuleId>(
                            valueListenable: activeModule,
                            builder: (context, moduleId, _) {
                              return _IOSNavigationBar(
                                rootLabel: rootLabel,
                                moduleLabel: moduleReleaseFor(moduleId).name,
                                connected: connected,
                                onBack: onBack,
                                onLauncher: onLauncher,
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xC91C1C1E),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: Colors.white24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55000000),
                                  blurRadius: 28,
                                  offset: Offset(0, 14),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(27),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IOSNavigationBar extends StatelessWidget {
  const _IOSNavigationBar({
    required this.rootLabel,
    required this.moduleLabel,
    required this.connected,
    required this.onBack,
    required this.onLauncher,
  });

  final String rootLabel;
  final String moduleLabel;
  final bool connected;
  final VoidCallback onBack;
  final VoidCallback onLauncher;

  @override
  Widget build(BuildContext context) {
    final title = moduleLabel == 'Undercover' ? rootLabel : moduleLabel;
    final showContext = title != rootLabel;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = 64 + (textScale - 1).clamp(0.0, 2.0) * 20;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: MaterialLocalizations.of(context).backButtonTooltip,
                    child: IconButton(
                      key: const Key('undercover-shell-back'),
                      onPressed: onBack,
                      style: IconButton.styleFrom(
                        foregroundColor: const Color(0xFF64D2FF),
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.chevron_left_rounded, size: 29),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (showContext)
                          Text(
                            rootLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: connected ? 'Device connected' : 'Local mode',
                    child: Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: connected
                            ? const Color(0xFF30D158)
                            : const Color(0xFFFF9F0A),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                (connected
                                        ? const Color(0xFF30D158)
                                        : const Color(0xFFFF9F0A))
                                    .withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Undercover home screen',
                    child: IconButton(
                      key: const Key('undercover-shell-launcher'),
                      onPressed: onLauncher,
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF0A84FF),
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.apps_rounded, size: 21),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData _undercoverTheme(ThemeData base) {
  const colors = ColorScheme.dark(
    primary: Color(0xFF0A84FF),
    onPrimary: Colors.white,
    secondary: Color(0xFF30D158),
    onSecondary: Color(0xFF001D0A),
    surface: Color(0xFF1C1C1E),
    onSurface: Colors.white,
    error: Color(0xFFFF453A),
    onError: Colors.white,
  );
  final textTheme = base.textTheme.apply(
    bodyColor: colors.onSurface,
    displayColor: colors.onSurface,
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    platform: TargetPlatform.iOS,
    brightness: Brightness.dark,
    colorScheme: colors,
    scaffoldBackgroundColor: const Color(0xFF1C1C1E),
    canvasColor: const Color(0xFF1C1C1E),
    cardColor: const Color(0xFF2C2C2E),
    dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF2C2C2E)),
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Color(0xF21C1C1E),
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2C2C2E),
      labelStyle: const TextStyle(color: Color(0xFFEBEBF5)),
      hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
      prefixIconColor: const Color(0xFF8E8E93),
      suffixIconColor: const Color(0xFF8E8E93),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: Color(0xFF0A84FF), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        backgroundColor: const Color(0xFF0A84FF),
        foregroundColor: Colors.white,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        foregroundColor: const Color(0xFF64D2FF),
        side: const BorderSide(color: Color(0xFF48484A)),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: const Color(0xFF64D2FF),
        shape: buttonShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        focusColor: const Color(0x5532ADE6),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(buttonShape),
        side: const WidgetStatePropertyAll(
          BorderSide(color: Color(0xFF48484A)),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF30D158)
            : const Color(0xFF48484A),
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Color(0xFF0A84FF),
      thumbColor: Colors.white,
      inactiveTrackColor: Color(0xFF48484A),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF22C2C2E),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF2C2C2E),
      modalBackgroundColor: Color(0xFF2C2C2E),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),
    dividerColor: const Color(0xFF3A3A3C),
    focusColor: const Color(0x5532ADE6),
    hoverColor: const Color(0x2232ADE6),
  );
}

class _ShellWallpaper extends StatelessWidget {
  const _ShellWallpaper();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101D3D), Color(0xFF4C3D79), Color(0xFFB45F7D)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -150,
            right: -110,
            child: _ShellGlow(size: 340, color: Color(0x6675D7FF)),
          ),
          Positioned(
            bottom: -130,
            left: -110,
            child: _ShellGlow(size: 360, color: Color(0x66FF8A9E)),
          ),
        ],
      ),
    );
  }
}

class _ShellGlow extends StatelessWidget {
  const _ShellGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}
