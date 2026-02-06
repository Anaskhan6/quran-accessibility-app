/// speech_service.dart
///
/// Unified Speech Service
/// Connects capture → extraction → arbitration → router pipeline

import 'dart:async';
import 'speech_capture.dart';
import 'intent_extractor.dart';
import 'confidence_arbiter.dart';
import 'voice_intent_router.dart';

// ============================================================================
// SPEECH SERVICE
// ============================================================================

/// Unified Speech Service
///
/// End-to-end voice command processing
class SpeechService {
  final SpeechCapture _capture;
  final IntentExtractor _extractor;
  final ConfidenceArbiter _arbiter;

  // Subscriptions
  StreamSubscription<SpeechResult>? _resultSubscription;

  // Streams
  final _commandExecutedController = StreamController<VoiceIntent>.broadcast();
  final _feedbackController = StreamController<String>.broadcast();

  /// Commands that were executed
  Stream<VoiceIntent> get commandExecutedStream => _commandExecutedController.stream;

  /// Feedback for accessibility (prompts, errors, confirmations)
  Stream<String> get feedbackStream => _feedbackController.stream;

  /// Whether actively listening
  bool get isListening => _capture.isListening;

  /// Whether has pending confirmation
  bool get hasPendingConfirmation => _arbiter.hasPendingConfirmation;

  SpeechService({
    required SpeechCapture capture,
    required IntentExtractor extractor,
    required ConfidenceArbiter arbiter,
  })  : _capture = capture,
        _extractor = extractor,
        _arbiter = arbiter {
    _setupPipeline();
  }

  /// Factory constructor with dependencies
  factory SpeechService.create({
    required VoiceIntentRouter router,
    SpeechCaptureConfig? captureConfig,
    ArbitrationConfig? arbitrationConfig,
  }) {
    final capture = SpeechCapture(config: captureConfig ?? const SpeechCaptureConfig());
    final extractor = IntentExtractor();
    final arbiter = ConfidenceArbiter(
      extractor: extractor,
      router: router,
      config: arbitrationConfig ?? const ArbitrationConfig(),
    );

    return SpeechService(
      capture: capture,
      extractor: extractor,
      arbiter: arbiter,
    );
  }

  void _setupPipeline() {
    // Connect capture results to arbitration
    _resultSubscription = _capture.resultStream.listen((result) {
      _processSpeech(result);
    });

    // Forward prompts to feedback stream
    _arbiter.promptStream.listen((prompt) {
      _feedbackController.add(prompt);
    });

    // Forward errors
    _arbiter.errorStream.listen((error) {
      _feedbackController.add(error);
    });

    _capture.errorStream.listen((error) {
      _feedbackController.add(error);
    });
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Start listening for voice commands
  Future<bool> startListening() async {
    final success = await _capture.startListening();
    if (success) {
      _feedbackController.add('Listening');
    }
    return success;
  }

  /// Stop listening
  Future<void> stopListening() async {
    await _capture.stopListening();
  }

  /// Cancel current command
  void cancel() {
    _capture.cancel();
    _arbiter.deny();
  }

  /// Confirm pending command
  Future<void> confirm() async {
    await _arbiter.confirm();
    _feedbackController.add('Confirmed');
  }

  /// Deny pending command
  void deny() {
    _arbiter.deny();
    _feedbackController.add('Cancelled');
  }

  /// Manual trigger (button press)
  void triggerManual() {
    _capture.triggerManualWake();
  }

  // ===========================================================================
  // PIPELINE
  // ===========================================================================

  Future<void> _processSpeech(SpeechResult result) async {
    final arbitrationResult = await _arbiter.process(result);

    if (arbitrationResult.decision == ArbitrationDecision.execute) {
      _commandExecutedController.add(arbitrationResult.intent);
    }
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> dispose() async {
    await _resultSubscription?.cancel();
    await _capture.dispose();
    await _arbiter.dispose();
    await _commandExecutedController.close();
    await _feedbackController.close();
  }
}
