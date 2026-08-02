import 'dart:async';

import 'package:chameleonultragui/gui/undercover/undercover_orientation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mobile controller locks portrait and restores system orientations',
    () async {
      final calls = <List<DeviceOrientation>>[];
      final controller = SystemUndercoverOrientationController(
        isMobile: true,
        setOrientations: (orientations) async => calls.add(orientations),
      );

      await controller.lockPortrait();
      await controller.restore();

      expect(calls, [
        [DeviceOrientation.portraitUp],
        <DeviceOrientation>[],
      ]);
    },
  );

  test('desktop controller leaves orientation untouched', () async {
    var calls = 0;
    final controller = SystemUndercoverOrientationController(
      isMobile: false,
      setOrientations: (_) async => calls++,
    );

    await controller.lockPortrait();
    await controller.restore();

    expect(calls, 0);
  });

  testWidgets('orientation scope locks once and restores on dispose', (
    tester,
  ) async {
    final controller = _RecordingOrientationController();
    await tester.pumpWidget(
      UndercoverOrientationScope(
        controller: controller,
        child: const Text('Undercover', textDirection: TextDirection.ltr),
      ),
    );
    await tester.pump();
    expect(controller.events, ['lock']);

    await tester.pumpWidget(
      UndercoverOrientationScope(
        controller: controller,
        child: const Text('Rebuilt', textDirection: TextDirection.ltr),
      ),
    );
    await tester.pump();
    expect(controller.events, ['lock']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.events, ['lock', 'restore']);
  });

  testWidgets('a replacement scope cannot be unlocked by an old restore', (
    tester,
  ) async {
    final first = _DelayedOrientationController();
    final second = _RecordingOrientationController();
    await tester.pumpWidget(
      UndercoverOrientationScope(
        key: const ValueKey('first'),
        controller: first,
        child: const SizedBox(),
      ),
    );
    expect(first.events, ['lock']);

    await tester.pumpWidget(
      UndercoverOrientationScope(
        key: const ValueKey('second'),
        controller: second,
        child: const SizedBox(),
      ),
    );
    first.releaseLock.complete();
    await tester.pump();
    await tester.pump();

    expect(first.events, ['lock']);
    expect(second.events, ['lock']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(second.events, ['lock', 'restore']);
  });
}

class _RecordingOrientationController
    implements UndercoverOrientationController {
  final events = <String>[];

  @override
  Future<void> lockPortrait() async {
    events.add('lock');
  }

  @override
  Future<void> restore() async {
    events.add('restore');
  }
}

class _DelayedOrientationController implements UndercoverOrientationController {
  final events = <String>[];
  final releaseLock = Completer<void>();

  @override
  Future<void> lockPortrait() async {
    events.add('lock');
    await releaseLock.future;
  }

  @override
  Future<void> restore() async {
    events.add('restore');
  }
}
