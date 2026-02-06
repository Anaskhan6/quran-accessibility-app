/// audio_engine_ffi.dart
///
/// Dart FFI bindings for native C++ audio engine
/// Expanded callbacks with timestamps for deterministic ordering
///
/// Features:
/// - 12 callback types with nanosecond timestamps
/// - Buffered position and preload progress streams
/// - Native repeat state mirror
/// - Command queue integration ready

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

// ============================================================================
// ENUMS
// ============================================================================

/// Playback state (matches C++ PlaybackState)
enum PlaybackState {
  idle,
  loading,
  playing,
  paused,
  stopped,
  buffering,
  error,
}

/// Audio focus state (matches C++ AudioFocusState)
enum AudioFocusState {
  gain,
  loss,
  lossTransient,
  lossTransientCanDuck,
}

/// Repeat mode (matches C++ RepeatMode)
enum RepeatMode {
  none,
  single,
  range,
  infinite,
  count,
}

// ============================================================================
// FFI TYPEDEFS - Lifecycle
// ============================================================================

typedef AudioEngineCreateNative = Pointer<Void> Function();
typedef AudioEngineCreate = Pointer<Void> Function();

typedef AudioEngineDestroyNative = Void Function(Pointer<Void>);
typedef AudioEngineDestroy = void Function(Pointer<Void>);

typedef AudioEngineInitializeNative = Int32 Function(Pointer<Void>);
typedef AudioEngineInitialize = int Function(Pointer<Void>);

typedef AudioEngineShutdownNative = Void Function(Pointer<Void>);
typedef AudioEngineShutdown = void Function(Pointer<Void>);

// ============================================================================
// FFI TYPEDEFS - Playback
// ============================================================================

typedef AudioEngineLoadNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef AudioEngineLoad = int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef AudioEnginePlayNative = Int32 Function(Pointer<Void>);
typedef AudioEnginePlay = int Function(Pointer<Void>);

typedef AudioEnginePauseNative = Int32 Function(Pointer<Void>);
typedef AudioEnginePause = int Function(Pointer<Void>);

typedef AudioEngineStopNative = Int32 Function(Pointer<Void>);
typedef AudioEngineStop = int Function(Pointer<Void>);

typedef AudioEngineSeekNative = Int32 Function(Pointer<Void>, Double);
typedef AudioEngineSeek = int Function(Pointer<Void>, double);

// ============================================================================
// FFI TYPEDEFS - State
// ============================================================================

typedef AudioEngineGetPositionNative = Double Function(Pointer<Void>);
typedef AudioEngineGetPosition = double Function(Pointer<Void>);

typedef AudioEngineGetDurationNative = Double Function(Pointer<Void>);
typedef AudioEngineGetDuration = double Function(Pointer<Void>);

typedef AudioEngineIsPlayingNative = Int32 Function(Pointer<Void>);
typedef AudioEngineIsPlaying = int Function(Pointer<Void>);

typedef AudioEngineGetStateNative = Int32 Function(Pointer<Void>);
typedef AudioEngineGetState = int Function(Pointer<Void>);

// ============================================================================
// FFI TYPEDEFS - Buffering State
// ============================================================================

typedef AudioEngineGetBufferedPositionNative = Double Function(Pointer<Void>);
typedef AudioEngineGetBufferedPosition = double Function(Pointer<Void>);

typedef AudioEngineGetRemainingDurationNative = Double Function(Pointer<Void>);
typedef AudioEngineGetRemainingDuration = double Function(Pointer<Void>);

typedef AudioEngineGetPreloadProgressNative = Double Function(Pointer<Void>);
typedef AudioEngineGetPreloadProgress = double Function(Pointer<Void>);

typedef AudioEngineIsBufferingNative = Int32 Function(Pointer<Void>);
typedef AudioEngineIsBuffering = int Function(Pointer<Void>);

// ============================================================================
// FFI TYPEDEFS - Volume
// ============================================================================

typedef AudioEngineSetVolumeNative = Void Function(Pointer<Void>, Float);
typedef AudioEngineSetVolume = void Function(Pointer<Void>, double);

typedef AudioEngineGetVolumeNative = Float Function(Pointer<Void>);
typedef AudioEngineGetVolume = double Function(Pointer<Void>);

typedef AudioEngineDuckVolumeNative = Void Function(Pointer<Void>, Float, Int32);
typedef AudioEngineDuckVolume = void Function(Pointer<Void>, double, int);

typedef AudioEngineRestoreVolumeNative = Void Function(Pointer<Void>, Int32);
typedef AudioEngineRestoreVolume = void Function(Pointer<Void>, int);

typedef AudioEngineFocusChangeNative = Void Function(Pointer<Void>, Int32);
typedef AudioEngineFocusChange = void Function(Pointer<Void>, int);

// ============================================================================
// FFI TYPEDEFS - Speed
// ============================================================================

typedef AudioEngineSetSpeedNative = Void Function(Pointer<Void>, Float);
typedef AudioEngineSetSpeed = void Function(Pointer<Void>, double);

typedef AudioEngineGetSpeedNative = Float Function(Pointer<Void>);
typedef AudioEngineGetSpeed = double Function(Pointer<Void>);

// ============================================================================
// FFI TYPEDEFS - Preload
// ============================================================================

typedef AudioEnginePreloadNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef AudioEnginePreload = int Function(Pointer<Void>, Pointer<Utf8>);

typedef AudioEngineSwitchPreloadNative = Int32 Function(Pointer<Void>);
typedef AudioEngineSwitchPreload = int Function(Pointer<Void>);

typedef AudioEngineClearPreloadNative = Void Function(Pointer<Void>);
typedef AudioEngineClearPreload = void Function(Pointer<Void>);

// ============================================================================
// FFI TYPEDEFS - Native Repeat
// ============================================================================

typedef AudioEngineSetRepeatModeNative = Void Function(Pointer<Void>, Int32, Int32);
typedef AudioEngineSetRepeatMode = void Function(Pointer<Void>, int, int);

typedef AudioEngineSetRepeatRangeNative = Void Function(Pointer<Void>, Int32, Int32);
typedef AudioEngineSetRepeatRange = void Function(Pointer<Void>, int, int);

typedef AudioEngineSetRepeatPauseIntervalNative = Void Function(Pointer<Void>, Int32);
typedef AudioEngineSetRepeatPauseInterval = void Function(Pointer<Void>, int);

typedef AudioEngineClearRepeatNative = Void Function(Pointer<Void>);
typedef AudioEngineClearRepeat = void Function(Pointer<Void>);

typedef AudioEngineGetRepeatModeNative = Int32 Function(Pointer<Void>);
typedef AudioEngineGetRepeatMode = int Function(Pointer<Void>);

typedef AudioEngineGetRepeatIterationNative = Int32 Function(Pointer<Void>);
typedef AudioEngineGetRepeatIteration = int Function(Pointer<Void>);

typedef AudioEngineGetRepeatTargetNative = Int32 Function(Pointer<Void>);
typedef AudioEngineGetRepeatTarget = int Function(Pointer<Void>);

typedef AudioEngineIsRepeatActiveNative = Int32 Function(Pointer<Void>);
typedef AudioEngineIsRepeatActive = int Function(Pointer<Void>);

// ============================================================================
// FFI TYPEDEFS - Expanded Callbacks
// ============================================================================

typedef PlaybackStartedCallbackNative = Void Function(Int64);
typedef PlaybackPausedCallbackNative = Void Function(Int64, Double);
typedef PlaybackResumedCallbackNative = Void Function(Int64, Double);
typedef PlaybackStoppedCallbackNative = Void Function(Int64);
typedef BufferingChangedCallbackNative = Void Function(Int32, Double);
typedef SeekCompletedCallbackNative = Void Function(Int64, Double);
typedef PreloadCompletedCallbackNative = Void Function(Pointer<Utf8>);
typedef AyahEndedCallbackNative = Void Function();
typedef PositionChangedCallbackNative = Void Function(Double);
typedef RepeatIterationCallbackNative = Void Function(Int32, Int32);
typedef RepeatCompletedCallbackNative = Void Function();
typedef ErrorCallbackNative = Void Function(Pointer<Utf8>);

typedef AudioEngineSetExpandedCallbacksNative = Void Function(
  Pointer<Void>,
  Pointer<NativeFunction<PlaybackStartedCallbackNative>>,
  Pointer<NativeFunction<PlaybackPausedCallbackNative>>,
  Pointer<NativeFunction<PlaybackResumedCallbackNative>>,
  Pointer<NativeFunction<PlaybackStoppedCallbackNative>>,
  Pointer<NativeFunction<BufferingChangedCallbackNative>>,
  Pointer<NativeFunction<SeekCompletedCallbackNative>>,
  Pointer<NativeFunction<PreloadCompletedCallbackNative>>,
  Pointer<NativeFunction<AyahEndedCallbackNative>>,
  Pointer<NativeFunction<PositionChangedCallbackNative>>,
  Pointer<NativeFunction<RepeatIterationCallbackNative>>,
  Pointer<NativeFunction<RepeatCompletedCallbackNative>>,
  Pointer<NativeFunction<ErrorCallbackNative>>,
);

typedef AudioEngineSetExpandedCallbacks = void Function(
  Pointer<Void>,
  Pointer<NativeFunction<PlaybackStartedCallbackNative>>,
  Pointer<NativeFunction<PlaybackPausedCallbackNative>>,
  Pointer<NativeFunction<PlaybackResumedCallbackNative>>,
  Pointer<NativeFunction<PlaybackStoppedCallbackNative>>,
  Pointer<NativeFunction<BufferingChangedCallbackNative>>,
  Pointer<NativeFunction<SeekCompletedCallbackNative>>,
  Pointer<NativeFunction<PreloadCompletedCallbackNative>>,
  Pointer<NativeFunction<AyahEndedCallbackNative>>,
  Pointer<NativeFunction<PositionChangedCallbackNative>>,
  Pointer<NativeFunction<RepeatIterationCallbackNative>>,
  Pointer<NativeFunction<RepeatCompletedCallbackNative>>,
  Pointer<NativeFunction<ErrorCallbackNative>>,
);

// ============================================================================
// CALLBACK EVENT CLASSES
// ============================================================================

/// Playback started event with timestamp
class PlaybackStartedEvent {
  final int timestampNs;
  PlaybackStartedEvent(this.timestampNs);
}

/// Playback paused event with timestamp and position
class PlaybackPausedEvent {
  final int timestampNs;
  final double position;
  PlaybackPausedEvent(this.timestampNs, this.position);
}

/// Playback resumed event with timestamp and position
class PlaybackResumedEvent {
  final int timestampNs;
  final double position;
  PlaybackResumedEvent(this.timestampNs, this.position);
}

/// Playback stopped event with timestamp
class PlaybackStoppedEvent {
  final int timestampNs;
  PlaybackStoppedEvent(this.timestampNs);
}

/// Buffering changed event
class BufferingChangedEvent {
  final bool isBuffering;
  final double progress;
  BufferingChangedEvent(this.isBuffering, this.progress);
}

/// Seek completed event with timestamp and position
class SeekCompletedEvent {
  final int timestampNs;
  final double position;
  SeekCompletedEvent(this.timestampNs, this.position);
}

/// Preload completed event
class PreloadCompletedEvent {
  final String filePath;
  PreloadCompletedEvent(this.filePath);
}

/// Repeat iteration event
class RepeatIterationEvent {
  final int current;
  final int total;
  RepeatIterationEvent(this.current, this.total);
}

/// Native repeat state mirror (read-only from Dart)
class NativeRepeatState {
  final RepeatMode mode;
  final int iteration;
  final int targetIterations;
  final bool isActive;

  const NativeRepeatState({
    required this.mode,
    required this.iteration,
    required this.targetIterations,
    required this.isActive,
  });

  static const none = NativeRepeatState(
    mode: RepeatMode.none,
    iteration: 0,
    targetIterations: 0,
    isActive: false,
  );
}

// ============================================================================
// AUDIO ENGINE FFI
// ============================================================================

/// AudioEngineFFI
///
/// Manages FFI bindings to native audio engine with expanded callbacks
class AudioEngineFFI {
  static AudioEngineFFI? _instance;

  late final DynamicLibrary _lib;
  Pointer<Void>? _engine;
  bool _isInitialized = false;

  // Stream controllers - expanded callbacks
  final _playbackStartedController = StreamController<PlaybackStartedEvent>.broadcast();
  final _playbackPausedController = StreamController<PlaybackPausedEvent>.broadcast();
  final _playbackResumedController = StreamController<PlaybackResumedEvent>.broadcast();
  final _playbackStoppedController = StreamController<PlaybackStoppedEvent>.broadcast();
  final _bufferingChangedController = StreamController<BufferingChangedEvent>.broadcast();
  final _seekCompletedController = StreamController<SeekCompletedEvent>.broadcast();
  final _preloadCompletedController = StreamController<PreloadCompletedEvent>.broadcast();
  final _ayahEndedController = StreamController<void>.broadcast();
  final _positionController = StreamController<double>.broadcast();
  final _repeatIterationController = StreamController<RepeatIterationEvent>.broadcast();
  final _repeatCompletedController = StreamController<void>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Buffered state streams
  final _bufferedPositionController = StreamController<double>.broadcast();
  final _remainingDurationController = StreamController<double>.broadcast();
  final _preloadProgressController = StreamController<double>.broadcast();

  // ===========================================================================
  // STREAMS
  // ===========================================================================

  /// Playback started with timestamp
  Stream<PlaybackStartedEvent> get onPlaybackStarted => _playbackStartedController.stream;

  /// Playback paused with timestamp and position
  Stream<PlaybackPausedEvent> get onPlaybackPaused => _playbackPausedController.stream;

  /// Playback resumed with timestamp and position
  Stream<PlaybackResumedEvent> get onPlaybackResumed => _playbackResumedController.stream;

  /// Playback stopped with timestamp
  Stream<PlaybackStoppedEvent> get onPlaybackStopped => _playbackStoppedController.stream;

  /// Buffering state changed
  Stream<BufferingChangedEvent> get onBufferingChanged => _bufferingChangedController.stream;

  /// Seek completed with timestamp and position
  Stream<SeekCompletedEvent> get onSeekCompleted => _seekCompletedController.stream;

  /// Preload completed
  Stream<PreloadCompletedEvent> get onPreloadCompleted => _preloadCompletedController.stream;

  /// Ayah playback completed
  Stream<void> get onAyahEnded => _ayahEndedController.stream;

  /// Position updates (~100ms during playback)
  Stream<double> get onPositionChanged => _positionController.stream;

  /// Repeat iteration event
  Stream<RepeatIterationEvent> get onRepeatIteration => _repeatIterationController.stream;

  /// Repeat loop completed
  Stream<void> get onRepeatCompleted => _repeatCompletedController.stream;

  /// Error events
  Stream<String> get onError => _errorController.stream;

  /// Buffered position updates
  Stream<double> get bufferedPosition => _bufferedPositionController.stream;

  /// Remaining duration updates
  Stream<double> get remainingDuration => _remainingDurationController.stream;

  /// Preload progress (0.0 - 1.0)
  Stream<double> get preloadProgress => _preloadProgressController.stream;

  // Native function pointers
  late final AudioEngineCreate _create;
  late final AudioEngineDestroy _destroy;
  late final AudioEngineInitialize _initialize;
  late final AudioEngineShutdown _shutdown;
  late final AudioEngineLoad _load;
  late final AudioEnginePlay _play;
  late final AudioEnginePause _pause;
  late final AudioEngineStop _stop;
  late final AudioEngineSeek _seek;
  late final AudioEngineGetPosition _getPosition;
  late final AudioEngineGetDuration _getDuration;
  late final AudioEngineIsPlaying _isPlaying;
  late final AudioEngineGetState _getState;
  late final AudioEngineGetBufferedPosition _getBufferedPosition;
  late final AudioEngineGetRemainingDuration _getRemainingDuration;
  late final AudioEngineGetPreloadProgress _getPreloadProgress;
  late final AudioEngineIsBuffering _isBuffering;
  late final AudioEngineSetVolume _setVolume;
  late final AudioEngineGetVolume _getVolume;
  late final AudioEngineDuckVolume _duckVolume;
  late final AudioEngineRestoreVolume _restoreVolume;
  late final AudioEngineFocusChange _focusChange;
  late final AudioEngineSetSpeed _setSpeed;
  late final AudioEngineGetSpeed _getSpeed;
  late final AudioEnginePreload _preload;
  late final AudioEngineSwitchPreload _switchPreload;
  late final AudioEngineClearPreload _clearPreload;
  late final AudioEngineSetRepeatMode _setRepeatMode;
  late final AudioEngineSetRepeatRange _setRepeatRange;
  late final AudioEngineSetRepeatPauseInterval _setRepeatPauseInterval;
  late final AudioEngineClearRepeat _clearRepeat;
  late final AudioEngineGetRepeatMode _getRepeatMode;
  late final AudioEngineGetRepeatIteration _getRepeatIteration;
  late final AudioEngineGetRepeatTarget _getRepeatTarget;
  late final AudioEngineIsRepeatActive _isRepeatActive;
  late final AudioEngineSetExpandedCallbacks _setExpandedCallbacks;

  AudioEngineFFI._internal() {
    _loadLibrary();
    _bindFunctions();
  }

  /// Get singleton instance
  static AudioEngineFFI get instance {
    _instance ??= AudioEngineFFI._internal();
    return _instance!;
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libquran_native.so');
    } else if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  void _bindFunctions() {
    _create = _lib.lookupFunction<AudioEngineCreateNative, AudioEngineCreate>('audio_engine_create');
    _destroy = _lib.lookupFunction<AudioEngineDestroyNative, AudioEngineDestroy>('audio_engine_destroy');
    _initialize = _lib.lookupFunction<AudioEngineInitializeNative, AudioEngineInitialize>('audio_engine_initialize');
    _shutdown = _lib.lookupFunction<AudioEngineShutdownNative, AudioEngineShutdown>('audio_engine_shutdown');
    _load = _lib.lookupFunction<AudioEngineLoadNative, AudioEngineLoad>('audio_engine_load');
    _play = _lib.lookupFunction<AudioEnginePlayNative, AudioEnginePlay>('audio_engine_play');
    _pause = _lib.lookupFunction<AudioEnginePauseNative, AudioEnginePause>('audio_engine_pause');
    _stop = _lib.lookupFunction<AudioEngineStopNative, AudioEngineStop>('audio_engine_stop');
    _seek = _lib.lookupFunction<AudioEngineSeekNative, AudioEngineSeek>('audio_engine_seek');
    _getPosition = _lib.lookupFunction<AudioEngineGetPositionNative, AudioEngineGetPosition>('audio_engine_get_position');
    _getDuration = _lib.lookupFunction<AudioEngineGetDurationNative, AudioEngineGetDuration>('audio_engine_get_duration');
    _isPlaying = _lib.lookupFunction<AudioEngineIsPlayingNative, AudioEngineIsPlaying>('audio_engine_is_playing');
    _getState = _lib.lookupFunction<AudioEngineGetStateNative, AudioEngineGetState>('audio_engine_get_state');
    _getBufferedPosition = _lib.lookupFunction<AudioEngineGetBufferedPositionNative, AudioEngineGetBufferedPosition>('audio_engine_get_buffered_position');
    _getRemainingDuration = _lib.lookupFunction<AudioEngineGetRemainingDurationNative, AudioEngineGetRemainingDuration>('audio_engine_get_remaining_duration');
    _getPreloadProgress = _lib.lookupFunction<AudioEngineGetPreloadProgressNative, AudioEngineGetPreloadProgress>('audio_engine_get_preload_progress');
    _isBuffering = _lib.lookupFunction<AudioEngineIsBufferingNative, AudioEngineIsBuffering>('audio_engine_is_buffering');
    _setVolume = _lib.lookupFunction<AudioEngineSetVolumeNative, AudioEngineSetVolume>('audio_engine_set_volume');
    _getVolume = _lib.lookupFunction<AudioEngineGetVolumeNative, AudioEngineGetVolume>('audio_engine_get_volume');
    _duckVolume = _lib.lookupFunction<AudioEngineDuckVolumeNative, AudioEngineDuckVolume>('audio_engine_duck_volume');
    _restoreVolume = _lib.lookupFunction<AudioEngineRestoreVolumeNative, AudioEngineRestoreVolume>('audio_engine_restore_volume');
    _focusChange = _lib.lookupFunction<AudioEngineFocusChangeNative, AudioEngineFocusChange>('audio_engine_on_audio_focus_change');
    _setSpeed = _lib.lookupFunction<AudioEngineSetSpeedNative, AudioEngineSetSpeed>('audio_engine_set_speed');
    _getSpeed = _lib.lookupFunction<AudioEngineGetSpeedNative, AudioEngineGetSpeed>('audio_engine_get_speed');
    _preload = _lib.lookupFunction<AudioEnginePreloadNative, AudioEnginePreload>('audio_engine_preload_next');
    _switchPreload = _lib.lookupFunction<AudioEngineSwitchPreloadNative, AudioEngineSwitchPreload>('audio_engine_switch_to_preloaded');
    _clearPreload = _lib.lookupFunction<AudioEngineClearPreloadNative, AudioEngineClearPreload>('audio_engine_clear_preload');
    _setRepeatMode = _lib.lookupFunction<AudioEngineSetRepeatModeNative, AudioEngineSetRepeatMode>('audio_engine_set_repeat_mode');
    _setRepeatRange = _lib.lookupFunction<AudioEngineSetRepeatRangeNative, AudioEngineSetRepeatRange>('audio_engine_set_repeat_range');
    _setRepeatPauseInterval = _lib.lookupFunction<AudioEngineSetRepeatPauseIntervalNative, AudioEngineSetRepeatPauseInterval>('audio_engine_set_repeat_pause_interval');
    _clearRepeat = _lib.lookupFunction<AudioEngineClearRepeatNative, AudioEngineClearRepeat>('audio_engine_clear_repeat');
    _getRepeatMode = _lib.lookupFunction<AudioEngineGetRepeatModeNative, AudioEngineGetRepeatMode>('audio_engine_get_repeat_mode');
    _getRepeatIteration = _lib.lookupFunction<AudioEngineGetRepeatIterationNative, AudioEngineGetRepeatIteration>('audio_engine_get_repeat_iteration');
    _getRepeatTarget = _lib.lookupFunction<AudioEngineGetRepeatTargetNative, AudioEngineGetRepeatTarget>('audio_engine_get_repeat_target');
    _isRepeatActive = _lib.lookupFunction<AudioEngineIsRepeatActiveNative, AudioEngineIsRepeatActive>('audio_engine_is_repeat_active');
    _setExpandedCallbacks = _lib.lookupFunction<AudioEngineSetExpandedCallbacksNative, AudioEngineSetExpandedCallbacks>('audio_engine_set_expanded_callbacks');
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  Future<bool> init() async {
    if (_isInitialized) return true;

    _engine = _create();
    if (_engine == null || _engine == nullptr) return false;

    final result = _initialize(_engine!);
    if (result != 1) {
      _destroy(_engine!);
      _engine = null;
      return false;
    }

    _isInitialized = true;
    return true;
  }

  Future<void> dispose() async {
    if (!_isInitialized || _engine == null) return;

    _shutdown(_engine!);
    _destroy(_engine!);
    _engine = null;
    _isInitialized = false;

    await Future.wait([
      _playbackStartedController.close(),
      _playbackPausedController.close(),
      _playbackResumedController.close(),
      _playbackStoppedController.close(),
      _bufferingChangedController.close(),
      _seekCompletedController.close(),
      _preloadCompletedController.close(),
      _ayahEndedController.close(),
      _positionController.close(),
      _repeatIterationController.close(),
      _repeatCompletedController.close(),
      _errorController.close(),
      _bufferedPositionController.close(),
      _remainingDurationController.close(),
      _preloadProgressController.close(),
    ]);
  }

  Future<bool> loadAudio(String filePath, {bool preload = false}) async {
    if (!_isInitialized || _engine == null) return false;

    final pathPtr = filePath.toNativeUtf8();
    try {
      return _load(_engine!, pathPtr, preload ? 1 : 0) == 1;
    } finally {
      calloc.free(pathPtr);
    }
  }

  bool play() {
    if (!_isInitialized || _engine == null) return false;
    return _play(_engine!) == 1;
  }

  bool pause() {
    if (!_isInitialized || _engine == null) return false;
    return _pause(_engine!) == 1;
  }

  bool stop() {
    if (!_isInitialized || _engine == null) return false;
    return _stop(_engine!) == 1;
  }

  bool seekTo(double positionSeconds) {
    if (!_isInitialized || _engine == null) return false;
    return _seek(_engine!, positionSeconds) == 1;
  }

  double get position {
    if (!_isInitialized || _engine == null) return 0.0;
    return _getPosition(_engine!);
  }

  double get duration {
    if (!_isInitialized || _engine == null) return 0.0;
    return _getDuration(_engine!);
  }

  bool get playing {
    if (!_isInitialized || _engine == null) return false;
    return _isPlaying(_engine!) == 1;
  }

  PlaybackState get state {
    if (!_isInitialized || _engine == null) return PlaybackState.idle;
    final stateInt = _getState(_engine!);
    return PlaybackState.values[stateInt.clamp(0, PlaybackState.values.length - 1)];
  }

  // Buffering state getters
  double get bufferedPositionValue {
    if (!_isInitialized || _engine == null) return 0.0;
    return _getBufferedPosition(_engine!);
  }

  double get remainingDurationValue {
    if (!_isInitialized || _engine == null) return 0.0;
    return _getRemainingDuration(_engine!);
  }

  double get preloadProgressValue {
    if (!_isInitialized || _engine == null) return 0.0;
    return _getPreloadProgress(_engine!);
  }

  bool get isBufferingValue {
    if (!_isInitialized || _engine == null) return false;
    return _isBuffering(_engine!) == 1;
  }

  // Volume
  set volume(double value) {
    if (!_isInitialized || _engine == null) return;
    _setVolume(_engine!, value.clamp(0.0, 1.0));
  }

  double get volume {
    if (!_isInitialized || _engine == null) return 1.0;
    return _getVolume(_engine!);
  }

  void duckVolume({double duckLevel = 0.3, int fadeMs = 100}) {
    if (!_isInitialized || _engine == null) return;
    _duckVolume(_engine!, duckLevel, fadeMs);
  }

  void restoreVolume({int fadeMs = 500}) {
    if (!_isInitialized || _engine == null) return;
    _restoreVolume(_engine!, fadeMs);
  }

  void onAudioFocusChange(AudioFocusState focusState) {
    if (!_isInitialized || _engine == null) return;
    _focusChange(_engine!, focusState.index);
  }

  // Speed
  set playbackSpeed(double speed) {
    if (!_isInitialized || _engine == null) return;
    _setSpeed(_engine!, speed.clamp(0.5, 2.0));
  }

  double get playbackSpeed {
    if (!_isInitialized || _engine == null) return 1.0;
    return _getSpeed(_engine!);
  }

  // Preload
  Future<bool> preloadNext(String filePath) async {
    if (!_isInitialized || _engine == null) return false;

    final pathPtr = filePath.toNativeUtf8();
    try {
      return _preload(_engine!, pathPtr) == 1;
    } finally {
      calloc.free(pathPtr);
    }
  }

  bool switchToPreloaded() {
    if (!_isInitialized || _engine == null) return false;
    return _switchPreload(_engine!) == 1;
  }

  void clearPreload() {
    if (!_isInitialized || _engine == null) return;
    _clearPreload(_engine!);
  }

  // Native repeat control
  void setRepeatMode(RepeatMode mode, {int count = 1}) {
    if (!_isInitialized || _engine == null) return;
    _setRepeatMode(_engine!, mode.index, count);
  }

  void setRepeatRange(int startAyah, int endAyah) {
    if (!_isInitialized || _engine == null) return;
    _setRepeatRange(_engine!, startAyah, endAyah);
  }

  void setRepeatPauseInterval(int intervalMs) {
    if (!_isInitialized || _engine == null) return;
    _setRepeatPauseInterval(_engine!, intervalMs);
  }

  void clearRepeat() {
    if (!_isInitialized || _engine == null) return;
    _clearRepeat(_engine!);
  }

  NativeRepeatState get repeatState {
    if (!_isInitialized || _engine == null) return NativeRepeatState.none;

    final modeInt = _getRepeatMode(_engine!);
    final mode = RepeatMode.values[modeInt.clamp(0, RepeatMode.values.length - 1)];
    final iteration = _getRepeatIteration(_engine!);
    final target = _getRepeatTarget(_engine!);
    final isActive = _isRepeatActive(_engine!) == 1;

    return NativeRepeatState(
      mode: mode,
      iteration: iteration,
      targetIterations: target,
      isActive: isActive,
    );
  }
}
