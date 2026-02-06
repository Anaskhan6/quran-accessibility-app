/// gapless_transition_test.dart
///
/// Test harness for measuring gapless Ayah transitions
/// Target: <5ms silence gap, no audible artifacts
///
/// Metrics captured:
/// - Transition latency (time between ayah end and next start)
/// - Silence gap duration
/// - Sample discontinuity detection

import 'dart:async';
import 'dart:math';

/// Transition timing metrics
class TransitionMetrics {
  final int ayahFrom;
  final int ayahTo;
  final int transitionLatencyUs;
  final int silenceGapUs;
  final bool hasArtifact;
  final DateTime timestamp;

  const TransitionMetrics({
    required this.ayahFrom,
    required this.ayahTo,
    required this.transitionLatencyUs,
    required this.silenceGapUs,
    required this.hasArtifact,
    required this.timestamp,
  });

  bool get passesTarget => silenceGapUs < 5000; // <5ms target

  @override
  String toString() => 
    'Transition $ayahFrom→$ayahTo: latency=${transitionLatencyUs}µs, '
    'gap=${silenceGapUs}µs, artifact=$hasArtifact';
}

/// Test session results
class TransitionTestResults {
  final List<TransitionMetrics> transitions;
  final int totalTransitions;
  final double avgTransitionLatencyUs;
  final double avgSilenceGapUs;
  final int maxSilenceGapUs;
  final int artifactCount;
  final bool allPassedTarget;

  TransitionTestResults({
    required this.transitions,
  })  : totalTransitions = transitions.length,
        avgTransitionLatencyUs = transitions.isEmpty 
            ? 0 
            : transitions.map((t) => t.transitionLatencyUs).reduce((a, b) => a + b) / transitions.length,
        avgSilenceGapUs = transitions.isEmpty 
            ? 0 
            : transitions.map((t) => t.silenceGapUs).reduce((a, b) => a + b) / transitions.length,
        maxSilenceGapUs = transitions.isEmpty 
            ? 0 
            : transitions.map((t) => t.silenceGapUs).reduce(max),
        artifactCount = transitions.where((t) => t.hasArtifact).length,
        allPassedTarget = transitions.every((t) => t.passesTarget);

  String get summary => '''
=== Gapless Transition Test Results ===
Total transitions: $totalTransitions
Average latency: ${avgTransitionLatencyUs.toStringAsFixed(1)} µs
Average gap: ${avgSilenceGapUs.toStringAsFixed(1)} µs
Max gap: $maxSilenceGapUs µs
Artifacts detected: $artifactCount
Target (<5ms): ${allPassedTarget ? 'PASSED ✓' : 'FAILED ✗'}
''';
}

/// Gapless transition test harness
class GaplessTransitionTestHarness {
  final List<TransitionMetrics> _transitions = [];
  
  // Timing state
  int? _lastAyahEndTimestampNs;
  int? _currentAyahStartTimestampNs;
  int _currentAyah = 0;
  
  // Audio buffer analysis (simulated - real impl would use PCM data)
  bool _artifactDetected = false;

  /// Reset test state
  void reset() {
    _transitions.clear();
    _lastAyahEndTimestampNs = null;
    _currentAyahStartTimestampNs = null;
    _currentAyah = 0;
    _artifactDetected = false;
  }

  /// Record Ayah end event
  void onAyahEnded(int ayahNumber, int timestampNs) {
    _lastAyahEndTimestampNs = timestampNs;
  }

  /// Record Ayah start event
  void onAyahStarted(int ayahNumber, int timestampNs) {
    _currentAyahStartTimestampNs = timestampNs;
    
    if (_lastAyahEndTimestampNs != null && _currentAyah > 0) {
      final transitionNs = timestampNs - _lastAyahEndTimestampNs!;
      final transitionUs = transitionNs ~/ 1000;
      
      // Estimate silence gap (simplified - real impl uses PCM analysis)
      final silenceGapUs = _estimateSilenceGap(transitionUs);
      
      _transitions.add(TransitionMetrics(
        ayahFrom: _currentAyah,
        ayahTo: ayahNumber,
        transitionLatencyUs: transitionUs,
        silenceGapUs: silenceGapUs,
        hasArtifact: _artifactDetected,
        timestamp: DateTime.now(),
      ));
      
      _artifactDetected = false;
    }
    
    _currentAyah = ayahNumber;
  }

  /// Estimate silence gap from transition latency
  /// Real implementation would analyze PCM buffers
  int _estimateSilenceGap(int transitionUs) {
    // Simplified model: silence gap ≈ transition latency minus decode time
    // Real implementation would measure actual zero samples
    const decodeOverheadUs = 1000; // ~1ms decode overhead
    return max(0, transitionUs - decodeOverheadUs);
  }

  /// Report artifact detected during playback
  void reportArtifact() {
    _artifactDetected = true;
  }

  /// Get current test results
  TransitionTestResults getResults() {
    return TransitionTestResults(transitions: List.from(_transitions));
  }

  /// Run automated transition test
  Future<TransitionTestResults> runTest({
    required int startAyah,
    required int endAyah,
    required Future<void> Function(int ayah) playAyah,
    required Stream<void> onAyahEnded,
    required Duration timeout,
  }) async {
    reset();
    
    final completer = Completer<TransitionTestResults>();
    int current = startAyah;
    
    // Listen for Ayah end events
    final subscription = onAyahEnded.listen((_) {
      final endTimestamp = DateTime.now().microsecondsSinceEpoch * 1000;
      onAyahEnded(current, endTimestamp);
      
      if (current < endAyah) {
        current++;
        final startTimestamp = DateTime.now().microsecondsSinceEpoch * 1000;
        onAyahStarted(current, startTimestamp);
        playAyah(current);
      } else {
        if (!completer.isCompleted) {
          completer.complete(getResults());
        }
      }
    });
    
    // Start first Ayah
    final startTimestamp = DateTime.now().microsecondsSinceEpoch * 1000;
    onAyahStarted(startAyah, startTimestamp);
    await playAyah(startAyah);
    
    // Wait for completion or timeout
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        subscription.cancel();
        return getResults();
      },
    );
  }
}

/// PCM buffer analyzer for artifact detection
/// (Placeholder - real implementation would analyze actual audio samples)
class PCMBufferAnalyzer {
  /// Detect click artifacts in PCM buffer
  static bool hasClickArtifact(List<int> samples, {int threshold = 1000}) {
    if (samples.length < 2) return false;
    
    for (int i = 1; i < samples.length; i++) {
      final diff = (samples[i] - samples[i - 1]).abs();
      if (diff > threshold) {
        return true;
      }
    }
    return false;
  }

  /// Measure silence duration in samples
  static int measureSilence(List<int> samples, {int silenceThreshold = 50}) {
    int silentSamples = 0;
    bool inSilence = false;
    
    for (final sample in samples) {
      if (sample.abs() <= silenceThreshold) {
        if (!inSilence) {
          inSilence = true;
        }
        silentSamples++;
      } else if (inSilence) {
        break;
      }
    }
    
    return silentSamples;
  }

  /// Convert samples to duration in microseconds
  static int samplesToMicroseconds(int samples, int sampleRate) {
    return (samples * 1000000) ~/ sampleRate;
  }
}

/// Transition timing validator
class TransitionValidator {
  /// Validate transition meets target
  static bool validate(TransitionMetrics metrics) {
    // Target: <5ms silence gap
    if (metrics.silenceGapUs >= 5000) {
      print('FAIL: Silence gap ${metrics.silenceGapUs}µs exceeds 5000µs target');
      return false;
    }
    
    // No audible artifacts
    if (metrics.hasArtifact) {
      print('FAIL: Audible artifact detected');
      return false;
    }
    
    return true;
  }

  /// Validate entire test run
  static bool validateAll(TransitionTestResults results) {
    print(results.summary);
    
    if (!results.allPassedTarget) {
      print('FAIL: Not all transitions met the <5ms target');
      return false;
    }
    
    if (results.artifactCount > 0) {
      print('FAIL: ${results.artifactCount} artifacts detected');
      return false;
    }
    
    print('PASS: All transitions meet gapless requirements');
    return true;
  }
}
