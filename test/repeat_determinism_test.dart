/// repeat_determinism_test.dart
///
/// Test harness for native repeat loop determinism
/// Validates timing stability across many iterations
///
/// Test Cases:
/// - Single Ayah × 100 loops
/// - Range 1-5 × 20 loops
/// - Pause interval variation
/// - Interrupt mid-loop
/// - Resume after restart

import 'dart:async';

/// Repeat loop timing metrics
class RepeatMetrics {
  final int iteration;
  final int targetIterations;
  final int loopStartTimestampNs;
  final int loopEndTimestampNs;
  final int pauseIntervalMs;
  final int actualPauseMs;

  const RepeatMetrics({
    required this.iteration,
    required this.targetIterations,
    required this.loopStartTimestampNs,
    required this.loopEndTimestampNs,
    required this.pauseIntervalMs,
    required this.actualPauseMs,
  });

  int get loopDurationNs => loopEndTimestampNs - loopStartTimestampNs;
  int get loopDurationMs => loopDurationNs ~/ 1000000;
  int get pauseDriftMs => (actualPauseMs - pauseIntervalMs).abs();

  @override
  String toString() =>
      'Iteration $iteration/$targetIterations: ${loopDurationMs}ms, '
      'pause drift: ${pauseDriftMs}ms';
}

/// Repeat test session results
class RepeatTestResults {
  final List<RepeatMetrics> iterations;
  final int totalIterations;
  final double avgLoopDurationMs;
  final double loopDurationStdDevMs;
  final double maxDriftMs;
  final double avgPauseDriftMs;
  final bool completed;
  final bool interrupted;
  final String? error;

  RepeatTestResults({
    required this.iterations,
    required this.completed,
    this.interrupted = false,
    this.error,
  })  : totalIterations = iterations.length,
        avgLoopDurationMs = iterations.isEmpty
            ? 0
            : iterations.map((i) => i.loopDurationMs).reduce((a, b) => a + b) /
                iterations.length,
        loopDurationStdDevMs = _calculateStdDev(
            iterations.map((i) => i.loopDurationMs.toDouble()).toList()),
        maxDriftMs = iterations.isEmpty
            ? 0
            : iterations
                .map((i) => i.pauseDriftMs.toDouble())
                .reduce((a, b) => a > b ? a : b),
        avgPauseDriftMs = iterations.isEmpty
            ? 0
            : iterations.map((i) => i.pauseDriftMs).reduce((a, b) => a + b) /
                iterations.length;

  static double _calculateStdDev(List<double> values) {
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return variance > 0 ? _sqrt(variance) : 0;
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  bool get passesTimingTarget => loopDurationStdDevMs < 10; // <10ms jitter
  bool get passesPauseTarget => maxDriftMs < 20; // <20ms pause accuracy

  String get summary => '''
=== Repeat Determinism Test Results ===
Total iterations: $totalIterations
Completed: $completed
Interrupted: $interrupted
Average loop duration: ${avgLoopDurationMs.toStringAsFixed(1)} ms
Std dev: ${loopDurationStdDevMs.toStringAsFixed(2)} ms
Max pause drift: ${maxDriftMs.toStringAsFixed(1)} ms
Average pause drift: ${avgPauseDriftMs.toStringAsFixed(1)} ms
Timing stability (<10ms): ${passesTimingTarget ? 'PASSED ✓' : 'FAILED ✗'}
Pause accuracy (<20ms): ${passesPauseTarget ? 'PASSED ✓' : 'FAILED ✗'}
${error != null ? 'Error: $error' : ''}
''';
}

/// Repeat determinism test harness
class RepeatDeterminismTestHarness {
  final List<RepeatMetrics> _iterations = [];
  
  int? _loopStartTimestampNs;
  int _currentIteration = 0;
  int _targetIterations = 0;
  int _pauseIntervalMs = 0;
  bool _completed = false;
  bool _interrupted = false;
  String? _error;

  /// Reset test state
  void reset() {
    _iterations.clear();
    _loopStartTimestampNs = null;
    _currentIteration = 0;
    _targetIterations = 0;
    _pauseIntervalMs = 0;
    _completed = false;
    _interrupted = false;
    _error = null;
  }

  /// Configure test parameters
  void configure({
    required int targetIterations,
    int pauseIntervalMs = 0,
  }) {
    _targetIterations = targetIterations;
    _pauseIntervalMs = pauseIntervalMs;
  }

  /// Record loop start
  void onLoopStart(int timestampNs) {
    _loopStartTimestampNs = timestampNs;
  }

  /// Record loop end / iteration
  void onLoopIteration(int iteration, int timestampNs, {int actualPauseMs = 0}) {
    if (_loopStartTimestampNs != null) {
      _iterations.add(RepeatMetrics(
        iteration: iteration,
        targetIterations: _targetIterations,
        loopStartTimestampNs: _loopStartTimestampNs!,
        loopEndTimestampNs: timestampNs,
        pauseIntervalMs: _pauseIntervalMs,
        actualPauseMs: actualPauseMs,
      ));
    }
    
    _currentIteration = iteration;
    _loopStartTimestampNs = timestampNs;
  }

  /// Record repeat completed
  void onRepeatCompleted() {
    _completed = true;
  }

  /// Record interruption
  void onInterrupted(String? reason) {
    _interrupted = true;
    _error = reason;
  }

  /// Get current results
  RepeatTestResults getResults() {
    return RepeatTestResults(
      iterations: List.from(_iterations),
      completed: _completed,
      interrupted: _interrupted,
      error: _error,
    );
  }

  /// Run single Ayah × N loops test
  Future<RepeatTestResults> runSingleAyahTest({
    required int ayahNumber,
    required int loopCount,
    required Future<void> Function() startRepeat,
    required Stream<void> onRepeatIteration,
    required Stream<void> onRepeatCompleted,
    required Duration timeout,
  }) async {
    reset();
    configure(targetIterations: loopCount);
    
    final completer = Completer<RepeatTestResults>();
    
    final iterSub = onRepeatIteration.listen((_) {
      final ts = DateTime.now().microsecondsSinceEpoch * 1000;
      onLoopIteration(_currentIteration + 1, ts);
    });
    
    final completeSub = onRepeatCompleted.listen((_) {
      this.onRepeatCompleted();
      if (!completer.isCompleted) {
        completer.complete(getResults());
      }
    });
    
    // Start repeat
    final startTs = DateTime.now().microsecondsSinceEpoch * 1000;
    onLoopStart(startTs);
    await startRepeat();
    
    return completer.future.timeout(timeout, onTimeout: () {
      iterSub.cancel();
      completeSub.cancel();
      onInterrupted('Timeout');
      return getResults();
    });
  }

  /// Run range repeat test
  Future<RepeatTestResults> runRangeRepeatTest({
    required int startAyah,
    required int endAyah,
    required int loopCount,
    required int pauseIntervalMs,
    required Future<void> Function() startRepeat,
    required Stream<void> onRepeatIteration,
    required Stream<void> onRepeatCompleted,
    required Duration timeout,
  }) async {
    reset();
    configure(
      targetIterations: loopCount * (endAyah - startAyah + 1),
      pauseIntervalMs: pauseIntervalMs,
    );
    
    final completer = Completer<RepeatTestResults>();
    int lastIterationTs = 0;
    
    final iterSub = onRepeatIteration.listen((_) {
      final ts = DateTime.now().microsecondsSinceEpoch * 1000;
      final actualPause = lastIterationTs > 0 
          ? (ts - lastIterationTs) ~/ 1000000 
          : 0;
      
      onLoopIteration(_currentIteration + 1, ts, actualPauseMs: actualPause);
      lastIterationTs = ts;
    });
    
    final completeSub = onRepeatCompleted.listen((_) {
      this.onRepeatCompleted();
      if (!completer.isCompleted) {
        completer.complete(getResults());
      }
    });
    
    // Start repeat
    final startTs = DateTime.now().microsecondsSinceEpoch * 1000;
    onLoopStart(startTs);
    lastIterationTs = startTs;
    await startRepeat();
    
    return completer.future.timeout(timeout, onTimeout: () {
      iterSub.cancel();
      completeSub.cancel();
      onInterrupted('Timeout');
      return getResults();
    });
  }

  /// Simulate interrupt and resume test
  Future<RepeatTestResults> runInterruptResumeTest({
    required int ayahNumber,
    required int loopCount,
    required int interruptAtIteration,
    required Duration interruptDuration,
    required Future<void> Function() startRepeat,
    required Future<void> Function() pauseRepeat,
    required Future<void> Function() resumeRepeat,
    required Stream<void> onRepeatIteration,
    required Stream<void> onRepeatCompleted,
    required Duration timeout,
  }) async {
    reset();
    configure(targetIterations: loopCount);
    
    final completer = Completer<RepeatTestResults>();
    bool interrupted = false;
    
    final iterSub = onRepeatIteration.listen((_) async {
      final ts = DateTime.now().microsecondsSinceEpoch * 1000;
      onLoopIteration(_currentIteration + 1, ts);
      
      // Interrupt at specified iteration
      if (_currentIteration + 1 == interruptAtIteration && !interrupted) {
        interrupted = true;
        await pauseRepeat();
        await Future<void>.delayed(interruptDuration);
        await resumeRepeat();
      }
    });
    
    final completeSub = onRepeatCompleted.listen((_) {
      this.onRepeatCompleted();
      if (!completer.isCompleted) {
        completer.complete(getResults());
      }
    });
    
    // Start repeat
    final startTs = DateTime.now().microsecondsSinceEpoch * 1000;
    onLoopStart(startTs);
    await startRepeat();
    
    return completer.future.timeout(timeout, onTimeout: () {
      iterSub.cancel();
      completeSub.cancel();
      onInterrupted('Timeout');
      return getResults();
    });
  }
}

/// Validator for repeat determinism results
class RepeatDeterminismValidator {
  /// Validate 100-loop stability
  static bool validate100Loops(RepeatTestResults results) {
    if (results.totalIterations < 100) {
      print('FAIL: Only ${results.totalIterations}/100 iterations completed');
      return false;
    }
    
    if (!results.completed) {
      print('FAIL: Test did not complete');
      return false;
    }
    
    if (!results.passesTimingTarget) {
      print('FAIL: Timing jitter ${results.loopDurationStdDevMs}ms exceeds 10ms target');
      return false;
    }
    
    print('PASS: 100-loop stability test passed');
    return true;
  }

  /// Validate pause interval accuracy
  static bool validatePauseInterval(RepeatTestResults results, int expectedPauseMs) {
    final tolerance = expectedPauseMs * 0.1; // 10% tolerance
    
    if (results.maxDriftMs > tolerance) {
      print('FAIL: Pause drift ${results.maxDriftMs}ms exceeds ${tolerance}ms tolerance');
      return false;
    }
    
    print('PASS: Pause interval accuracy test passed');
    return true;
  }

  /// Validate interrupt/resume
  static bool validateInterruptResume(RepeatTestResults results) {
    if (results.interrupted && results.error != null) {
      print('FAIL: Test had unhandled interrupt: ${results.error}');
      return false;
    }
    
    if (!results.completed) {
      print('FAIL: Test did not complete after resume');
      return false;
    }
    
    print('PASS: Interrupt/resume test passed');
    return true;
  }

  /// Print full validation report
  static void printReport(RepeatTestResults results) {
    print(results.summary);
    
    print('\n--- Iteration Details ---');
    for (final iter in results.iterations.take(10)) {
      print(iter);
    }
    if (results.iterations.length > 10) {
      print('... and ${results.iterations.length - 10} more');
    }
  }
}
