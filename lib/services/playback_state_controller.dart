/// playback_state_controller.dart
///
/// Canonical Playback State Machine
/// Single source of truth for playback state
///
/// Responsibilities:
/// - Consume native callbacks
/// - Normalize state transitions
/// - Expose read-only state stream
/// - Prevent illegal transitions

import 'dart:async';

// ============================================================================
// ENUMS
// ============================================================================

/// Canonical playback states
enum PlaybackStateType {
  /// No audio loaded, idle state
  idle,

  /// Audio file being loaded/decoded
  loading,

  /// Audio actively playing
  playing,

  /// Playback paused, position preserved
  paused,

  /// Buffering audio data
  buffering,

  /// Seeking to new position
  seeking,

  /// In repeat loop
  repeating,

  /// Playback reached end
  completed,

  /// Error state
  error,
}

/// State transition result
enum TransitionResult {
  /// Transition succeeded
  success,

  /// Transition rejected as illegal
  rejected,

  /// Transition ignored (already in target state)
  ignored,
}

// ============================================================================
// STATE MODEL
// ============================================================================

/// Immutable playback state snapshot
class PlaybackState {
  final PlaybackStateType type;
  final int? surahId;
  final int? ayahNumber;
  final double position;
  final double duration;
  final double bufferedPosition;
  final double playbackSpeed;
  final bool isRepeating;
  final int? repeatIteration;
  final int? repeatTotal;
  final String? errorMessage;
  final DateTime timestamp;

  const PlaybackState({
    required this.type,
    this.surahId,
    this.ayahNumber,
    this.position = 0.0,
    this.duration = 0.0,
    this.bufferedPosition = 0.0,
    this.playbackSpeed = 1.0,
    this.isRepeating = false,
    this.repeatIteration,
    this.repeatTotal,
    this.errorMessage,
    required this.timestamp,
  });

  /// Initial idle state
  static PlaybackState get initial => PlaybackState(
        type: PlaybackStateType.idle,
        timestamp: DateTime.now(),
      );

  /// Create copy with updated fields
  PlaybackState copyWith({
    PlaybackStateType? type,
    int? surahId,
    int? ayahNumber,
    double? position,
    double? duration,
    double? bufferedPosition,
    double? playbackSpeed,
    bool? isRepeating,
    int? repeatIteration,
    int? repeatTotal,
    String? errorMessage,
  }) {
    return PlaybackState(
      type: type ?? this.type,
      surahId: surahId ?? this.surahId,
      ayahNumber: ayahNumber ?? this.ayahNumber,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      isRepeating: isRepeating ?? this.isRepeating,
      repeatIteration: repeatIteration ?? this.repeatIteration,
      repeatTotal: repeatTotal ?? this.repeatTotal,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: DateTime.now(),
    );
  }

  /// Check if audio is loaded
  bool get hasAudio => surahId != null && ayahNumber != null;

  /// Check if actively outputting audio
  bool get isActive =>
      type == PlaybackStateType.playing || type == PlaybackStateType.repeating;

  /// Accessibility description
  String get accessibilityLabel {
    switch (type) {
      case PlaybackStateType.idle:
        return 'Ready';
      case PlaybackStateType.loading:
        return 'Loading';
      case PlaybackStateType.playing:
        return 'Playing';
      case PlaybackStateType.paused:
        return 'Paused';
      case PlaybackStateType.buffering:
        return 'Buffering';
      case PlaybackStateType.seeking:
        return 'Seeking';
      case PlaybackStateType.repeating:
        return isRepeating
            ? 'Repeating ${repeatIteration ?? 0} of ${repeatTotal ?? 0}'
            : 'Repeating';
      case PlaybackStateType.completed:
        return 'Completed';
      case PlaybackStateType.error:
        return 'Error: ${errorMessage ?? "Unknown"}';
    }
  }

  @override
  String toString() => 'PlaybackState($type, pos=$position, dur=$duration)';
}

/// State transition event for logging/debugging
class StateTransition {
  final PlaybackStateType from;
  final PlaybackStateType to;
  final TransitionResult result;
  final String? reason;
  final DateTime timestamp;

  const StateTransition({
    required this.from,
    required this.to,
    required this.result,
    this.reason,
    required this.timestamp,
  });

  @override
  String toString() => '$from → $to: $result${reason != null ? " ($reason)" : ""}';
}

// ============================================================================
// STATE MACHINE
// ============================================================================

/// Playback State Controller
///
/// Canonical authority for playback state.
/// Consumes native callbacks and enforces valid state transitions.
class PlaybackStateController {
  PlaybackState _state = PlaybackState.initial;

  final _stateController = StreamController<PlaybackState>.broadcast();
  final _transitionController = StreamController<StateTransition>.broadcast();

  /// Read-only state stream
  Stream<PlaybackState> get stateStream => _stateController.stream;

  /// State transition events (for debugging/logging)
  Stream<StateTransition> get transitionStream => _transitionController.stream;

  /// Current state (read-only)
  PlaybackState get state => _state;

  /// Current state type
  PlaybackStateType get type => _state.type;

  // ===========================================================================
  // TRANSITION RULES
  // ===========================================================================

  /// Valid transitions from each state
  static const Map<PlaybackStateType, Set<PlaybackStateType>> _validTransitions = {
    PlaybackStateType.idle: {
      PlaybackStateType.loading,
      PlaybackStateType.error,
    },
    PlaybackStateType.loading: {
      PlaybackStateType.playing,
      PlaybackStateType.paused, // Loaded but not auto-playing
      PlaybackStateType.idle,
      PlaybackStateType.error,
    },
    PlaybackStateType.playing: {
      PlaybackStateType.paused,
      PlaybackStateType.seeking,
      PlaybackStateType.repeating,
      PlaybackStateType.completed,
      PlaybackStateType.buffering,
      PlaybackStateType.idle, // Stop
      PlaybackStateType.loading, // Load new
      PlaybackStateType.error,
    },
    PlaybackStateType.paused: {
      PlaybackStateType.playing, // Resume
      PlaybackStateType.seeking,
      PlaybackStateType.idle, // Stop
      PlaybackStateType.loading, // Load new
      PlaybackStateType.error,
    },
    PlaybackStateType.buffering: {
      PlaybackStateType.playing,
      PlaybackStateType.paused,
      PlaybackStateType.idle,
      PlaybackStateType.error,
    },
    PlaybackStateType.seeking: {
      PlaybackStateType.playing,
      PlaybackStateType.paused,
      PlaybackStateType.repeating,
      PlaybackStateType.idle,
      PlaybackStateType.error,
    },
    PlaybackStateType.repeating: {
      PlaybackStateType.playing, // Exit repeat
      PlaybackStateType.paused,
      PlaybackStateType.seeking,
      PlaybackStateType.completed,
      PlaybackStateType.idle,
      PlaybackStateType.error,
    },
    PlaybackStateType.completed: {
      PlaybackStateType.idle,
      PlaybackStateType.loading,
      PlaybackStateType.playing, // Replay
      PlaybackStateType.repeating,
    },
    PlaybackStateType.error: {
      PlaybackStateType.idle,
      PlaybackStateType.loading,
    },
  };

  /// Check if transition is valid
  bool isValidTransition(PlaybackStateType from, PlaybackStateType to) {
    if (from == to) return true; // Same state is always valid
    final validTargets = _validTransitions[from];
    return validTargets?.contains(to) ?? false;
  }

  // ===========================================================================
  // STATE TRANSITIONS
  // ===========================================================================

  /// Attempt state transition
  TransitionResult transition(
    PlaybackStateType newType, {
    int? surahId,
    int? ayahNumber,
    double? position,
    double? duration,
    String? errorMessage,
  }) {
    final oldType = _state.type;

    // Check for same state
    if (oldType == newType) {
      _recordTransition(oldType, newType, TransitionResult.ignored, 'Same state');
      return TransitionResult.ignored;
    }

    // Validate transition
    if (!isValidTransition(oldType, newType)) {
      _recordTransition(
        oldType,
        newType,
        TransitionResult.rejected,
        'Invalid transition from $oldType to $newType',
      );
      return TransitionResult.rejected;
    }

    // Execute transition
    _state = _state.copyWith(
      type: newType,
      surahId: surahId,
      ayahNumber: ayahNumber,
      position: position,
      duration: duration,
      errorMessage: newType == PlaybackStateType.error ? errorMessage : null,
    );

    _stateController.add(_state);
    _recordTransition(oldType, newType, TransitionResult.success);

    return TransitionResult.success;
  }

  /// Record transition for debugging
  void _recordTransition(
    PlaybackStateType from,
    PlaybackStateType to,
    TransitionResult result, [
    String? reason,
  ]) {
    _transitionController.add(StateTransition(
      from: from,
      to: to,
      result: result,
      reason: reason,
      timestamp: DateTime.now(),
    ));
  }

  // ===========================================================================
  // CONVENIENCE METHODS
  // ===========================================================================

  /// Transition to loading
  TransitionResult startLoading({int? surahId, int? ayahNumber}) {
    return transition(
      PlaybackStateType.loading,
      surahId: surahId,
      ayahNumber: ayahNumber,
    );
  }

  /// Transition to playing
  TransitionResult startPlaying({double? position, double? duration}) {
    return transition(
      PlaybackStateType.playing,
      position: position,
      duration: duration,
    );
  }

  /// Transition to paused
  TransitionResult pause({double? position}) {
    return transition(PlaybackStateType.paused, position: position);
  }

  /// Transition to idle (stop)
  TransitionResult stop() {
    return transition(PlaybackStateType.idle);
  }

  /// Transition to seeking
  TransitionResult startSeeking() {
    return transition(PlaybackStateType.seeking);
  }

  /// Transition to repeating
  TransitionResult startRepeating() {
    // Can only start repeating from playing state
    if (_state.type != PlaybackStateType.playing &&
        _state.type != PlaybackStateType.seeking) {
      _recordTransition(
        _state.type,
        PlaybackStateType.repeating,
        TransitionResult.rejected,
        'Can only repeat from playing/seeking state',
      );
      return TransitionResult.rejected;
    }
    return transition(PlaybackStateType.repeating);
  }

  /// Transition to completed
  TransitionResult complete() {
    return transition(PlaybackStateType.completed);
  }

  /// Transition to error
  TransitionResult error(String message) {
    return transition(PlaybackStateType.error, errorMessage: message);
  }

  // ===========================================================================
  // STATE UPDATES (without type change)
  // ===========================================================================

  /// Update position without changing state
  void updatePosition(double position) {
    _state = _state.copyWith(position: position);
    _stateController.add(_state);
  }

  /// Update buffered position
  void updateBufferedPosition(double bufferedPosition) {
    _state = _state.copyWith(bufferedPosition: bufferedPosition);
    _stateController.add(_state);
  }

  /// Update repeat iteration
  void updateRepeatIteration(int iteration, int total) {
    _state = _state.copyWith(
      isRepeating: true,
      repeatIteration: iteration,
      repeatTotal: total,
    );
    _stateController.add(_state);
  }

  /// Update playback speed
  void updateSpeed(double speed) {
    _state = _state.copyWith(playbackSpeed: speed);
    _stateController.add(_state);
  }

  /// Clear repeat state
  void clearRepeat() {
    _state = _state.copyWith(
      isRepeating: false,
      repeatIteration: null,
      repeatTotal: null,
    );
    _stateController.add(_state);
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Reset to initial state
  void reset() {
    _state = PlaybackState.initial;
    _stateController.add(_state);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _stateController.close();
    await _transitionController.close();
  }
}
