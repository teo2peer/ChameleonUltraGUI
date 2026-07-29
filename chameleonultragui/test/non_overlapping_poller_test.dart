import 'dart:async';

import 'package:chameleonultragui/helpers/non_overlapping_poller.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for poller state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  test('never overlaps tasks or builds a fixed-rate backlog', () async {
    final completions = <Completer<void>>[];
    var active = 0;
    var maxActive = 0;
    final poller = NonOverlappingPoller(
      interval: const Duration(milliseconds: 2),
      task: () async {
        active++;
        if (active > maxActive) maxActive = active;
        final completion = Completer<void>();
        completions.add(completion);
        await completion.future;
        active--;
      },
    );

    poller.start();
    await _waitFor(() => completions.length == 1);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(completions, hasLength(1));

    completions[0].complete();
    await _waitFor(() => completions.length == 2);
    expect(maxActive, 1);
    poller.stop();
    completions[1].complete();
  });

  test('stop during an active task prevents rescheduling', () async {
    final completion = Completer<void>();
    var calls = 0;
    final poller = NonOverlappingPoller(
      interval: const Duration(milliseconds: 1),
      task: () {
        calls++;
        return completion.future;
      },
    );

    poller.start();
    await _waitFor(() => calls == 1);
    poller.stop();
    completion.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(calls, 1);
    expect(poller.isActive, isFalse);
    expect(poller.isRunning, isFalse);
  });

  test('restart during an active task resumes once without overlap', () async {
    final completions = <Completer<void>>[];
    var active = 0;
    var maxActive = 0;
    final poller = NonOverlappingPoller(
      interval: const Duration(seconds: 1),
      task: () async {
        active++;
        if (active > maxActive) maxActive = active;
        final completion = Completer<void>();
        completions.add(completion);
        await completion.future;
        active--;
      },
    );

    poller.start();
    await _waitFor(() => completions.length == 1);
    poller.start();
    poller.start();
    expect(completions, hasLength(1));

    completions[0].complete();
    await _waitFor(() => completions.length == 2);
    expect(maxActive, 1);
    poller.stop();
    completions[1].complete();
  });

  test('reports task errors without leaking an unhandled future', () async {
    final errors = <Object>[];
    late final NonOverlappingPoller poller;
    poller = NonOverlappingPoller(
      interval: const Duration(seconds: 1),
      task: () async => throw StateError('poll failed'),
      onError: (error, _) {
        errors.add(error);
        poller.stop();
      },
    );

    poller.start();
    await _waitFor(() => errors.isNotEmpty);

    expect(errors.single, isA<StateError>());
    expect(poller.isActive, isFalse);
    expect(poller.isRunning, isFalse);
  });
}
