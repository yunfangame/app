import 'dart:async';

typedef RuntimeSample = Future<void> Function(bool Function() isCurrent);

class RuntimeSampler {
  RuntimeSampler({
    required RuntimeSample sample,
    this.interval = const Duration(seconds: 1),
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _sample = sample,
       _onError = onError;

  final RuntimeSample _sample;
  final Duration interval;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  Timer? _timer;
  bool _running = false;
  bool _foreground = true;
  bool _closed = false;
  bool _inFlight = false;
  bool _requested = false;
  int _revision = 0;

  bool get _canSample => !_closed && _running && _foreground;

  void setRunning(bool running) {
    if (_closed || _running == running) return;
    _running = running;
    _reset();
  }

  void setForeground(bool foreground) {
    if (_closed || _foreground == foreground) return;
    _foreground = foreground;
    _reset();
  }

  void _reset() {
    _revision++;
    _timer?.cancel();
    _timer = null;
    _requested = _canSample;
    if (_requested) unawaited(_run());
  }

  Future<void> _run() async {
    if (!_canSample) return;
    if (_inFlight) {
      _requested = true;
      return;
    }
    _inFlight = true;
    _requested = false;
    final revision = _revision;
    bool isCurrent() => _canSample && _revision == revision;
    try {
      await _sample(isCurrent);
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    } finally {
      _inFlight = false;
      if (_canSample) {
        if (_requested) {
          unawaited(_run());
        } else {
          _timer = Timer(interval, () {
            _timer = null;
            unawaited(_run());
          });
        }
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _reset();
  }
}
