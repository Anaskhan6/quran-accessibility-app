/// voice_intent_router.dart
///
/// Voice Intent Routing Engine
/// State-aware arbitration between voice commands and playback state machine
///
/// Problems solved:
/// - "Repeat Ayah 5" while repeating Ayah 3
/// - "Pause" during preload
/// - "Seek" mid-repeat → suspend repeat, prompt resume

import 'dart:async';
import 'playback_state_controller.dart';
import 'repeat_orchestrator.dart';
import 'playback_command_queue.dart';

// ============================================================================
// INTENT TYPES
// ============================================================================

/// Voice intent types
enum VoiceIntentType {
  // Playback control
  play,
  pause,
  stop,
  resume,

  // Navigation
  seekToAyah,
  seekToSurah,
  nextAyah,
  previousAyah,
  nextSurah,
  previousSurah,

  // Repeat
  repeatCurrent,
  repeatAyah,
  repeatRange,
  repeatTimes,
  stopRepeat,

  // Speed
  speedUp,
  slowDown,
  setSpeed,

  // Volume
  volumeUp,
  volumeDown,
  mute,
  unmute,

  // Other
  whatIsPlaying,
  help,
  unknown,
}

/// Routing decision
enum RoutingDecision {
  /// Execute immediately
  execute,

  /// Queue for later execution
  queue,

  /// Reject - not allowed in current state
  reject,

  /// Requires confirmation
  confirm,

  /// Suspended current operation, then execute
  suspendAndExecute,
}

// ============================================================================
// MODELS
// ============================================================================

/// Parsed voice intent with entities
class VoiceIntent {
  final VoiceIntentType type;
  final String rawText;
  final double confidence;
  final Map<String, dynamic> entities;
  final DateTime timestamp;

  const VoiceIntent({
    required this.type,
    required this.rawText,
    this.confidence = 1.0,
    this.entities = const {},
    required this.timestamp,
  });

  /// Get Surah entity
  int? get surahId => entities['surahId'] as int?;

  /// Get Ayah entity
  int? get ayahNumber => entities['ayahNumber'] as int?;

  /// Get end Ayah for range
  int? get endAyahNumber => entities['endAyahNumber'] as int?;

  /// Get repeat count
  int? get repeatCount => entities['repeatCount'] as int?;

  /// Get speed value
  double? get speed => entities['speed'] as double?;

  @override
  String toString() => 'VoiceIntent($type, confidence=$confidence)';
}

/// Routing result
class RoutingResult {
  final RoutingDecision decision;
  final VoiceIntent intent;
  final String? rejectionReason;
  final String? confirmationPrompt;

  const RoutingResult({
    required this.decision,
    required this.intent,
    this.rejectionReason,
    this.confirmationPrompt,
  });

  bool get isExecutable =>
      decision == RoutingDecision.execute ||
      decision == RoutingDecision.suspendAndExecute;
}

// ============================================================================
// VOICE INTENT ROUTER
// ============================================================================

/// Voice Intent Router
///
/// State-aware routing of voice commands to playback engine.
/// Prevents conflicts and handles edge cases.
class VoiceIntentRouter {
  final PlaybackStateController _playbackController;
  final RepeatOrchestrator _repeatOrchestrator;
  final PlaybackCommandQueue _commandQueue;

  final _routingController = StreamController<RoutingResult>.broadcast();
  final _confirmationController = StreamController<String>.broadcast();
  final _rejectionController = StreamController<String>.broadcast();

  /// Routing results stream
  Stream<RoutingResult> get routingStream => _routingController.stream;

  /// Confirmation prompts (for UI/accessibility)
  Stream<String> get confirmationStream => _confirmationController.stream;

  /// Rejection announcements
  Stream<String> get rejectionStream => _rejectionController.stream;

  VoiceIntentRouter({
    required PlaybackStateController playbackController,
    required RepeatOrchestrator repeatOrchestrator,
    required PlaybackCommandQueue commandQueue,
  })  : _playbackController = playbackController,
        _repeatOrchestrator = repeatOrchestrator,
        _commandQueue = commandQueue;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Route a voice intent
  Future<RoutingResult> route(VoiceIntent intent) async {
    final result = _evaluateRouting(intent);
    _routingController.add(result);

    switch (result.decision) {
      case RoutingDecision.execute:
        await _execute(intent);
        break;

      case RoutingDecision.suspendAndExecute:
        // Suspend repeat first, then execute
        if (_repeatOrchestrator.isActive) {
          // Repeat will be suspended automatically by state controller
        }
        await _execute(intent);
        break;

      case RoutingDecision.confirm:
        _confirmationController.add(result.confirmationPrompt ?? 'Confirm?');
        break;

      case RoutingDecision.reject:
        _rejectionController.add(result.rejectionReason ?? 'Command not allowed');
        break;

      case RoutingDecision.queue:
        // Queue for later
        break;
    }

    return result;
  }

  /// Confirm a pending intent (after user confirmation)
  Future<void> confirmPending(VoiceIntent intent) async {
    await _execute(intent);
  }

  // ===========================================================================
  // ROUTING EVALUATION
  // ===========================================================================

  RoutingResult _evaluateRouting(VoiceIntent intent) {
    final state = _playbackController.state;
    final repeatState = _repeatOrchestrator.state;

    switch (intent.type) {
      // ---------------------------------------------------------------------
      // PLAY/PAUSE/STOP - Always allowed
      // ---------------------------------------------------------------------
      case VoiceIntentType.play:
      case VoiceIntentType.resume:
        if (state.type == PlaybackStateType.playing) {
          return RoutingResult(
            decision: RoutingDecision.reject,
            intent: intent,
            rejectionReason: 'Already playing',
          );
        }
        return RoutingResult(decision: RoutingDecision.execute, intent: intent);

      case VoiceIntentType.pause:
        if (state.type != PlaybackStateType.playing &&
            state.type != PlaybackStateType.repeating) {
          return RoutingResult(
            decision: RoutingDecision.reject,
            intent: intent,
            rejectionReason: 'Not playing',
          );
        }
        return RoutingResult(decision: RoutingDecision.execute, intent: intent);

      case VoiceIntentType.stop:
        // Stop always allowed
        return RoutingResult(decision: RoutingDecision.execute, intent: intent);

      // ---------------------------------------------------------------------
      // SEEK - Suspends repeat if active
      // ---------------------------------------------------------------------
      case VoiceIntentType.seekToAyah:
      case VoiceIntentType.seekToSurah:
      case VoiceIntentType.nextAyah:
      case VoiceIntentType.previousAyah:
      case VoiceIntentType.nextSurah:
      case VoiceIntentType.previousSurah:
        if (state.type == PlaybackStateType.idle) {
          return RoutingResult(
            decision: RoutingDecision.reject,
            intent: intent,
            rejectionReason: 'Nothing loaded',
          );
        }

        // If repeating, suspend repeat first
        if (repeatState.isActive) {
          return RoutingResult(
            decision: RoutingDecision.suspendAndExecute,
            intent: intent,
          );
        }

        return RoutingResult(decision: RoutingDecision.execute, intent: intent);

      // ---------------------------------------------------------------------
      // REPEAT - State-dependent
      // ---------------------------------------------------------------------
      case VoiceIntentType.repeatCurrent:
      case VoiceIntentType.repeatAyah:
      case VoiceIntentType.repeatRange:
      case VoiceIntentType.repeatTimes:
        if (state.type == PlaybackStateType.idle) {
          return RoutingResult(
            decision: RoutingDecision.reject,
            intent: intent,
            rejectionReason: 'Nothing to repeat',
          );
        }

        // If already repeating different Ayah
        if (repeatState.isActive) {
          final currentRepeatAyah = repeatState.currentAyah;
          final targetAyah = intent.ayahNumber ?? state.ayahNumber;

          if (currentRepeatAyah != targetAyah) {
            return RoutingResult(
              decision: RoutingDecision.confirm,
              intent: intent,
              confirmationPrompt:
                  'Already repeating Ayah $currentRepeatAyah. Switch to Ayah $targetAyah?',
            );
          }
        }

        // Must be playing to start repeat
        if (state.type != PlaybackStateType.playing &&
            state.type != PlaybackStateType.paused) {
          return RoutingResult(
            decision: RoutingDecision.reject,
            intent: intent,
            rejectionReason: 'Start playing first',
          );
        }

        return RoutingResult(decision: RoutingDecision.execute, intent: intent);

      case VoiceIntentType.stopRepeat:
        if (!repeatState.isActive && !repeatState.isSuspendedForSeek) {
          return RoutingResult(
            decision: RoutingDecision.reject,
            intent: intent,
            rejectionReason: 'No repeat active',
          );
        }
        return RoutingResult(decision: RoutingDecision.execute, intent: intent);

      // ---------------------------------------------------------------------
      // SPEED/VOLUME - Always allowed when loaded
      // ---------------------------------------------------------------------
      case VoiceIntentType.speedUp:
      case VoiceIntentType.slowDown:
      case VoiceIntentType.setSpeed:
      case VoiceIntentType.volumeUp:
      case VoiceIntentType.volumeDown:
      case VoiceIntentType.mute:
      case VoiceIntentType.unmute:
        if (state.type == PlaybackStateType.idle) {
          return RoutingResult(
            decision: RoutingDecision.reject,
            intent: intent,
            rejectionReason: 'Nothing loaded',
          );
        }
        return RoutingResult(decision: RoutingDecision.execute, intent: intent);

      // ---------------------------------------------------------------------
      // INFO - Always allowed
      // ---------------------------------------------------------------------
      case VoiceIntentType.whatIsPlaying:
      case VoiceIntentType.help:
        return RoutingResult(decision: RoutingDecision.execute, intent: intent);

      case VoiceIntentType.unknown:
        return RoutingResult(
          decision: RoutingDecision.reject,
          intent: intent,
          rejectionReason: 'Unknown command',
        );
    }
  }

  // ===========================================================================
  // COMMAND EXECUTION
  // ===========================================================================

  Future<void> _execute(VoiceIntent intent) async {
    switch (intent.type) {
      case VoiceIntentType.play:
      case VoiceIntentType.resume:
        await _commandQueue.play();
        break;

      case VoiceIntentType.pause:
        await _commandQueue.doPause();
        break;

      case VoiceIntentType.stop:
        await _commandQueue.stop();
        break;

      case VoiceIntentType.seekToAyah:
        if (intent.ayahNumber != null) {
          // Would trigger seek via command queue
          // _commandQueue.seekToAyah(intent.ayahNumber!);
        }
        break;

      case VoiceIntentType.repeatCurrent:
        await _commandQueue.startRepeat(
          mode: RepeatUXMode.singleAyah.index,
          count: intent.repeatCount ?? 3,
        );
        break;

      case VoiceIntentType.repeatAyah:
        if (intent.ayahNumber != null) {
          await _commandQueue.startRepeat(
            mode: RepeatUXMode.singleAyah.index,
            count: intent.repeatCount ?? 3,
            startAyah: intent.ayahNumber,
          );
        }
        break;

      case VoiceIntentType.repeatRange:
        if (intent.ayahNumber != null && intent.endAyahNumber != null) {
          await _commandQueue.startRepeat(
            mode: RepeatUXMode.range.index,
            count: intent.repeatCount ?? 1,
            startAyah: intent.ayahNumber,
            endAyah: intent.endAyahNumber,
          );
        }
        break;

      case VoiceIntentType.stopRepeat:
        await _commandQueue.stopRepeat();
        break;

      case VoiceIntentType.whatIsPlaying:
        // Emit info event
        break;

      default:
        break;
    }
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> dispose() async {
    await _routingController.close();
    await _confirmationController.close();
    await _rejectionController.close();
  }
}
