import 'dart:async';
import 'dart:math' as math;
import 'package:chameleonultragui/gui/undercover/undercover_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UndercoverMenuScreen {
  const UndercoverMenuScreen({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.apps = const [],
    this.dashboardBuilder,
  }) : assert(apps.length > 0 || dashboardBuilder != null);

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<UndercoverAppEntry> apps;
  final WidgetBuilder? dashboardBuilder;
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
    this.opensDirectly = false,
  });

  final String id;
  final String title;
  final String menuPath;
  final IconData icon;
  final Color accent;
  final VoidCallback onOpen;
  final bool requiresConnection;
  final bool opensDirectly;
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
  final TextEditingController _actionSearchController = TextEditingController();
  Timer? _clockTimer;
  UndercoverAppEntry? _activeApp;
  int _page = 0;
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
    if (app.opensDirectly) {
      app.onOpen();
      return;
    }
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
            onPageChanged: (value) => setState(() => _page = value),
            onPageSelected: _showPage,
            onAppSelected: _openActionBoard,
            onExitRequested: widget.onExitRequested,
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
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
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
    required this.onPageChanged,
    required this.onPageSelected,
    required this.onAppSelected,
    required this.onExitRequested,
  });

  final bool connected;
  final List<UndercoverMenuScreen> screens;
  final PageController pageController;
  final int selectedIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSelected;
  final ValueChanged<UndercoverAppEntry> onAppSelected;
  final VoidCallback onExitRequested;

  @override
  Widget build(BuildContext context) {
    if (screens.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final index = selectedIndex.clamp(0, screens.length - 1);
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            key: const Key('undercover-page-view'),
            controller: pageController,
            onPageChanged: onPageChanged,
            itemCount: screens.length,
            itemBuilder: (context, pageIndex) {
              final page = screens[pageIndex];
              final dashboardBuilder = page.dashboardBuilder;
              if (dashboardBuilder != null) {
                return KeyedSubtree(
                  key: Key('undercover-dashboard-${page.id}'),
                  child: dashboardBuilder(context),
                );
              }
              return _AppGrid(
                key: Key('undercover-screen-${page.id}'),
                screen: page,
                connected: connected,
                onAppSelected: onAppSelected,
              );
            },
          ),
        ),
        _PageIndicator(
          screens: screens,
          selectedIndex: index,
          onSelected: onPageSelected,
        ),
        _IPhoneDock(onExitRequested: onExitRequested),
      ],
    );
  }
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({
    super.key,
    required this.screen,
    required this.connected,
    required this.onAppSelected,
  });

  final UndercoverMenuScreen screen;
  final bool connected;
  final ValueChanged<UndercoverAppEntry> onAppSelected;

  @override
  Widget build(BuildContext context) {
    final apps = screen.apps;

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

    return UndercoverSpringGrid(
      key: PageStorageKey('undercover-grid-${screen.id}'),
      placements: [
        for (var index = 0; index < apps.length && index < 24; index++)
          UndercoverGridPlacement(
            row: index ~/ 4,
            column: index % 4,
            rowSpan: 1,
            columnSpan: 1,
            child: _HomeAppIcon(
              app: apps[index],
              enabled: !apps[index].requiresConnection || connected,
              onTap: () => onAppSelected(apps[index]),
            ),
          ),
      ],
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
    return UndercoverGridTile(
      key: Key('undercover-app-${app.id}'),
      label: app.title,
      details: app.menuPath,
      icon: app.icon,
      color: app.accent,
      enabled: enabled,
      onPressed: onTap,
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
        title: 'My Week',
        subtitle: 'All lists',
        icon: Icons.apps_rounded,
        colors: const [Color(0xFFBF5AF2), Color(0xFF7D3CC8)],
        onTap: onHome,
      ),
      _AppAction(
        id: 'exit',
        title: 'Done',
        subtitle: 'Close My Week',
        icon: Icons.check_circle_outline_rounded,
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
                              connected ? 'Cloud sync ready' : 'Offline mode',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              app.requiresConnection
                                  ? 'This item needs cloud sync to continue.'
                                  : 'This item is available offline.',
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
                              ? 'Available when cloud sync is ready.'
                              : 'Available online and offline.',
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
        UndercoverSquircleIcon(icon: app.icon, color: app.accent, size: 58),
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
                child: InkWell(
                  key: Key('undercover-action-${action.id}-$appId'),
                  customBorder: const ContinuousRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(36)),
                  ),
                  onTap: action.enabled ? action.onTap : null,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: UndercoverSquircleIcon(
                        icon: action.icon,
                        color: action.colors.last,
                        size: math.min(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                        enabled: action.enabled,
                      ),
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
            label: 'Current time',
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
          const SizedBox(width: 8),
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
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              screens[selectedIndex].title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
          const SizedBox(width: 10),
          for (var index = 0; index < screens.length; index++)
            Semantics(
              button: true,
              selected: index == selectedIndex,
              label: screens[index].title,
              child: GestureDetector(
                key: Key('undercover-page-${screens[index].id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(index),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: index == selectedIndex ? 15 : 6,
                    height: 6,
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
        ],
      ),
    );
  }
}

class _IPhoneDock extends StatelessWidget {
  const _IPhoneDock({required this.onExitRequested});

  final VoidCallback onExitRequested;

  void _showUnavailable(BuildContext context, String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          content: Text('$label is not available.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: _IOSWidget(
          radius: 29,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: _DockIcon(
                  key: const Key('undercover-dock-phone'),
                  label: 'Phone',
                  icon: Icons.phone_rounded,
                  colors: const [Color(0xFF55E96B), Color(0xFF16B93D)],
                  onTap: () => _showUnavailable(context, 'Phone'),
                ),
              ),
              Expanded(
                child: _DockIcon(
                  key: const Key('undercover-dock-messages'),
                  label: 'Messages',
                  icon: Icons.chat_bubble_rounded,
                  colors: const [Color(0xFF62EE7A), Color(0xFF18B943)],
                  onTap: () => _showUnavailable(context, 'Messages'),
                ),
              ),
              Expanded(
                child: _DockIcon(
                  key: const Key('undercover-dock-camera'),
                  label: 'Camera',
                  icon: Icons.camera_alt_rounded,
                  colors: const [Color(0xFFB8BBC2), Color(0xFF62656D)],
                  onTap: () => _showUnavailable(context, 'Camera'),
                ),
              ),
              Expanded(
                child: _DockIcon(
                  key: const Key('undercover-dock-chrome'),
                  label: 'Chrome',
                  icon: Icons.public_rounded,
                  colors: const [Color(0xFFEA4335), Color(0xFF4285F4)],
                  onTap: onExitRequested,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    super.key,
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UndercoverSquircleIcon(icon: icon, color: colors.last, size: 42),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE624273D),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _SpringBoardWallpaper extends StatelessWidget {
  const _SpringBoardWallpaper();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF101D3D), Color(0xFF4C3D79), Color(0xFFB45F7D)],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        Image.asset(
          'assets/iosBackground.png',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x22000000), Color(0x66000000)],
            ),
          ),
        ),
        const Positioned(
          top: -150,
          right: -110,
          child: _WallpaperGlow(size: 340, color: Color(0x4475D7FF)),
        ),
        const Positioned(
          bottom: -130,
          right: -90,
          child: _WallpaperGlow(size: 350, color: Color(0x44FF8A9E)),
        ),
      ],
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
