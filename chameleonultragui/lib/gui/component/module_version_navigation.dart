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
    if (route case ModulePageRoute<dynamic>(:final moduleId)) {
      activeModule.value = moduleId;
    } else if (previousRoute == null) {
      activeModule.value = rootModule;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute case ModulePageRoute<dynamic>(:final moduleId)) {
      activeModule.value = moduleId;
    } else if (previousRoute?.isFirst == true) {
      activeModule.value = rootModule;
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute case ModulePageRoute<dynamic>(:final moduleId)) {
      activeModule.value = moduleId;
    } else if (newRoute?.isFirst == true) {
      activeModule.value = rootModule;
    }
  }
}
