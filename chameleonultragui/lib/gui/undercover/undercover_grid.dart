import 'dart:math' as math;

import 'package:flutter/material.dart';

class UndercoverGridPlacement {
  const UndercoverGridPlacement({
    required this.row,
    required this.column,
    required this.rowSpan,
    required this.columnSpan,
    required this.child,
  }) : assert(row >= 0 && row < UndercoverSpringGrid.rows),
       assert(column >= 0 && column < UndercoverSpringGrid.columns),
       assert(rowSpan == 1 || rowSpan == 2),
       assert(columnSpan == 1 || columnSpan == 2 || columnSpan == 4),
       assert(row + rowSpan <= UndercoverSpringGrid.rows),
       assert(column + columnSpan <= UndercoverSpringGrid.columns);

  final int row;
  final int column;
  final int rowSpan;
  final int columnSpan;
  final Widget child;
}

class UndercoverSpringGrid extends StatelessWidget {
  const UndercoverSpringGrid({
    super.key,
    required this.placements,
    this.horizontalPadding = 12,
    this.verticalPadding = 4,
  });

  static const columns = 4;
  static const rows = 6;
  static const _gap = 8.0;

  final List<UndercoverGridPlacement> placements;
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    assert(_placementsDoNotOverlap());
    return LayoutBuilder(
      builder: (context, constraints) {
        final usableWidth = math.max(
          0.0,
          constraints.maxWidth - horizontalPadding * 2,
        );
        final usableHeight = math.max(
          0.0,
          constraints.maxHeight - verticalPadding * 2,
        );
        final cellExtent = math.min(
          (usableWidth - _gap * (columns - 1)) / columns,
          (usableHeight - _gap * (rows - 1)) / rows,
        );
        if (!cellExtent.isFinite || cellExtent <= 0) {
          return const SizedBox.shrink();
        }

        final gridWidth = cellExtent * columns + _gap * (columns - 1);
        final gridHeight = cellExtent * rows + _gap * (rows - 1);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: gridWidth,
            height: gridHeight,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Stack(
                children: [
                  for (final placement in placements)
                    Positioned(
                      left: placement.column * (cellExtent + _gap),
                      top: placement.row * (cellExtent + _gap),
                      width:
                          placement.columnSpan * cellExtent +
                          (placement.columnSpan - 1) * _gap,
                      height:
                          placement.rowSpan * cellExtent +
                          (placement.rowSpan - 1) * _gap,
                      child: placement.child,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _placementsDoNotOverlap() {
    final occupied = <(int, int)>{};
    for (final placement in placements) {
      for (
        var row = placement.row;
        row < placement.row + placement.rowSpan;
        row++
      ) {
        for (
          var column = placement.column;
          column < placement.column + placement.columnSpan;
          column++
        ) {
          if (!occupied.add((row, column))) return false;
        }
      }
    }
    return true;
  }
}

class UndercoverGridTile extends StatelessWidget {
  const UndercoverGridTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.details,
    this.value,
    this.selected = false,
    this.enabled = true,
    this.busy = false,
    this.onPressed,
    this.onLongPress,
  });

  final String label;
  final String? details;
  final String? value;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final bool busy;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && onPressed != null;
    return Semantics(
      button: onPressed != null,
      enabled: enabled,
      selected: selected,
      label: [label, ?value, ?details].join(', '),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shorterSide = math.min(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final longerSide = math.max(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final isAppIcon = longerSide / shorterSide < 1.24;
          if (isAppIcon) {
            return _IOSAppIconTile(
              label: label,
              icon: icon,
              color: color,
              selected: selected,
              enabled: enabled,
              busy: busy,
              onPressed: interactive ? onPressed : null,
              onLongPress: enabled ? onLongPress : null,
            );
          }
          return _IOSWidgetTile(
            label: label,
            details: details,
            value: value,
            icon: icon,
            color: color,
            selected: selected,
            enabled: enabled,
            busy: busy,
            onPressed: interactive ? onPressed : null,
            onLongPress: enabled ? onLongPress : null,
          );
        },
      ),
    );
  }
}

class UndercoverSquircleIcon extends StatelessWidget {
  const UndercoverSquircleIcon({
    super.key,
    required this.icon,
    required this.color,
    required this.size,
    this.selected = false,
    this.enabled = true,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool selected;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = enabled ? color : const Color(0xFF68686F);
    final colors = [
      Color.lerp(accent, Colors.white, dark ? 0.18 : 0.34)!,
      accent,
      Color.lerp(accent, Colors.black, dark ? 0.3 : 0.12)!,
    ];
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(size * 0.48),
      side: BorderSide(
        color: selected
            ? Colors.white.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: dark ? 0.18 : 0.42),
        width: selected ? 2.2 : 0.8,
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
            stops: const [0, 0.52, 1],
          ),
          shape: shape,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.2 : 0.12),
              blurRadius: size * 0.18,
              offset: Offset(0, size * 0.07),
            ),
          ],
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.55, -0.7),
                    radius: 1.1,
                    colors: [
                      Colors.white.withValues(alpha: dark ? 0.13 : 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 1,
                left: size * 0.2,
                right: size * 0.2,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.58),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: busy
                    ? SizedBox.square(
                        dimension: size * 0.36,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Icon(
                        enabled ? icon : Icons.lock_rounded,
                        color: enabled ? Colors.white : Colors.white60,
                        size: size * 0.42,
                        shadows: const [
                          Shadow(
                            color: Color(0x33000000),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
              ),
              if (selected)
                Positioned(
                  top: size * 0.08,
                  right: size * 0.08,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: size * 0.24,
                    shadows: const [
                      Shadow(color: Colors.black38, blurRadius: 4),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IOSAppIconTile extends StatelessWidget {
  const _IOSAppIconTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.busy,
    required this.onPressed,
    required this.onLongPress,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final bool busy;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelHeight = 19.0;
        final iconSize = math.max(
          44.0,
          math.min(constraints.maxWidth, constraints.maxHeight - labelHeight),
        );
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onPressed,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                UndercoverSquircleIcon(
                  icon: icon,
                  color: color,
                  size: iconSize,
                  selected: selected,
                  enabled: enabled,
                  busy: busy,
                ),
                const SizedBox(height: 3),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white60,
                      fontSize: constraints.maxHeight < 72 ? 8.5 : 10.5,
                      height: 1.02,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 5),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IOSWidgetTile extends StatelessWidget {
  const _IOSWidgetTile({
    required this.label,
    required this.details,
    required this.value,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.busy,
    required this.onPressed,
    required this.onLongPress,
  });

  final String label;
  final String? details;
  final String? value;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final bool busy;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = enabled ? color : const Color(0xFF45454C);
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(34),
      side: BorderSide(
        color: selected
            ? Colors.white.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: dark ? 0.14 : 0.38),
        width: selected ? 2 : 0.8,
      ),
    );
    return Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(accent, Colors.white, dark ? 0.14 : 0.3)!,
              accent.withValues(alpha: dark ? 0.9 : 0.82),
              Color.lerp(accent, Colors.black, dark ? 0.3 : 0.12)!,
            ],
          ),
          shape: shape,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.18 : 0.1),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          customBorder: shape,
          onTap: onPressed,
          onLongPress: onLongPress,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = constraints.maxWidth > constraints.maxHeight;
              final compact = constraints.maxHeight < 92;
              final glyphSize = math.min(
                horizontal ? constraints.maxHeight * 0.54 : 44.0,
                48.0,
              );
              final glyph = UndercoverSquircleIcon(
                icon: icon,
                color: color,
                size: glyphSize,
                selected: selected,
                enabled: enabled,
                busy: busy,
              );
              final text = _IOSWidgetText(
                label: label,
                value: value,
                details: details,
                enabled: enabled,
                compact: compact,
                textAlign: horizontal ? TextAlign.start : TextAlign.center,
              );
              return Stack(
                children: [
                  Positioned(
                    top: 1,
                    left: constraints.maxWidth * 0.2,
                    right: constraints.maxWidth * 0.2,
                    child: Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.36),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(compact ? 8 : 14),
                    child: horizontal
                        ? Row(
                            children: [
                              glyph,
                              SizedBox(width: compact ? 8 : 14),
                              Expanded(child: text),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              glyph,
                              const SizedBox(height: 8),
                              Flexible(child: text),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _IOSWidgetText extends StatelessWidget {
  const _IOSWidgetText({
    required this.label,
    required this.value,
    required this.details,
    required this.enabled,
    required this.compact,
    required this.textAlign,
  });

  final String label;
  final String? value;
  final String? details;
  final bool enabled;
  final bool compact;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.start
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white60,
            fontSize: compact ? 11 : 13,
            height: 1,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black38, blurRadius: 4)],
          ),
        ),
        if (value != null) ...[
          const SizedBox(height: 4),
          Text(
            value!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white54,
              fontSize: compact ? 15 : 20,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
        if (details != null && !compact) ...[
          const SizedBox(height: 5),
          Text(
            details!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              height: 1.15,
            ),
          ),
        ],
      ],
    );
  }
}
