/// repeat_orchestrator.dart
///
/// Repeat UX Orchestration Layer
/// Manages repeat behavior across playback lifecycle
///
/// Rules:
/// - Repeat persists after pause
/// - Repeat resets on Surah change
/// - Repeat survives app background
/// - Repeat resumes after call interruption

import 'dart:async';
import 'playback_state_controller.dart';

// ============================================================================
// ENUMS
// ============================================================================

/// Repeat mode for UX layer
enum RepeatUXMode {
  /// No repeat active
  none,

  /// Repeat current Ayah
  singleAyah,

  /// Repeat range of Ayahs
  range,

  /// Repeat specific count
  count,

  /// Infinite loop
  infinite,
}

/// Repeat lifecycle events
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
}

// ============================================================================
// MODELS
// ============================================================================

/// Repeat configuration
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

  /// Single Ayah repeat
  factory RepeatConfig.single({
    required int surahId,
    required int ayah,
    int count = 1,
    int pauseIntervalMs = 0,
  }) {
    return RepeatConfig(
      mode: count < 0 ? RepeatUXMode.infinite : RepeatUXMode.singleAyah,
      surahId: surahId,
      startAyah: ayah,
      endAyah: ayah,
      targetIterations: count < 0 ? -1 : count,
      pauseIntervalMs: pauseIntervalMs,
    );
  }

  /// Range repeat
  factory RepeatConfig.range({
    required int surahId,
    required int startAyah,
    required int endAyah,
    int count = 1,
    int pauseIntervalMs = 0,
  }) {
    return RepeatConfig(
      mode: RepeatUXMode.range,
      surahId: surahId,
      startAyah: startAyah,
      endAyah: endAyah,
      targetIterations: count,
      pauseIntervalMs: pauseIntervalMs,
    );
  }

  /// Check if infinite
  bool get isInfinite => targetIterations < 0;

  /// Range size
  int get rangeSize => endAyah - startAyah + 1;
}

/// Current repeat state
class RepeatState {
  final RepeatConfig? config;
  final int currentIteration;
  final int currentAyah;
  final bool isPaused;
  final bool isActive;
  final DateTime? startedAt;
  final DateTime? pausedAt;

  const RepeatState({
    this.config,
    this.currentIteration = 0,
    this.currentAyah = 0,
    this.isPaused = false,
    this.isActive = false,
    this.startedAt,
    this.pausedAt,
  });

  static const none = RepeatState();

  /// Create copy with updates
  RepeatState copyWith({
    RepeatConfig? config,
    int? currentIteration,
    int? currentAyah,
    bool? isPaused,
    bool? isActive,
    DateTime? startedAt,
    DateTime? pausedAt,
  }) {
    return RepeatState(
      config: config ?? this.config,
      currentIteration: currentIteration ?? this.currentIteration,
      currentAyah: currentAyah ?? this.currentAyah,
      isPaused: isPaused ?? this.isPaused,
      isActive: isActive ?? this.isActive,
      startedAt: startedAt ?? this.startedAt,
      pausedAt: pausedAt ?? this.pausedAt,
    );
  }

  /// Check if complete
  bool get isComplete {
    if (config == null || !isActive) return false;
    if (config!.isInfinite) return false;
    return currentIteration >= config!.targetIterations;
  }

  /// Progress as 0.0 to 1.0
  double get progress {
    if (config == null || config!.isInfinite) return 0.0;
    return currentIteration / config!.targetIterations;
  }

  /// Accessibility announcement
  String get announcement {
    if (config == null || !isActive) return '';

    if (config!.isInfinite) {
      return 'Repeat iteration $currentIteration';
    }

    return 'Repeat ${currentIteration + 1} of ${config!.targetIterations}';
  }
}

/// Repeat event with context
class RepeatEventData {
  final RepeatEvent event;
  final RepeatState state;
  final DateTime timestamp;

  const RepeatEventData({
    required this.event,
    required this.state,
    required this.timestamp,
  });
}

// ============================================================================
// ORCHESTRATOR
// ============================================================================

/// Repeat Orchestrator
///
/// Manages repeat UX behavior independently of native timing
class RepeatOrchestrator {
  final PlaybackStateController _playbackController;

  RepeatState _state = RepeatState.none;
  RepeatState? _savedState; // For interrupt recovery

  final _stateController = StreamController<RepeatState>.broadcast();
  final _eventController = StreamController<RepeatEventData>.broadcast();
  final _announcementController = StreamController<String>.broadcast();

  StreamSubscription<PlaybackState>? _playbackSubscription;

  /// Repeat state stream
  Stream<RepeatState> get stateStream => _stateController.stream;

  /// Repeat events
  Stream<RepeatEventData> get eventStream => _eventController.stream;

  /// Announcements for accessibility
  Stream<String> get announcementStream => _announcementController.stream;

  /// Current state
  RepeatState get state => _state;

  /// Whether repeat is active
  bool get isActive => _state.isActive;

  RepeatOrchestrator(this._playbackController) {
    _subscribeToPlayback();
  }

  /// Subscribe to playback state changes
  void _subscribeToPlayback() {
    _playbackSubscription = _playbackController.stateStream.listen((playback) {
      _handlePlaybackChange(playback);
    });
  }

  /// Handle playback state changes
  void _handlePlaybackChange(PlaybackState playback) {
    if (!_state.isActive) return;

    switch (playback.type) {
      case PlaybackStateType.paused:
        // Repeat persists after pause
        if (!_state.isPaused) {
          _pauseRepeat();
        }
        break;

      case PlaybackStateType.playing:
        // Resume repeat if was paused
        if (_state.isPaused) {
          _resumeRepeat();
        }
        break;

      case PlaybackStateType.loading:
        // Check if Surah changed
        if (_state.config?.surahId != null &&
            playback.surahId != _state.config!.surahId) {
          // Repeat resets on Surah change
          cancelRepeat(reason: 'Surah changed');
        }
        break;

      case PlaybackStateType.idle:
      case PlaybackStateType.completed:
      case PlaybackStateType.error:
        // Interrupt but don't cancel - can be restored
        _interruptRepeat();
        break;

      default:
        break;
    }
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Start repeat with config
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

  /// Cancel repeat
  void cancelRepeat({String? reason}) {
    if (!_state.isActive) return;

    _state = RepeatState.none;
    _savedState = null;

    _stateController.add(_state);
    _emitEvent(RepeatEvent.cancelled);
    _announce('Repeat cancelled');
  }

  /// Handle Ayah completion (called from playback)
  void onAyahCompleted() {
    if (!_state.isActive || _state.config == null) return;

    final config = _state.config!;

    // Check if range mode and need to advance Ayah
    if (config.mode == RepeatUXMode.range &&
        _state.currentAyah < config.endAyah) {
      _advanceAyah();
      return;
    }

    // Check if iterations complete
    if (!config.isInfinite &&
        _state.currentIteration + 1 >= config.targetIterations) {
      _completeRepeat();
      return;
    }

    // Advance iteration
    _advanceIteration();
  }

  /// Handle interrupt (call, app background)
  void onInterrupt() {
    if (!_state.isActive) return;
    _interruptRepeat();
  }

  /// Restore after interrupt
  void restoreAfterInterrupt() {
    if (_savedState == null) return;

    _state = _savedState!.copyWith(
      isPaused: false,
      pausedAt: null,
    );
    _savedState = null;

    _stateController.add(_state);
    _emitEvent(RepeatEvent.restored);
    _announce('Repeat restored');
  }

  // ===========================================================================
  // PRIVATE METHODS
  // ===========================================================================

  void _advanceIteration() {
    final config = _state.config!;

    _state = _state.copyWith(
      currentIteration: _state.currentIteration + 1,
      currentAyah: config.startAyah, // Reset to start for range
    );

    _stateController.add(_state);
    _emitEvent(RepeatEvent.iterationAdvanced);
    _announce(_state.announcement);
  }

  void _advanceAyah() {
    _state = _state.copyWith(
      currentAyah: _state.currentAyah + 1,
    );

    _stateController.add(_state);
    _emitEvent(RepeatEvent.rangeAdvanced);
  }

  void _completeRepeat() {
    final announcement = 'Repeat complete';

    _state = RepeatState.none;
    _savedState = null;

    _stateController.add(_state);
    _emitEvent(RepeatEvent.completed);
    _announce(announcement);
  }

  void _pauseRepeat() {
    _state = _state.copyWith(
      isPaused: true,
      pausedAt: DateTime.now(),
    );

    _stateController.add(_state);
    _emitEvent(RepeatEvent.paused);
  }

  void _resumeRepeat() {
    _state = _state.copyWith(
      isPaused: false,
      pausedAt: null,
    );

    _stateController.add(_state);
    _emitEvent(RepeatEvent.resumed);
    _announce('Repeat resumed');
  }

  void _interruptRepeat() {
    _savedState = _state;

    _state = _state.copyWith(
      isPaused: true,
      pausedAt: DateTime.now(),
    );

    _stateController.add(_state);
    _emitEvent(RepeatEvent.interrupted);
  }

  void _emitEvent(RepeatEvent event) {
    _eventController.add(RepeatEventData(
      event: event,
      state: _state,
      timestamp: DateTime.now(),
    ));
  }

  void _announce(String message) {
    _announcementController.add(message);
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Dispose resources
  Future<void> dispose() async {
    await _playbackSubscription?.cancel();
    await _stateController.close();
    await _eventController.close();
    await _announcementController.close();
  }
}
