import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:flutter/material.dart';

class ModulePageRoute<T> extends MaterialPageRoute<T> {
  final ModuleId moduleId;

  ModulePageRoute({
    required this.moduleId,
    required super.builder,
    super.fullscreenDialog,
  });
}

class ModuleNavigationObserver extends NavigatorObserver {
  final ValueNotifier<ModuleId> activeModule;
  final Map<Route<dynamic>, ModuleId> _previousModules = {};
  ModuleId rootModule;

  ModuleNavigationObserver({
    required this.activeModule,
    required this.rootModule,
  });

  void setRootModule(ModuleId moduleId) {
    rootModule = moduleId;
    if (navigator?.canPop() != true) {
      activeModule.value = moduleId;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_moduleFor(route) case final ModuleId moduleId) {
      _previousModules[route] = activeModule.value;
      activeModule.value = moduleId;
    } else if (previousRoute == null) {
      activeModule.value = rootModule;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_moduleFor(route) == null) return;
    activeModule.value = _previousModules.remove(route) ?? rootModule;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (_moduleFor(newRoute) case final ModuleId moduleId) {
      _previousModules[newRoute!] = oldRoute == null
          ? activeModule.value
          : _previousModules.remove(oldRoute) ?? activeModule.value;
      activeModule.value = moduleId;
    } else if (oldRoute != null && _moduleFor(oldRoute) != null) {
      activeModule.value = _previousModules.remove(oldRoute) ?? rootModule;
    } else if (newRoute?.isFirst == true) {
      activeModule.value = rootModule;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_moduleFor(route) == null) return;
    activeModule.value = _previousModules.remove(route) ?? rootModule;
  }

  ModuleId? _moduleFor(Route<dynamic>? route) {
    if (route is ModulePageRoute<dynamic>) return route.moduleId;
    return route?.settings.arguments is ModuleId
        ? route!.settings.arguments as ModuleId
        : null;
  }
}

class ModuleVersionScope extends InheritedNotifier<ValueNotifier<ModuleId>> {
  const ModuleVersionScope({
    required ValueNotifier<ModuleId> notifier,
    required super.child,
    super.key,
  }) : super(notifier: notifier);

  static ValueNotifier<ModuleId>? maybeNotifierOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<ModuleVersionScope>()
        ?.notifier;
  }
}
