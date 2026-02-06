/// confidence_arbiter.dart
///
/// Confidence Arbitration Layer
/// Routes intents based on confidence level
///
/// Thresholds:
/// - < 0.5: Confirm
/// - 0.5-0.8: Clarify if ambiguous
/// - > 0.8: Execute

import 'dart:async';
import 'voice_intent_router.dart';
import 'speech_capture.dart';
import 'intent_extractor.dart';

// ============================================================================
// ENUMS
// ============================================================================

/// Arbitration decision
enum ArbitrationDecision {
  /// High confidence - execute immediately
  execute,

  /// Medium confidence - clarify if ambiguous
  clarify,

  /// Low confidence - confirm with user
  confirm,

  /// Too low - reject
  reject,
}

// ============================================================================
// MODELS
// ============================================================================

/// Arbitration result
class ArbitrationResult {
  final ArbitrationDecision decision;
  final VoiceIntent intent;
  final double confidence;
  final String? clarificationPrompt;
  final List<VoiceIntent>? alternatives;

  const ArbitrationResult({
    required this.decision,
    required this.intent,
    required this.confidence,
    this.clarificationPrompt,
    this.alternatives,
  });
}

/// Confirmation request
class ConfirmationRequest {
  final VoiceIntent intent;
  final String prompt;
  final DateTime requestedAt;
  Timer? timeoutTimer;

  ConfirmationRequest({
    required this.intent,
    required this.prompt,
  }) : requestedAt = DateTime.now();

  Duration get age => DateTime.now().difference(requestedAt);
}

// ============================================================================
// CONFIGURATION
// ============================================================================

class ArbitrationConfig {
  /// Threshold for immediate execution
  final double executeThreshold;

  /// Threshold for clarification
  final double clarifyThreshold;

  /// Threshold for confirmation
  final double confirmThreshold;

  /// Timeout for pending confirmations
  final Duration confirmationTimeout;

  const ArbitrationConfig({
    this.executeThreshold = 0.8,
    this.clarifyThreshold = 0.5,
    this.confirmThreshold = 0.3,
    this.confirmationTimeout = const Duration(seconds: 10),
  });
}

// ============================================================================
// CONFIDENCE ARBITER
// ============================================================================

class ConfidenceArbiter {
  final IntentExtractor _extractor;
  final VoiceIntentRouter _router;
  final ArbitrationConfig config;

  ConfirmationRequest? _pendingConfirmation;

  final _resultController = StreamController<ArbitrationResult>.broadcast();
  final _promptController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Arbitration results
  Stream<ArbitrationResult> get resultStream => _resultController.stream;

  /// Prompts for user (confirm/clarify)
  Stream<String> get promptStream => _promptController.stream;

  /// Errors
  Stream<String> get errorStream => _errorController.stream;

  /// Whether has pending confirmation
  bool get hasPendingConfirmation => _pendingConfirmation != null;

  ConfidenceArbiter({
    required IntentExtractor extractor,
    required VoiceIntentRouter router,
    this.config = const ArbitrationConfig(),
  })  : _extractor = extractor,
        _router = router;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Process speech result through full pipeline
  Future<ArbitrationResult> process(SpeechResult speech) async {
    // Cancel any pending confirmation
    _cancelPendingConfirmation();

    // Extract intent
    final intent = _extractor.extract(speech);

    // Determine arbitration decision
    final decision = _determineDecision(intent);
    final result = _createResult(decision, intent);

    _resultController.add(result);

    // Handle based on decision
    switch (decision) {
      case ArbitrationDecision.execute:
        await _executeIntent(intent);
        break;

      case ArbitrationDecision.clarify:
        _requestClarification(intent, result.clarificationPrompt!);
        break;

      case ArbitrationDecision.confirm:
        _requestConfirmation(intent, result.clarificationPrompt!);
        break;

      case ArbitrationDecision.reject:
        _errorController.add('Could not understand command');
        break;
    }

    return result;
  }

  /// User confirms pending intent
  Future<void> confirm() async {
    if (_pendingConfirmation == null) return;

    final intent = _pendingConfirmation!.intent;
    _cancelPendingConfirmation();

    await _executeIntent(intent);
  }

  /// User denies pending intent
  void deny() {
    _cancelPendingConfirmation();
    _errorController.add('Command cancelled');
  }

  /// User provides clarification speech
  Future<ArbitrationResult> clarify(SpeechResult speech) async {
    // Re-process with context from previous intent
    return process(speech);
  }

  // ===========================================================================
  // DECISION LOGIC
  // ===========================================================================

  ArbitrationDecision _determineDecision(VoiceIntent intent) {
    // Unknown intent is always rejected
    if (intent.type == VoiceIntentType.unknown) {
      return ArbitrationDecision.reject;
    }

    final confidence = intent.confidence;

    if (confidence >= config.executeThreshold) {
      return ArbitrationDecision.execute;
    }

    if (confidence >= config.clarifyThreshold) {
      // Check if ambiguous
      if (_isAmbiguous(intent)) {
        return ArbitrationDecision.clarify;
      }
      return ArbitrationDecision.execute;
    }

    if (confidence >= config.confirmThreshold) {
      return ArbitrationDecision.confirm;
    }

    return ArbitrationDecision.reject;
  }

  bool _isAmbiguous(VoiceIntent intent) {
    // Ambiguous cases:
    // - "Repeat" without count
    // - "Play" without Surah
    // - Seek without target
    switch (intent.type) {
      case VoiceIntentType.play:
        return intent.surahId == null;

      case VoiceIntentType.seekToAyah:
        return intent.ayahNumber == null;

      case VoiceIntentType.seekToSurah:
        return intent.surahId == null;

      case VoiceIntentType.repeatRange:
        return intent.endAyahNumber == null;

      default:
        return false;
    }
  }

  ArbitrationResult _createResult(ArbitrationDecision decision, VoiceIntent intent) {
    String? prompt;

    switch (decision) {
      case ArbitrationDecision.confirm:
        prompt = _buildConfirmPrompt(intent);
        break;

      case ArbitrationDecision.clarify:
        prompt = _buildClarifyPrompt(intent);
        break;

      default:
        break;
    }

    return ArbitrationResult(
      decision: decision,
      intent: intent,
      confidence: intent.confidence,
      clarificationPrompt: prompt,
    );
  }

  String _buildConfirmPrompt(VoiceIntent intent) {
    switch (intent.type) {
      case VoiceIntentType.play:
        final surahId = intent.surahId;
        return surahId != null
            ? 'Play Surah $surahId?'
            : 'Did you mean to play?';

      case VoiceIntentType.repeatCurrent:
      case VoiceIntentType.repeatAyah:
        final count = intent.repeatCount ?? 3;
        return 'Repeat $count times?';

      case VoiceIntentType.seekToAyah:
        return 'Go to Ayah ${intent.ayahNumber}?';

      default:
        return 'Did you mean ${intent.type.name}?';
    }
  }

  String _buildClarifyPrompt(VoiceIntent intent) {
    switch (intent.type) {
      case VoiceIntentType.play:
        return 'Which Surah?';

      case VoiceIntentType.seekToAyah:
        return 'Which Ayah?';

      case VoiceIntentType.repeatRange:
        return 'From which Ayah to which?';

      default:
        return 'Please repeat the command';
    }
  }

  // ===========================================================================
  // EXECUTION
  // ===========================================================================

  Future<void> _executeIntent(VoiceIntent intent) async {
    await _router.route(intent);
  }

  // ===========================================================================
  // CONFIRMATION/CLARIFICATION
  // ===========================================================================

  void _requestConfirmation(VoiceIntent intent, String prompt) {
    _pendingConfirmation = ConfirmationRequest(
      intent: intent,
      prompt: prompt,
    );

    _pendingConfirmation!.timeoutTimer = Timer(
      config.confirmationTimeout,
      _onConfirmationTimeout,
    );

    _promptController.add(prompt);
  }

  void _requestClarification(VoiceIntent intent, String prompt) {
    // Clarification uses same mechanism but different prompt style
    _pendingConfirmation = ConfirmationRequest(
      intent: intent,
      prompt: prompt,
    );

    _pendingConfirmation!.timeoutTimer = Timer(
      config.confirmationTimeout,
      _onConfirmationTimeout,
    );

    _promptController.add(prompt);
  }

  void _onConfirmationTimeout() {
    if (_pendingConfirmation != null) {
      _errorController.add('Confirmation timed out');
      _pendingConfirmation = null;
    }
  }

  void _cancelPendingConfirmation() {
    _pendingConfirmation?.timeoutTimer?.cancel();
    _pendingConfirmation = null;
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> dispose() async {
    _cancelPendingConfirmation();
    await _resultController.close();
    await _promptController.close();
    await _errorController.close();
  }
}
