/// speech_capture.dart
///
/// Speech Capture Layer
/// Handles microphone focus, wake word, and session lifecycle
///
/// Does NOT parse commands - only captures raw speech

import 'dart:async';

// ============================================================================
// ENUMS
// ============================================================================

/// Speech session state
enum SpeechSessionState {
  /// Ready to listen
  idle,

  /// Waiting for wake word
  waitingForWakeWord,

  /// Actively listening for command
  listening,

  /// Processing speech
  processing,

  /// Session complete
  done,

  /// Error occurred
  error,
}

/// Wake word mode
enum WakeWordMode {
  /// No wake word required
  disabled,

  /// Require "Ya Quran" or similar
  enabled,

  /// Wake word optional (button or voice)
  optional,
}

// ============================================================================
// MODELS
// ============================================================================

/// Raw speech result from STT engine
class SpeechResult {
  final String text;
  final double confidence;
  final bool isFinal;
  final Duration speechDuration;
  final DateTime timestamp;

  const SpeechResult({
    required this.text,
    required this.confidence,
    required this.isFinal,
    required this.speechDuration,
    required this.timestamp,
  });

  @override
  String toString() => 'SpeechResult("$text", confidence=$confidence, final=$isFinal)';
}

/// Partial transcript for buffering
class PartialTranscript {
  final String text;
  final double confidence;
  final DateTime timestamp;

  const PartialTranscript({
    required this.text,
    required this.confidence,
    required this.timestamp,
  });
}

/// Speech session for tracking lifecycle
class SpeechSession {
  final String id;
  final DateTime startedAt;
  final List<PartialTranscript> partials;
  SpeechResult? finalResult;
  SpeechSessionState state;
  String? errorMessage;

  SpeechSession({required this.id})
      : startedAt = DateTime.now(),
        partials = [],
        state = SpeechSessionState.idle;

  Duration get duration => DateTime.now().difference(startedAt);

  void addPartial(PartialTranscript partial) {
    partials.add(partial);
  }

  void complete(SpeechResult result) {
    finalResult = result;
    state = SpeechSessionState.done;
  }

  void fail(String message) {
    errorMessage = message;
    state = SpeechSessionState.error;
  }
}

// ============================================================================
// CONFIGURATION
// ============================================================================

/// Speech capture configuration
class SpeechCaptureConfig {
  /// Wake word mode
  final WakeWordMode wakeWordMode;

  /// Wake word phrases
  final List<String> wakeWords;

  /// Maximum listening duration
  final Duration maxListenDuration;

  /// Silence timeout (end session)
  final Duration silenceTimeout;

  /// Minimum confidence threshold
  final double minConfidence;

  /// Enable partial results
  final bool partialResults;

  const SpeechCaptureConfig({
    this.wakeWordMode = WakeWordMode.disabled,
    this.wakeWords = const ['ya quran', 'hey quran', 'quran'],
    this.maxListenDuration = const Duration(seconds: 10),
    this.silenceTimeout = const Duration(seconds: 3),
    this.minConfidence = 0.3,
    this.partialResults = true,
  });
}

// ============================================================================
// SPEECH CAPTURE
// ============================================================================

/// Speech Capture Layer
///
/// Manages microphone and STT lifecycle without command parsing
class SpeechCapture {
  final SpeechCaptureConfig config;

  // State
  SpeechSessionState _state = SpeechSessionState.idle;
  SpeechSession? _currentSession;
  bool _hasMicrophoneFocus = false;
  Timer? _silenceTimer;
  Timer? _maxDurationTimer;

  // Stream controllers
  final _stateController = StreamController<SpeechSessionState>.broadcast();
  final _partialController = StreamController<PartialTranscript>.broadcast();
  final _resultController = StreamController<SpeechResult>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Session state stream
  Stream<SpeechSessionState> get stateStream => _stateController.stream;

  /// Partial transcripts (for live feedback)
  Stream<PartialTranscript> get partialStream => _partialController.stream;

  /// Final speech results
  Stream<SpeechResult> get resultStream => _resultController.stream;

  /// Error stream
  Stream<String> get errorStream => _errorController.stream;

  /// Current state
  SpeechSessionState get state => _state;

  /// Whether actively listening
  bool get isListening => _state == SpeechSessionState.listening;

  /// Whether has microphone focus
  bool get hasMicrophoneFocus => _hasMicrophoneFocus;

  SpeechCapture({this.config = const SpeechCaptureConfig()});

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Start listening for speech
  Future<bool> startListening() async {
    if (_state == SpeechSessionState.listening) {
      return true; // Already listening
    }

    // Request microphone focus
    final focusGranted = await _requestMicrophoneFocus();
    if (!focusGranted) {
      _emitError('Microphone focus denied');
      return false;
    }

    // Check wake word mode
    if (config.wakeWordMode == WakeWordMode.enabled) {
      _setState(SpeechSessionState.waitingForWakeWord);
      _startWakeWordDetection();
    } else {
      _startSpeechSession();
    }

    return true;
  }

  /// Stop listening
  Future<void> stopListening() async {
    _cancelTimers();

    if (_currentSession != null &&
        _currentSession!.state == SpeechSessionState.listening) {
      _currentSession!.state = SpeechSessionState.done;
    }

    _setState(SpeechSessionState.idle);
    await _releaseMicrophoneFocus();
  }

  /// Cancel current session
  void cancel() {
    _cancelTimers();
    _currentSession?.fail('Cancelled');
    _setState(SpeechSessionState.idle);
  }

  /// Manually trigger wake word (button press)
  void triggerManualWake() {
    if (config.wakeWordMode == WakeWordMode.optional &&
        _state == SpeechSessionState.waitingForWakeWord) {
      _onWakeWordDetected();
    } else if (_state == SpeechSessionState.idle) {
      startListening();
    }
  }

  // ===========================================================================
  // MICROPHONE FOCUS
  // ===========================================================================

  Future<bool> _requestMicrophoneFocus() async {
    // Platform-specific microphone permission and focus
    // For now, simulate success
    _hasMicrophoneFocus = true;
    return true;
  }

  Future<void> _releaseMicrophoneFocus() async {
    _hasMicrophoneFocus = false;
  }

  // ===========================================================================
  // WAKE WORD
  // ===========================================================================

  void _startWakeWordDetection() {
    // In real implementation, would use wake word detection library
    // For now, this is a placeholder
    _setState(SpeechSessionState.waitingForWakeWord);
  }

  void _onWakeWordDetected() {
    _startSpeechSession();
  }

  /// Check if text contains wake word
  bool _containsWakeWord(String text) {
    final lower = text.toLowerCase();
    for (final wake in config.wakeWords) {
      if (lower.contains(wake)) {
        return true;
      }
    }
    return false;
  }

  // ===========================================================================
  // SPEECH SESSION
  // ===========================================================================

  void _startSpeechSession() {
    _currentSession = SpeechSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    _currentSession!.state = SpeechSessionState.listening;

    _setState(SpeechSessionState.listening);

    // Start timers
    _startSilenceTimer();
    _startMaxDurationTimer();

    // In real implementation, would start STT engine here
  }

  /// Handle partial result from STT
  void onPartialResult(String text, double confidence) {
    if (_state != SpeechSessionState.listening) return;

    // Check for wake word if in that mode
    if (config.wakeWordMode == WakeWordMode.enabled &&
        _state == SpeechSessionState.waitingForWakeWord) {
      if (_containsWakeWord(text)) {
        _onWakeWordDetected();
      }
      return;
    }

    // Reset silence timer
    _resetSilenceTimer();

    final partial = PartialTranscript(
      text: text,
      confidence: confidence,
      timestamp: DateTime.now(),
    );

    _currentSession?.addPartial(partial);
    _partialController.add(partial);
  }

  /// Handle final result from STT
  void onFinalResult(String text, double confidence, Duration duration) {
    if (_state != SpeechSessionState.listening) return;

    _cancelTimers();
    _setState(SpeechSessionState.processing);

    final result = SpeechResult(
      text: text,
      confidence: confidence,
      isFinal: true,
      speechDuration: duration,
      timestamp: DateTime.now(),
    );

    _currentSession?.complete(result);
    _resultController.add(result);

    _setState(SpeechSessionState.done);
    _releaseMicrophoneFocus();
  }

  /// Handle STT error
  void onError(String message) {
    _cancelTimers();
    _currentSession?.fail(message);
    _emitError(message);
    _setState(SpeechSessionState.error);
    _releaseMicrophoneFocus();
  }

  // ===========================================================================
  // TIMERS
  // ===========================================================================

  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(config.silenceTimeout, () {
      // Silence timeout - end session
      if (_currentSession != null && _currentSession!.partials.isNotEmpty) {
        // Use last partial as final
        final lastPartial = _currentSession!.partials.last;
        onFinalResult(lastPartial.text, lastPartial.confidence, _currentSession!.duration);
      } else {
        onError('No speech detected');
      }
    });
  }

  void _resetSilenceTimer() {
    _startSilenceTimer();
  }

  void _startMaxDurationTimer() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = Timer(config.maxListenDuration, () {
      // Max duration reached
      if (_currentSession != null && _currentSession!.partials.isNotEmpty) {
        final lastPartial = _currentSession!.partials.last;
        onFinalResult(lastPartial.text, lastPartial.confidence, _currentSession!.duration);
      } else {
        stopListening();
      }
    });
  }

  void _cancelTimers() {
    _silenceTimer?.cancel();
    _maxDurationTimer?.cancel();
  }

  // ===========================================================================
  // STATE MANAGEMENT
  // ===========================================================================

  void _setState(SpeechSessionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _emitError(String message) {
    _errorController.add(message);
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> dispose() async {
    _cancelTimers();
    await stopListening();
    await _stateController.close();
    await _partialController.close();
    await _resultController.close();
    await _errorController.close();
  }
}
