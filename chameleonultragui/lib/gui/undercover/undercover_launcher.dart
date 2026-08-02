import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UndercoverMenuScreen {
  const UndercoverMenuScreen({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.apps,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<UndercoverAppEntry> apps;
}

class UndercoverAppEntry {
  const UndercoverAppEntry({
    required this.id,
    required this.title,
    required this.menuPath,
    required this.icon,
    required this.accent,
    required this.onOpen,
    this.requiresConnection = false,
  });

  final String id;
  final String title;
  final String menuPath;
  final IconData icon;
  final Color accent;
  final VoidCallback onOpen;
  final bool requiresConnection;
}

class UndercoverLauncher extends StatefulWidget {
  const UndercoverLauncher({
    super.key,
    required this.connected,
    required this.screens,
    required this.onExitRequested,
  });

  final bool connected;
  final List<UndercoverMenuScreen> screens;
  final VoidCallback onExitRequested;

  @override
  State<UndercoverLauncher> createState() => _UndercoverLauncherState();
}

class _UndercoverLauncherState extends State<UndercoverLauncher> {
  late final PageController _pageController;
  final TextEditingController _appSearchController = TextEditingController();
  final TextEditingController _actionSearchController = TextEditingController();
  Timer? _clockTimer;
  UndercoverAppEntry? _activeApp;
  int _page = 0;
  String _appQuery = '';
  String _actionQuery = '';
  bool _showAppInfo = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scheduleClockRefresh();
  }

  @override
  void didUpdateWidget(covariant UndercoverLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.screens.isEmpty) {
      _page = 0;
    } else if (_page >= widget.screens.length) {
      _page = widget.screens.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_page);
        }
      });
    }

    final activeId = _activeApp?.id;
    if (activeId == null) return;
    UndercoverAppEntry? replacement;
    for (final screen in widget.screens) {
      for (final app in screen.apps) {
        if (app.id == activeId) replacement = app;
      }
    }
    if (replacement?.requiresConnection == true && !widget.connected) {
      _activeApp = null;
      _actionQuery = '';
      _showAppInfo = false;
      _actionSearchController.clear();
    } else {
      _activeApp = replacement;
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pageController.dispose();
    _appSearchController.dispose();
    _actionSearchController.dispose();
    super.dispose();
  }

  void _scheduleClockRefresh() {
    _clockTimer?.cancel();
    final now = DateTime.now();
    final millisecondsToNextMinute =
        60000 - (now.second * 1000 + now.millisecond);
    _clockTimer = Timer(Duration(milliseconds: millisecondsToNextMinute), () {
      if (!mounted) return;
      setState(() {});
      _scheduleClockRefresh();
    });
  }

  void _showPage(int index) {
    if (index < 0 || index >= widget.screens.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _openActionBoard(UndercoverAppEntry app) {
    _actionSearchController.clear();
    setState(() {
      _activeApp = app;
      _actionQuery = '';
      _showAppInfo = false;
    });
  }

  void _closeActionBoard() {
    _actionSearchController.clear();
    setState(() {
      _activeApp = null;
      _actionQuery = '';
      _showAppInfo = false;
    });
  }

  void _handleBack() {
    if (_activeApp != null) {
      _closeActionBoard();
      return;
    }
    widget.onExitRequested();
  }

  @override
  Widget build(BuildContext context) {
    final activeApp = _activeApp;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final content = activeApp == null
        ? _SpringBoard(
            key: const ValueKey('undercover-springboard'),
            connected: widget.connected,
            screens: widget.screens,
            pageController: _pageController,
            selectedIndex: _page,
            query: _appQuery,
            searchController: _appSearchController,
            onQueryChanged: (value) => setState(() => _appQuery = value),
            onPageChanged: (value) => setState(() => _page = value),
            onPageSelected: _showPage,
            onAppSelected: _openActionBoard,
          )
        : _AppActionBoard(
            key: ValueKey('undercover-actions-${activeApp.id}'),
            app: activeApp,
            connected: widget.connected,
            query: _actionQuery,
            searchController: _actionSearchController,
            showInfo: _showAppInfo,
            onQueryChanged: (value) => setState(() => _actionQuery = value),
            onOpen: activeApp.onOpen,
            onToggleInfo: () => setState(() => _showAppInfo = !_showAppInfo),
            onHome: _closeActionBoard,
            onExitRequested: widget.onExitRequested,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF171A35),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _handleBack,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              if (_activeApp == null) _showPage(_page - 1);
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              if (_activeApp == null) _showPage(_page + 1);
            },
          },
          child: Focus(
            autofocus: true,
            child: Material(
              key: const Key('undercover-launcher'),
              color: const Color(0xFF171A35),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _SpringBoardWallpaper(),
                  SafeArea(
                    child: Column(
                      children: [
                        _IOSStatusBar(
                          connected: widget.connected,
                          now: DateTime.now(),
                          onExitRequested: widget.onExitRequested,
                        ),
                        Expanded(
                          child: reduceMotion
                              ? content
                              : AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 280),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: 0.97,
                                          end: 1,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: content,
                                ),
                        ),
                      ],
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

class _SpringBoard extends StatelessWidget {
  const _SpringBoard({
    super.key,
    required this.connected,
    required this.screens,
    required this.pageController,
    required this.selectedIndex,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onPageChanged,
    required this.onPageSelected,
    required this.onAppSelected,
  });

  final bool connected;
  final List<UndercoverMenuScreen> screens;
  final PageController pageController;
  final int selectedIndex;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSelected;
  final ValueChanged<UndercoverAppEntry> onAppSelected;

  @override
  Widget build(BuildContext context) {
    if (screens.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final index = selectedIndex.clamp(0, screens.length - 1);
    final screen = screens[index];

    return Column(
      children: [
        _BoardHeading(screen: screen),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
          child: _IOSSearchField(
            key: const Key('undercover-app-search'),
            controller: searchController,
            hintText: 'Search ${screen.title}',
            query: query,
            onChanged: onQueryChanged,
          ),
        ),
        Expanded(
          child: PageView.builder(
            key: const Key('undercover-page-view'),
            controller: pageController,
            onPageChanged: onPageChanged,
            itemCount: screens.length,
            itemBuilder: (context, pageIndex) => _AppGrid(
              key: Key('undercover-screen-${screens[pageIndex].id}'),
              screen: screens[pageIndex],
              connected: connected,
              query: query,
              onAppSelected: onAppSelected,
            ),
          ),
        ),
        _PageIndicator(
          screens: screens,
          selectedIndex: index,
          onSelected: onPageSelected,
        ),
        _CategoryDock(
          screens: screens,
          selectedIndex: index,
          onSelected: onPageSelected,
        ),
      ],
    );
  }
}

class _BoardHeading extends StatelessWidget {
  const _BoardHeading({required this.screen});

  final UndercoverMenuScreen screen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 0),
      child: Column(
        children: [
          Semantics(
            header: true,
            child: Text(
              screen.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                height: 1.08,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            screen.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.15,
              shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({
    super.key,
    required this.screen,
    required this.connected,
    required this.query,
    required this.onAppSelected,
  });

  final UndercoverMenuScreen screen;
  final bool connected;
  final String query;
  final ValueChanged<UndercoverAppEntry> onAppSelected;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final apps = normalizedQuery.isEmpty
        ? screen.apps
        : screen.apps
              .where(
                (app) =>
                    app.title.toLowerCase().contains(normalizedQuery) ||
                    app.menuPath.toLowerCase().contains(normalizedQuery),
              )
              .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 7
            : width >= 600
            ? 6
            : width >= 350
            ? 4
            : 3;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final aspectRatio = (0.82 - (textScale - 1).clamp(0.0, 2.0) * 0.13)
            .clamp(0.56, 0.82)
            .toDouble();

        if (apps.isEmpty) {
          return Center(
            child: _IOSWidget(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Text(
                'No apps found on ${screen.title}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        return GridView.builder(
          key: PageStorageKey('undercover-grid-${screen.id}'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: aspectRatio,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: apps.length,
          itemBuilder: (context, index) {
            final app = apps[index];
            return _HomeAppIcon(
              app: app,
              enabled: !app.requiresConnection || connected,
              onTap: () => onAppSelected(app),
            );
          },
        );
      },
    );
  }
}

class _HomeAppIcon extends StatelessWidget {
  const _HomeAppIcon({
    required this.app,
    required this.enabled,
    required this.onTap,
  });

  final UndercoverAppEntry app;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = constraints.maxWidth.clamp(52.0, 68.0);
        final labelColor = enabled ? Colors.white : Colors.white54;
        return Semantics(
          button: true,
          enabled: enabled,
          label: '${app.title}, ${app.menuPath}',
          child: Column(
            children: [
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(iconSize * 0.23),
                        child: InkWell(
                          key: Key('undercover-app-${app.id}'),
                          borderRadius: BorderRadius.circular(iconSize * 0.23),
                          onTap: enabled ? onTap : null,
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: enabled
                                    ? [
                                        Color.lerp(
                                          app.accent,
                                          Colors.white,
                                          0.22,
                                        )!,
                                        Color.lerp(
                                          app.accent,
                                          Colors.black,
                                          0.24,
                                        )!,
                                      ]
                                    : const [
                                        Color(0xFF777780),
                                        Color(0xFF3A3A3C),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(
                                iconSize * 0.23,
                              ),
                              border: Border.all(color: Colors.white24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(
                              app.icon,
                              color: enabled ? Colors.white : Colors.white60,
                              size: iconSize * 0.48,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!enabled)
                      const Positioned(
                        right: -5,
                        bottom: -4,
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: Color(0xFF1C1C1E),
                          child: Icon(
                            Icons.lock_rounded,
                            size: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  app.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 6),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                app.menuPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white38,
                  fontSize: 9,
                  height: 1,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppActionBoard extends StatelessWidget {
  const _AppActionBoard({
    super.key,
    required this.app,
    required this.connected,
    required this.query,
    required this.searchController,
    required this.showInfo,
    required this.onQueryChanged,
    required this.onOpen,
    required this.onToggleInfo,
    required this.onHome,
    required this.onExitRequested,
  });

  final UndercoverAppEntry app;
  final bool connected;
  final String query;
  final TextEditingController searchController;
  final bool showInfo;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onOpen;
  final VoidCallback onToggleInfo;
  final VoidCallback onHome;
  final VoidCallback onExitRequested;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _AppAction(
        id: 'open',
        title: 'Open App',
        subtitle: app.requiresConnection && !connected
            ? 'Connection required'
            : app.title,
        icon: Icons.arrow_upward_rounded,
        colors: [Color.lerp(app.accent, Colors.white, 0.18)!, app.accent],
        enabled: !app.requiresConnection || connected,
        onTap: onOpen,
      ),
      _AppAction(
        id: 'info',
        title: showInfo ? 'Hide Info' : 'App Info',
        subtitle: app.menuPath,
        icon: Icons.info_outline_rounded,
        colors: const [Color(0xFF64D2FF), Color(0xFF0A84FF)],
        onTap: onToggleInfo,
      ),
      _AppAction(
        id: 'home',
        title: 'Home Screen',
        subtitle: 'All menus',
        icon: Icons.apps_rounded,
        colors: const [Color(0xFFBF5AF2), Color(0xFF7D3CC8)],
        onTap: onHome,
      ),
      _AppAction(
        id: 'exit',
        title: 'Exit Mode',
        subtitle: 'Restore navigation',
        icon: Icons.lock_open_rounded,
        colors: const [Color(0xFFFF6961), Color(0xFFD70015)],
        onTap: onExitRequested,
      ),
    ];
    final normalizedQuery = query.trim().toLowerCase();
    final visibleActions = normalizedQuery.isEmpty
        ? actions
        : actions
              .where(
                (action) =>
                    action.title.toLowerCase().contains(normalizedQuery) ||
                    action.subtitle.toLowerCase().contains(normalizedQuery),
              )
              .toList();

    return CustomScrollView(
      key: const Key('undercover-action-board'),
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: _ActionHeader(app: app, onBack: onHome),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: _IOSWidget(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              (connected
                                      ? const Color(0xFF30D158)
                                      : const Color(0xFFFF9F0A))
                                  .withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          connected
                              ? Icons.wifi_rounded
                              : Icons.offline_bolt_rounded,
                          color: connected
                              ? const Color(0xFF30D158)
                              : const Color(0xFFFF9F0A),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected ? 'Device connected' : 'Local mode',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              app.requiresConnection
                                  ? 'This app uses the active device connection.'
                                  : 'This app can run without a device connection.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: _IOSSearchField(
                  key: const Key('undercover-action-search'),
                  controller: searchController,
                  hintText: 'Find an action',
                  query: query,
                  onChanged: onQueryChanged,
                ),
              ),
            ),
          ),
        ),
        if (showInfo)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: _IOSWidget(
                    key: const Key('undercover-app-info'),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          app.menuPath,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          app.requiresConnection
                              ? 'Requires an active Chameleon connection.'
                              : 'Available in local and connected sessions.',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final columns = width >= 720
                  ? 6
                  : width >= 520
                  ? 5
                  : width >= 350
                  ? 4
                  : 3;
              if (visibleActions.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Text(
                      'No actions found',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 0.74,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final action = visibleActions[index];
                  return _ActionIcon(appId: app.id, action: action);
                }, childCount: visibleActions.length),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActionHeader extends StatelessWidget {
  const _ActionHeader({required this.app, required this.onBack});

  final UndercoverAppEntry app;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('undercover-action-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.16),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        const SizedBox(width: 10),
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(app.accent, Colors.white, 0.22)!,
                Color.lerp(app.accent, Colors.black, 0.24)!,
              ],
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Icon(app.icon, color: Colors.white, size: 29),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                app.menuPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppAction {
  const _AppAction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.enabled = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool enabled;
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.appId, required this.action});

  final String appId;
  final _AppAction action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: action.enabled,
      label: '${action.title}, ${action.subtitle}',
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  key: Key('undercover-action-${action.id}-$appId'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: action.enabled ? action.onTap : null,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: action.enabled
                            ? action.colors
                            : const [Color(0xFF777780), Color(0xFF3A3A3C)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 14,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Icon(
                      action.enabled ? action.icon : Icons.lock_rounded,
                      color: action.enabled ? Colors.white : Colors.white60,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            action.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            action.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 9,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _IOSSearchField extends StatelessWidget {
  const _IOSSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.query,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _IOSWidget(
      radius: 14,
      padding: EdgeInsets.zero,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white60),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(
                    Icons.cancel_rounded,
                    color: Colors.white54,
                    size: 19,
                  ),
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

class _IOSStatusBar extends StatelessWidget {
  const _IOSStatusBar({
    required this.connected,
    required this.now,
    required this.onExitRequested,
  });

  final bool connected;
  final DateTime now;
  final VoidCallback onExitRequested;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(now));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Exit Undercover',
            onLongPress: onExitRequested,
            child: GestureDetector(
              key: const Key('undercover-exit-anchor'),
              behavior: HitTestBehavior.opaque,
              onLongPress: onExitRequested,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Text(
                  time,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Icon(
            connected
                ? Icons.signal_cellular_alt_rounded
                : Icons.signal_cellular_0_bar,
            color: Colors.white,
            size: 17,
          ),
          const SizedBox(width: 6),
          Icon(
            connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: Colors.white,
            size: 17,
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.battery_5_bar_rounded,
            color: Colors.white,
            size: 19,
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const Key('undercover-exit-button'),
            tooltip: 'Exit Undercover',
            onPressed: onExitRequested,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.screens,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<UndercoverMenuScreen> screens;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: _IOSWidget(
        radius: 15,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < screens.length; index++)
              Semantics(
                button: true,
                selected: index == selectedIndex,
                label: screens[index].title,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => onSelected(index),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: index == selectedIndex ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: index == selectedIndex
                              ? Colors.white
                              : Colors.white38,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDock extends StatelessWidget {
  const _CategoryDock({
    required this.screens,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<UndercoverMenuScreen> screens;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: _IOSWidget(
        radius: 27,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var index = 0; index < screens.length; index++)
                      Tooltip(
                        message: screens[index].title,
                        child: Semantics(
                          button: true,
                          selected: index == selectedIndex,
                          label: screens[index].title,
                          child: IconButton(
                            key: Key('undercover-page-${screens[index].id}'),
                            onPressed: () => onSelected(index),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              foregroundColor: Colors.white,
                              backgroundColor: index == selectedIndex
                                  ? screens[index].accent
                                  : Colors.white.withValues(alpha: 0.12),
                              side: BorderSide(
                                color: index == selectedIndex
                                    ? Colors.white38
                                    : Colors.white12,
                              ),
                            ),
                            icon: Icon(screens[index].icon, size: 21),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IOSWidget extends StatelessWidget {
  const _IOSWidget({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 22,
                offset: Offset(0, 11),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _SpringBoardWallpaper extends StatelessWidget {
  const _SpringBoardWallpaper();

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
            child: _WallpaperGlow(size: 340, color: Color(0x6675D7FF)),
          ),
          Positioned(
            top: 230,
            left: -150,
            child: _WallpaperGlow(size: 360, color: Color(0x557C5CFC)),
          ),
          Positioned(
            bottom: -130,
            right: -90,
            child: _WallpaperGlow(size: 350, color: Color(0x66FF8A9E)),
          ),
        ],
      ),
    );
  }
}

class _WallpaperGlow extends StatelessWidget {
  const _WallpaperGlow({required this.size, required this.color});

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
