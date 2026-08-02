import 'dart:async';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum UndercoverDestination {
  status,
  wallet,
  files,
  camera,
  shortcuts,
  utilities,
  settings,
  passwords,
  diagnostics,
}

class UndercoverLauncher extends StatefulWidget {
  const UndercoverLauncher({
    super.key,
    required this.connected,
    required this.onExitRequested,
  });

  final bool connected;
  final VoidCallback onExitRequested;

  @override
  State<UndercoverLauncher> createState() => _UndercoverLauncherState();
}

class _UndercoverLauncherState extends State<UndercoverLauncher> {
  Timer? _clockTimer;
  UndercoverDestination? _activeDestination;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _handleConcealedBack() {
    if (_activeDestination != null) {
      setState(() => _activeDestination = null);
    } else {
      widget.onExitRequested();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final apps = _apps(localizations);
    final activeIndex = apps.indexWhere(
      (app) => app.destination == _activeDestination,
    );
    final active = activeIndex < 0 ? null : apps[activeIndex];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF171A35),
        statusBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleConcealedBack();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape):
                _handleConcealedBack,
          },
          child: Focus(
            autofocus: true,
            child: Material(
              key: const Key('undercover-launcher'),
              color: const Color(0xFF171A35),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _Wallpaper(),
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth.clamp(0.0, 620.0);
                        final columns = width >= 560 ? 6 : 4;
                        final textScale = MediaQuery.textScalerOf(
                          context,
                        ).scale(1);
                        final iconAspectRatio =
                            (0.76 - (textScale - 1).clamp(0.0, 2.0) * 0.16)
                                .clamp(0.5, 0.76)
                                .toDouble();
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: CustomScrollView(
                              physics: const BouncingScrollPhysics(),
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    4,
                                    20,
                                    12,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: _StatusBar(now: DateTime.now()),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    4,
                                    18,
                                    22,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: AnimatedSwitcher(
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 260),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      child: active == null
                                          ? _OverviewWidgets(
                                              key: const ValueKey('overview'),
                                              connected: widget.connected,
                                              onExitRequested:
                                                  widget.onExitRequested,
                                            )
                                          : _FacadeWidget(
                                              key: ValueKey(active.destination),
                                              app: active,
                                              connected: widget.connected,
                                              onClose: () => setState(
                                                () => _activeDestination = null,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          childAspectRatio: iconAspectRatio,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                        ),
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final app = apps[index];
                                      return _LauncherIcon(
                                        app: app,
                                        selected:
                                            app.destination ==
                                            _activeDestination,
                                        onTap: () => setState(
                                          () => _activeDestination =
                                              app.destination,
                                        ),
                                      );
                                    }, childCount: apps.length),
                                  ),
                                ),
                                const SliverPadding(
                                  padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
                                  sliver: SliverToBoxAdapter(child: _Dock()),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101D3D), Color(0xFF463A72), Color(0xFFBE667B)],
          stops: [0, 0.56, 1],
        ),
      ),
      child: Stack(
        children: const [
          Positioned(
            top: -130,
            right: -90,
            child: _Glow(size: 300, color: Color(0x5575D7FF)),
          ),
          Positioned(
            bottom: 70,
            left: -120,
            child: _Glow(size: 320, color: Color(0x55FF8A9E)),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(now));
    return Row(
      children: [
        Text(
          time,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const Spacer(),
        const Icon(Icons.signal_cellular_alt_rounded, size: 17),
        const SizedBox(width: 6),
        const Icon(Icons.wifi_rounded, size: 17),
        const SizedBox(width: 6),
        const Icon(Icons.battery_5_bar_rounded, size: 19),
      ],
    );
  }
}

class _OverviewWidgets extends StatelessWidget {
  const _OverviewWidgets({
    super.key,
    required this.connected,
    required this.onExitRequested,
  });

  final bool connected;
  final VoidCallback onExitRequested;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final materialLocalizations = MaterialLocalizations.of(context);
    final localizations = AppLocalizations.of(context)!;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight = 176 + (textScale - 1).clamp(0.0, 2.0).toDouble() * 96;
    final calendarCard = Semantics(
      label: localizations.undercover_calendar,
      button: true,
      onLongPress: onExitRequested,
      child: GestureDetector(
        key: const Key('undercover-exit-anchor'),
        behavior: HitTestBehavior.opaque,
        onLongPress: onExitRequested,
        child: _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                materialLocalizations.formatMediumDate(now).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFB6C7),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${now.day}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 58,
                  height: 0.9,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                localizations.undercover_no_events,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
    final weatherCard = _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_outlined, color: Colors.white, size: 22),
              Spacer(),
              Text(
                '21°',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            localizations.home,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: connected ? const Color(0xFF62E6A6) : Colors.white54,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  connected
                      ? localizations.undercover_hub_connected
                      : localizations.undercover_hub_offline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (textScale > 1.5 && constraints.maxWidth < 420) {
          return Column(
            children: [
              SizedBox(height: cardHeight, child: calendarCard),
              const SizedBox(height: 12),
              SizedBox(height: cardHeight, child: weatherCard),
            ],
          );
        }
        return SizedBox(
          height: cardHeight,
          child: Row(
            children: [
              Expanded(child: calendarCard),
              const SizedBox(width: 12),
              Expanded(child: weatherCard),
            ],
          ),
        );
      },
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xB5242940),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LauncherIcon extends StatelessWidget {
  const _LauncherIcon({
    required this.app,
    required this.selected,
    required this.onTap,
  });

  final _UndercoverApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: app.title,
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: app.colors,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x45000000),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    key: Key('undercover-app-${app.destination.name}'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: onTap,
                    child: Icon(app.icon, color: Colors.white, size: 34),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            app.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
            ),
          ),
        ],
      ),
    );
  }
}

class _FacadeWidget extends StatelessWidget {
  const _FacadeWidget({
    super.key,
    required this.app,
    required this.connected,
    required this.onClose,
  });

  final _UndercoverApp app;
  final bool connected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final content = _facadeContent(app.destination, connected, localizations);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactLargeText =
        textScale > 1.5 && MediaQuery.sizeOf(context).width < 420;
    return SizedBox(
      key: const Key('undercover-facade'),
      height: 176 + (textScale - 1).clamp(0.0, 2.0).toDouble() * 96,
      child: _GlassCard(
        child: Row(
          children: [
            if (!compactLargeText)
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: app.colors),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(app.icon, color: Colors.white, size: 32),
              ),
            if (!compactLargeText) const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 19,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: onClose,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  for (final line in content)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        children: [
                          Icon(line.icon, color: Colors.white70, size: 17),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              line.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              line.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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

class _Dock extends StatelessWidget {
  const _Dock();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: Colors.white24),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _DockIcon(icon: Icons.phone_rounded, color: Color(0xFF4DD276)),
          _DockIcon(icon: Icons.chat_bubble_rounded, color: Color(0xFF53D86A)),
          _DockIcon(icon: Icons.explore_rounded, color: Color(0xFF4CA6F8)),
          _DockIcon(icon: Icons.music_note_rounded, color: Color(0xFFEF4F68)),
        ],
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: Colors.white, size: 29),
    );
  }
}

class _UndercoverApp {
  const _UndercoverApp({
    required this.destination,
    required this.title,
    required this.icon,
    required this.colors,
  });

  final UndercoverDestination destination;
  final String title;
  final IconData icon;
  final List<Color> colors;
}

class _FacadeLine {
  const _FacadeLine(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

List<_UndercoverApp> _apps(AppLocalizations localizations) => [
  _UndercoverApp(
    destination: UndercoverDestination.status,
    title: localizations.undercover_app_status,
    icon: Icons.cloud_rounded,
    colors: const [Color(0xFF5BA7FF), Color(0xFF3765D7)],
  ),
  _UndercoverApp(
    destination: UndercoverDestination.wallet,
    title: localizations.undercover_app_wallet,
    icon: Icons.account_balance_wallet_rounded,
    colors: const [Color(0xFF43475C), Color(0xFF161821)],
  ),
  _UndercoverApp(
    destination: UndercoverDestination.files,
    title: localizations.undercover_app_files,
    icon: Icons.folder_rounded,
    colors: const [Color(0xFF6AC5FF), Color(0xFF3478F6)],
  ),
  _UndercoverApp(
    destination: UndercoverDestination.camera,
    title: localizations.undercover_app_camera,
    icon: Icons.camera_alt_rounded,
    colors: const [Color(0xFF7B7F8C), Color(0xFF292C35)],
  ),
  _UndercoverApp(
    destination: UndercoverDestination.shortcuts,
    title: localizations.undercover_app_shortcuts,
    icon: Icons.auto_awesome_rounded,
    colors: const [Color(0xFFFF7A59), Color(0xFFB742D1)],
  ),
  _UndercoverApp(
    destination: UndercoverDestination.utilities,
    title: localizations.undercover_app_utilities,
    icon: Icons.tune_rounded,
    colors: const [Color(0xFF69707C), Color(0xFF242832)],
  ),
  _UndercoverApp(
    destination: UndercoverDestination.settings,
    title: localizations.undercover_app_settings,
    icon: Icons.settings_rounded,
    colors: const [Color(0xFFA8ACB5), Color(0xFF636874)],
  ),
  _UndercoverApp(
    destination: UndercoverDestination.passwords,
    title: localizations.undercover_app_passwords,
    icon: Icons.key_rounded,
    colors: const [Color(0xFF7BD7C2), Color(0xFF198F83)],
  ),
  _UndercoverApp(
    destination: UndercoverDestination.diagnostics,
    title: localizations.undercover_app_diagnostics,
    icon: Icons.health_and_safety_rounded,
    colors: const [Color(0xFFFF7189), Color(0xFFCE304D)],
  ),
];

List<_FacadeLine> _facadeContent(
  UndercoverDestination destination,
  bool connected,
  AppLocalizations localizations,
) => switch (destination) {
  UndercoverDestination.status => [
    _FacadeLine(
      Icons.thermostat_rounded,
      localizations.undercover_indoor,
      '21°',
    ),
    _FacadeLine(
      Icons.water_drop_outlined,
      localizations.undercover_humidity,
      '48%',
    ),
    _FacadeLine(
      Icons.home_outlined,
      localizations.undercover_home_hub,
      connected
          ? localizations.undercover_connected
          : localizations.undercover_offline,
    ),
  ],
  UndercoverDestination.wallet => [
    _FacadeLine(
      Icons.credit_card_rounded,
      localizations.undercover_daily_card,
      localizations.undercover_ready,
    ),
    _FacadeLine(
      Icons.directions_transit_rounded,
      localizations.undercover_transit,
      localizations.undercover_express,
    ),
    _FacadeLine(
      Icons.receipt_long_rounded,
      localizations.undercover_latest_activity,
      localizations.undercover_today,
    ),
  ],
  UndercoverDestination.files => [
    _FacadeLine(
      Icons.description_outlined,
      localizations.undercover_project_notes,
      localizations.undercover_this_afternoon,
    ),
    _FacadeLine(
      Icons.image_outlined,
      localizations.undercover_reference_images,
      localizations.undercover_eight_items,
    ),
    _FacadeLine(
      Icons.cloud_done_outlined,
      localizations.undercover_cloud_drive,
      localizations.undercover_synced,
    ),
  ],
  UndercoverDestination.camera => [
    _FacadeLine(
      Icons.photo_camera_outlined,
      localizations.undercover_app_camera,
      localizations.undercover_ready,
    ),
    _FacadeLine(
      Icons.document_scanner_outlined,
      localizations.undercover_document_scan,
      localizations.undercover_auto,
    ),
    _FacadeLine(
      Icons.photo_library_outlined,
      localizations.undercover_recent,
      localizations.undercover_twelve_photos,
    ),
  ],
  UndercoverDestination.shortcuts => [
    _FacadeLine(
      Icons.bedtime_outlined,
      localizations.undercover_evening_scene,
      localizations.undercover_on_tap,
    ),
    _FacadeLine(
      Icons.directions_car_outlined,
      localizations.undercover_drive_home,
      localizations.undercover_eighteen_minutes,
    ),
    _FacadeLine(
      Icons.timer_outlined,
      localizations.undercover_focus_timer,
      localizations.undercover_twenty_five_minutes,
    ),
  ],
  UndercoverDestination.utilities => [
    _FacadeLine(Icons.speed_rounded, localizations.undercover_level, '0°'),
    _FacadeLine(
      Icons.explore_outlined,
      localizations.undercover_compass,
      localizations.undercover_northwest,
    ),
    _FacadeLine(
      Icons.calculate_outlined,
      localizations.undercover_calculator,
      localizations.undercover_ready,
    ),
  ],
  UndercoverDestination.settings => [
    _FacadeLine(
      Icons.wifi_rounded,
      localizations.undercover_wifi,
      localizations.home,
    ),
    _FacadeLine(
      Icons.bluetooth_rounded,
      localizations.bluetooth,
      localizations.undercover_on,
    ),
    _FacadeLine(
      Icons.notifications_none_rounded,
      localizations.undercover_notifications,
      localizations.undercover_summary,
    ),
  ],
  UndercoverDestination.passwords => [
    _FacadeLine(
      Icons.shield_outlined,
      localizations.undercover_security,
      localizations.undercover_good,
    ),
    _FacadeLine(
      Icons.autorenew_rounded,
      localizations.undercover_updated,
      localizations.undercover_today,
    ),
    _FacadeLine(
      Icons.devices_outlined,
      localizations.undercover_trusted_devices,
      '3',
    ),
  ],
  UndercoverDestination.diagnostics => [
    _FacadeLine(
      Icons.check_circle_outline,
      localizations.system,
      localizations.undercover_normal,
    ),
    _FacadeLine(
      Icons.battery_charging_full_rounded,
      localizations.undercover_battery,
      localizations.undercover_optimized,
    ),
    _FacadeLine(
      Icons.storage_outlined,
      localizations.undercover_storage,
      localizations.available,
    ),
  ],
};
