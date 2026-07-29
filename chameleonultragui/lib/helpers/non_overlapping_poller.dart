import 'dart:async';

class NonOverlappingPoller {
  NonOverlappingPoller({
    required this.interval,
    required this.task,
    this.onError,
  });

  final Duration interval;
  final Future<void> Function() task;
  final FutureOr<void> Function(Object error, StackTrace stackTrace)? onError;

  Timer? _timer;
  var _generation = 0;
  var _active = false;
  var _running = false;
  var _restartPending = false;

  bool get isActive => _active;
  bool get isRunning => _running;

  void start({bool immediate = true}) {
    _generation++;
    _active = true;
    _timer?.cancel();
    _timer = null;
    if (_running) {
      _restartPending = true;
      return;
    }
    _restartPending = false;
    _schedule(immediate ? Duration.zero : interval, _generation);
  }

  void stop() {
    _generation++;
    _active = false;
    _restartPending = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();

  void _schedule(Duration delay, int generation) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_run(generation));
    });
  }

  Future<void> _run(int generation) async {
    if (!_active || generation != _generation || _running) return;
    _running = true;
    try {
      await task();
    } catch (error, stackTrace) {
      final errorHandler = onError;
      if (errorHandler != null) await errorHandler(error, stackTrace);
    } finally {
      _running = false;
      if (_active) {
        if (_restartPending) {
          _restartPending = false;
          _schedule(Duration.zero, _generation);
        } else if (generation == _generation) {
          _schedule(interval, generation);
        }
      }
    }
  }
}
