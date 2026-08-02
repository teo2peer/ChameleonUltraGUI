import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract interface class UndercoverOrientationController {
  Future<void> lockPortrait();
  Future<void> restore();
}

typedef OrientationSetter =
    Future<void> Function(List<DeviceOrientation> orientations);

class SystemUndercoverOrientationController
    implements UndercoverOrientationController {
  SystemUndercoverOrientationController({
    bool? isMobile,
    OrientationSetter? setOrientations,
  }) : _isMobile =
           isMobile ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS)),
       _setOrientations =
           setOrientations ?? SystemChrome.setPreferredOrientations;

  final bool _isMobile;
  final OrientationSetter _setOrientations;

  @override
  Future<void> lockPortrait() async {
    if (!_isMobile) return;
    await _setOrientations(const [DeviceOrientation.portraitUp]);
  }

  @override
  Future<void> restore() async {
    if (!_isMobile) return;
    await _setOrientations(const []);
  }
}

class UndercoverOrientationScope extends StatefulWidget {
  const UndercoverOrientationScope({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final UndercoverOrientationController? controller;

  @override
  State<UndercoverOrientationScope> createState() =>
      _UndercoverOrientationScopeState();
}

class _UndercoverOrientationScopeState
    extends State<UndercoverOrientationScope> {
  static Future<void> _operations = Future<void>.value();
  static int _activeScopes = 0;

  late final UndercoverOrientationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SystemUndercoverOrientationController();
    _activeScopes++;
    _schedule(_controller.lockPortrait);
  }

  void _schedule(Future<void> Function() operation) {
    _operations = _operations
        .then((_) => operation())
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _activeScopes--;
    _schedule(() async {
      if (_activeScopes == 0) await _controller.restore();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
