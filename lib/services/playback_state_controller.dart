/// playback_state_controller.dart
///
/// Canonical Playback State Machine
/// Audit refinement: Buffering as mid-playback interrupt state

import 'dart:async';

// ============================================================================
// ENUMS
// ============================================================================

/// Canonical playback states
enum PlaybackStateType {
  idle,
  loading,
  playing,
  paused,
  /// Buffering mid-playback (network/preload)
  buffering, 
  seeking,
  repeating,
  completed,
  error,
}

/// State transition result
enum TransitionResult {
  success,
  rejected,
  ignored,
}

// ============================================================================
// STATE MODEL
// ============================================================================

/// Immutable playback state snapshot
class PlaybackState {
  final PlaybackStateType type;
  final PlaybackStateType? preBufferingState; // For resume after buffering
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
    this.preBufferingState,
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

  static PlaybackState get initial => PlaybackState(
        type: PlaybackStateType.idle,
        timestamp: DateTime.now(),
      );

  PlaybackState copyWith({
    PlaybackStateType? type,
    PlaybackStateType? preBufferingState,
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
      preBufferingState: preBufferingState ?? this.preBufferingState,
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

  bool get hasAudio => surahId != null && ayahNumber != null;
  bool get isActive => type == PlaybackStateType.playing || type == PlaybackStateType.repeating;

  String get accessibilityLabel {
    switch (type) {
      case PlaybackStateType.idle: return 'Ready';
      case PlaybackStateType.loading: return 'Loading';
      case PlaybackStateType.playing: return 'Playing';
      case PlaybackStateType.paused: return 'Paused';
      case PlaybackStateType.buffering: return 'Buffering';
      case PlaybackStateType.seeking: return 'Seeking';
      case PlaybackStateType.repeating:
        return isRepeating ? 'Repeating ${repeatIteration ?? 0} of ${repeatTotal ?? 0}' : 'Repeating';
      case PlaybackStateType.completed: return 'Completed';
      case PlaybackStateType.error: return 'Error: ${errorMessage ?? "Unknown"}';
    }
  }
}

/// State transition event
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
}

// ============================================================================
// STATE MACHINE
// ============================================================================

class PlaybackStateController {
  PlaybackState _state = PlaybackState.initial;
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _transitionController = StreamController<StateTransition>.broadcast();

  Stream<PlaybackState> get stateStream => _stateController.stream;
  Stream<StateTransition> get transitionStream => _transitionController.stream;
  PlaybackState get state => _state;
  PlaybackStateType get type => _state.type;

  /// Valid transitions - buffering can interrupt playing/repeating
  static const Map<PlaybackStateType, Set<PlaybackStateType>> _validTransitions = {
    PlaybackStateType.idle: {
      PlaybackStateType.loading,
      PlaybackStateType.error,
    },
    PlaybackStateType.loading: {
      PlaybackStateType.playing,
      PlaybackStateType.paused,
      PlaybackStateType.idle,
      PlaybackStateType.error,
    },
    PlaybackStateType.playing: {
      PlaybackStateType.paused,
      PlaybackStateType.seeking,
      PlaybackStateType.repeating,
      PlaybackStateType.completed,
      PlaybackStateType.buffering, // Mid-playback buffering
      PlaybackStateType.idle,
      PlaybackStateType.loading,
      PlaybackStateType.error,
    },
    PlaybackStateType.paused: {
      PlaybackStateType.playing,
      PlaybackStateType.seeking,
      PlaybackStateType.idle,
      PlaybackStateType.loading,
      PlaybackStateType.error,
    },
    PlaybackStateType.buffering: {
      PlaybackStateType.playing, // Resume to pre-buffering state
      PlaybackStateType.repeating,
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
      PlaybackStateType.playing,
      PlaybackStateType.paused,
      PlaybackStateType.seeking,
      PlaybackStateType.completed,
      PlaybackStateType.buffering, // Mid-repeat buffering
      PlaybackStateType.idle,
      PlaybackStateType.error,
    },
    PlaybackStateType.completed: {
      PlaybackStateType.idle,
      PlaybackStateType.loading,
      PlaybackStateType.playing,
      PlaybackStateType.repeating,
    },
    PlaybackStateType.error: {
      PlaybackStateType.idle,
      PlaybackStateType.loading,
    },
  };

  bool isValidTransition(PlaybackStateType from, PlaybackStateType to) {
    if (from == to) return true;
    return _validTransitions[from]?.contains(to) ?? false;
  }

  TransitionResult transition(
    PlaybackStateType newType, {
    int? surahId,
    int? ayahNumber,
    double? position,
    double? duration,
    String? errorMessage,
  }) {
    final oldType = _state.type;
    if (oldType == newType) {
      _recordTransition(oldType, newType, TransitionResult.ignored, 'Same state');
      return TransitionResult.ignored;
    }

    if (!isValidTransition(oldType, newType)) {
      _recordTransition(oldType, newType, TransitionResult.rejected, 'Invalid transition');
      return TransitionResult.rejected;
    }

    // Save pre-buffering state for resume
    PlaybackStateType? preBuffering;
    if (newType == PlaybackStateType.buffering) {
      preBuffering = oldType;
    }

    _state = _state.copyWith(
      type: newType,
      preBufferingState: preBuffering,
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

  void _recordTransition(PlaybackStateType from, PlaybackStateType to, TransitionResult result, [String? reason]) {
    _transitionController.add(StateTransition(from: from, to: to, result: result, reason: reason, timestamp: DateTime.now()));
  }

  // Convenience methods
  TransitionResult startLoading({int? surahId, int? ayahNumber}) => transition(PlaybackStateType.loading, surahId: surahId, ayahNumber: ayahNumber);
  TransitionResult startPlaying({double? position, double? duration}) => transition(PlaybackStateType.playing, position: position, duration: duration);
  TransitionResult pause({double? position}) => transition(PlaybackStateType.paused, position: position);
  TransitionResult stop() => transition(PlaybackStateType.idle);
  TransitionResult startSeeking() => transition(PlaybackStateType.seeking);
  TransitionResult complete() => transition(PlaybackStateType.completed);
  TransitionResult error(String message) => transition(PlaybackStateType.error, errorMessage: message);

  /// Start buffering mid-playback
  TransitionResult startBuffering() => transition(PlaybackStateType.buffering);

  /// Resume from buffering to pre-buffering state
  TransitionResult resumeFromBuffering() {
    if (_state.preBufferingState != null) {
      return transition(_state.preBufferingState!);
    }
    return transition(PlaybackStateType.playing);
  }

  TransitionResult startRepeating() {
    if (_state.type != PlaybackStateType.playing && _state.type != PlaybackStateType.seeking) {
      _recordTransition(_state.type, PlaybackStateType.repeating, TransitionResult.rejected, 'Can only repeat from playing/seeking');
      return TransitionResult.rejected;
    }
    return transition(PlaybackStateType.repeating);
  }

  void updatePosition(double position) {
    _state = _state.copyWith(position: position);
    _stateController.add(_state);
  }

  void updateBufferedPosition(double bufferedPosition) {
    _state = _state.copyWith(bufferedPosition: bufferedPosition);
    _stateController.add(_state);
  }

  void updateRepeatIteration(int iteration, int total) {
    _state = _state.copyWith(isRepeating: true, repeatIteration: iteration, repeatTotal: total);
    _stateController.add(_state);
  }

  void updateSpeed(double speed) {
    _state = _state.copyWith(playbackSpeed: speed);
    _stateController.add(_state);
  }

  void clearRepeat() {
    _state = _state.copyWith(isRepeating: false, repeatIteration: null, repeatTotal: null);
    _stateController.add(_state);
  }

  void reset() {
    _state = PlaybackState.initial;
    _stateController.add(_state);
  }

  Future<void> dispose() async {
    await _stateController.close();
    await _transitionController.close();
  }
}
