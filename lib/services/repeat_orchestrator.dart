/// repeat_orchestrator.dart
///
/// Repeat UX Orchestration Layer
/// Audit refinement: Manual seek suspends repeat (resumable)

import 'dart:async';
import 'playback_state_controller.dart';

// ============================================================================
// ENUMS
// ============================================================================

enum RepeatUXMode { none, singleAyah, range, count, infinite }

enum RepeatEvent {
  started,
  paused,
  resumed,
  iterationAdvanced,
  rangeAdvanced,
  completed,
  cancelled,
  interrupted,
  restored,
  /// Repeat suspended due to manual seek
  suspendedForSeek,
}

// ============================================================================
// MODELS
// ============================================================================

class RepeatConfig {
  final RepeatUXMode mode;
  final int? surahId;
  final int startAyah;
  final int endAyah;
  final int targetIterations;
  final int pauseIntervalMs;

  const RepeatConfig({
    required this.mode,
    this.surahId,
    required this.startAyah,
    required this.endAyah,
    this.targetIterations = 1,
    this.pauseIntervalMs = 0,
  });

  factory RepeatConfig.single({required int surahId, required int ayah, int count = 1, int pauseIntervalMs = 0}) {
    return RepeatConfig(
      mode: count < 0 ? RepeatUXMode.infinite : RepeatUXMode.singleAyah,
      surahId: surahId,
      startAyah: ayah,
      endAyah: ayah,
      targetIterations: count < 0 ? -1 : count,
      pauseIntervalMs: pauseIntervalMs,
    );
  }

  factory RepeatConfig.range({required int surahId, required int startAyah, required int endAyah, int count = 1, int pauseIntervalMs = 0}) {
    return RepeatConfig(
      mode: RepeatUXMode.range,
      surahId: surahId,
      startAyah: startAyah,
      endAyah: endAyah,
      targetIterations: count,
      pauseIntervalMs: pauseIntervalMs,
    );
  }

  bool get isInfinite => targetIterations < 0;
  int get rangeSize => endAyah - startAyah + 1;
  
  Map<String, dynamic> toJson() => {
    'mode': mode.index,
    'surahId': surahId,
    'startAyah': startAyah,
    'endAyah': endAyah,
    'targetIterations': targetIterations,
    'pauseIntervalMs': pauseIntervalMs,
  };
}

class RepeatState {
  final RepeatConfig? config;
  final int currentIteration;
  final int currentAyah;
  final bool isPaused;
  final bool isActive;
  final bool isSuspendedForSeek; // AUDIT: Seek suspends repeat
  final DateTime? startedAt;
  final DateTime? pausedAt;

  const RepeatState({
    this.config,
    this.currentIteration = 0,
    this.currentAyah = 0,
    this.isPaused = false,
    this.isActive = false,
    this.isSuspendedForSeek = false,
    this.startedAt,
    this.pausedAt,
  });

  static const none = RepeatState();

  RepeatState copyWith({
    RepeatConfig? config,
    int? currentIteration,
    int? currentAyah,
    bool? isPaused,
    bool? isActive,
    bool? isSuspendedForSeek,
    DateTime? startedAt,
    DateTime? pausedAt,
  }) {
    return RepeatState(
      config: config ?? this.config,
      currentIteration: currentIteration ?? this.currentIteration,
      currentAyah: currentAyah ?? this.currentAyah,
      isPaused: isPaused ?? this.isPaused,
      isActive: isActive ?? this.isActive,
      isSuspendedForSeek: isSuspendedForSeek ?? this.isSuspendedForSeek,
      startedAt: startedAt ?? this.startedAt,
      pausedAt: pausedAt ?? this.pausedAt,
    );
  }

  bool get isComplete {
    if (config == null || !isActive) return false;
    if (config!.isInfinite) return false;
    return currentIteration >= config!.targetIterations;
  }

  double get progress {
    if (config == null || config!.isInfinite) return 0.0;
    return currentIteration / config!.targetIterations;
  }

  String get announcement {
    if (config == null || !isActive) return '';
    if (config!.isInfinite) return 'Repeat iteration $currentIteration';
    return 'Repeat ${currentIteration + 1} of ${config!.targetIterations}';
  }
}

class RepeatEventData {
  final RepeatEvent event;
  final RepeatState state;
  final DateTime timestamp;

  const RepeatEventData({required this.event, required this.state, required this.timestamp});
}

// ============================================================================
// ORCHESTRATOR
// ============================================================================

class RepeatOrchestrator {
  final PlaybackStateController _playbackController;

  RepeatState _state = RepeatState.none;
  RepeatState? _savedState;

  final _stateController = StreamController<RepeatState>.broadcast();
  final _eventController = StreamController<RepeatEventData>.broadcast();
  final _announcementController = StreamController<String>.broadcast();
  /// Stream for prompting user to resume after seek
  final _resumePromptController = StreamController<void>.broadcast();

  StreamSubscription<PlaybackState>? _playbackSubscription;

  Stream<RepeatState> get stateStream => _stateController.stream;
  Stream<RepeatEventData> get eventStream => _eventController.stream;
  Stream<String> get announcementStream => _announcementController.stream;
  /// Listen to prompt user: "Resume repeat?"
  Stream<void> get resumePromptStream => _resumePromptController.stream;
  RepeatState get state => _state;
  bool get isActive => _state.isActive;
  bool get isSuspendedForSeek => _state.isSuspendedForSeek;

  RepeatOrchestrator(this._playbackController) {
    _subscribeToPlayback();
  }

  void _subscribeToPlayback() {
    _playbackSubscription = _playbackController.stateStream.listen((playback) {
      _handlePlaybackChange(playback);
    });
  }

  void _handlePlaybackChange(PlaybackState playback) {
    if (!_state.isActive && !_state.isSuspendedForSeek) return;

    switch (playback.type) {
      case PlaybackStateType.paused:
        if (!_state.isPaused && _state.isActive) {
          _pauseRepeat();
        }
        break;

      case PlaybackStateType.playing:
        if (_state.isPaused && !_state.isSuspendedForSeek) {
          _resumeRepeat();
        }
        break;

      case PlaybackStateType.seeking:
        // AUDIT: Manual seek suspends repeat
        if (_state.isActive && !_state.isSuspendedForSeek) {
          _suspendForSeek();
        }
        break;

      case PlaybackStateType.loading:
        if (_state.config?.surahId != null && playback.surahId != _state.config!.surahId) {
          cancelRepeat(reason: 'Surah changed');
        }
        break;

      case PlaybackStateType.idle:
      case PlaybackStateType.completed:
      case PlaybackStateType.error:
        _interruptRepeat();
        break;

      default:
        break;
    }
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  void startRepeat(RepeatConfig config) {
    _state = RepeatState(
      config: config,
      currentIteration: 0,
      currentAyah: config.startAyah,
      isActive: true,
      startedAt: DateTime.now(),
    );
    _stateController.add(_state);
    _emitEvent(RepeatEvent.started);
    _announce('Starting repeat');
  }

  void cancelRepeat({String? reason}) {
    if (!_state.isActive && !_state.isSuspendedForSeek) return;
    _state = RepeatState.none;
    _savedState = null;
    _stateController.add(_state);
    _emitEvent(RepeatEvent.cancelled);
    _announce('Repeat cancelled');
  }

  void onAyahCompleted() {
    if (!_state.isActive || _state.config == null) return;
    final config = _state.config!;

    if (config.mode == RepeatUXMode.range && _state.currentAyah < config.endAyah) {
      _advanceAyah();
      return;
    }

    if (!config.isInfinite && _state.currentIteration + 1 >= config.targetIterations) {
      _completeRepeat();
      return;
    }

    _advanceIteration();
  }

  void onInterrupt() {
    if (!_state.isActive) return;
    _interruptRepeat();
  }

  void restoreAfterInterrupt() {
    if (_savedState == null) return;
    _state = _savedState!.copyWith(isPaused: false, pausedAt: null);
    _savedState = null;
    _stateController.add(_state);
    _emitEvent(RepeatEvent.restored);
    _announce('Repeat restored');
  }

  /// AUDIT: Resume repeat after user confirms (after seek)
  void resumeAfterSeek() {
    if (!_state.isSuspendedForSeek) return;
    _state = _state.copyWith(isSuspendedForSeek: false, isPaused: false);
    _stateController.add(_state);
    _emitEvent(RepeatEvent.resumed);
    _announce('Repeat resumed');
  }

  /// AUDIT: Cancel the suspended repeat
  void cancelSuspendedRepeat() {
    if (!_state.isSuspendedForSeek) return;
    cancelRepeat(reason: 'Cancelled after seek');
  }

  // ===========================================================================
  // PRIVATE METHODS
  // ===========================================================================

  void _suspendForSeek() {
    _state = _state.copyWith(isSuspendedForSeek: true, isPaused: true, pausedAt: DateTime.now());
    _stateController.add(_state);
    _emitEvent(RepeatEvent.suspendedForSeek);
    _resumePromptController.add(null); // Prompt UI to ask user
  }

  void _advanceIteration() {
    final config = _state.config!;
    _state = _state.copyWith(currentIteration: _state.currentIteration + 1, currentAyah: config.startAyah);
    _stateController.add(_state);
    _emitEvent(RepeatEvent.iterationAdvanced);
    _announce(_state.announcement);
  }

  void _advanceAyah() {
    _state = _state.copyWith(currentAyah: _state.currentAyah + 1);
    _stateController.add(_state);
    _emitEvent(RepeatEvent.rangeAdvanced);
  }

  void _completeRepeat() {
    _state = RepeatState.none;
    _savedState = null;
    _stateController.add(_state);
    _emitEvent(RepeatEvent.completed);
    _announce('Repeat complete');
  }

  void _pauseRepeat() {
    _state = _state.copyWith(isPaused: true, pausedAt: DateTime.now());
    _stateController.add(_state);
    _emitEvent(RepeatEvent.paused);
  }

  void _resumeRepeat() {
    _state = _state.copyWith(isPaused: false, pausedAt: null);
    _stateController.add(_state);
    _emitEvent(RepeatEvent.resumed);
    _announce('Repeat resumed');
  }

  void _interruptRepeat() {
    _savedState = _state;
    _state = _state.copyWith(isPaused: true, pausedAt: DateTime.now());
    _stateController.add(_state);
    _emitEvent(RepeatEvent.interrupted);
  }

  void _emitEvent(RepeatEvent event) {
    _eventController.add(RepeatEventData(event: event, state: _state, timestamp: DateTime.now()));
  }

  void _announce(String message) {
    _announcementController.add(message);
  }

  Future<void> dispose() async {
    await _playbackSubscription?.cancel();
    await _stateController.close();
    await _eventController.close();
    await _announcementController.close();
    await _resumePromptController.close();
  }
}
