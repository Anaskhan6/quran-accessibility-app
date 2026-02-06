/// audio_engine_ffi.dart
///
/// Dart FFI bindings for C++ native audio engine
/// Provides low-latency Quran playback using Oboe (Android) / AVAudioEngine (iOS)
///
/// Usage:
/// ```dart
/// final engine = AudioEngineFFI();
/// await engine.load('/path/to/ayah.mp3');
/// await engine.play();
/// ```

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Playback states (must match C++ enum)
enum PlaybackState {
  idle,
  loading,
  playing,
  paused,
  stopped,
  repeating,
  error,
}

/// Audio focus states (must match C++ enum)
enum AudioFocusState {
  gain,
  loss,
  lossTransient,
  lossTransientCanDuck,
}

/// Native function signatures
typedef AudioEngineCreateNative = Pointer<Void> Function();
typedef AudioEngineCreateDart = Pointer<Void> Function();

typedef AudioEngineDestroyNative = Void Function(Pointer<Void> engine);
typedef AudioEngineDestroyDart = void Function(Pointer<Void> engine);

typedef AudioEngineLoadNative = Int32 Function(
    Pointer<Void> engine, Pointer<Utf8> filePath, Int32 preload);
typedef AudioEngineLoadDart = int Function(
    Pointer<Void> engine, Pointer<Utf8> filePath, int preload);

typedef AudioEnginePlayNative = Int32 Function(Pointer<Void> engine);
typedef AudioEnginePlayDart = int Function(Pointer<Void> engine);

typedef AudioEnginePauseNative = Int32 Function(Pointer<Void> engine);
typedef AudioEnginePauseDart = int Function(Pointer<Void> engine);

typedef AudioEngineStopNative = Int32 Function(Pointer<Void> engine);
typedef AudioEngineStopDart = int Function(Pointer<Void> engine);

typedef AudioEngineSeekNative = Int32 Function(
    Pointer<Void> engine, Double positionSeconds);
typedef AudioEngineSeekDart = int Function(
    Pointer<Void> engine, double positionSeconds);

typedef AudioEngineGetPositionNative = Double Function(Pointer<Void> engine);
typedef AudioEngineGetPositionDart = double Function(Pointer<Void> engine);

typedef AudioEngineGetDurationNative = Double Function(Pointer<Void> engine);
typedef AudioEngineGetDurationDart = double Function(Pointer<Void> engine);

typedef AudioEngineIsPlayingNative = Int32 Function(Pointer<Void> engine);
typedef AudioEngineIsPlayingDart = int Function(Pointer<Void> engine);

typedef AudioEngineGetStateNative = Int32 Function(Pointer<Void> engine);
typedef AudioEngineGetStateDart = int Function(Pointer<Void> engine);

typedef AudioEngineSetVolumeNative = Void Function(
    Pointer<Void> engine, Float volume);
typedef AudioEngineSetVolumeDart = void Function(
    Pointer<Void> engine, double volume);

typedef AudioEngineGetVolumeNative = Float Function(Pointer<Void> engine);
typedef AudioEngineGetVolumeDart = double Function(Pointer<Void> engine);

typedef AudioEngineDuckVolumeNative = Void Function(
    Pointer<Void> engine, Float duckLevel, Int32 fadeMs);
typedef AudioEngineDuckVolumeDart = void Function(
    Pointer<Void> engine, double duckLevel, int fadeMs);

typedef AudioEngineRestoreVolumeNative = Void Function(
    Pointer<Void> engine, Int32 fadeMs);
typedef AudioEngineRestoreVolumeDart = void Function(
    Pointer<Void> engine, int fadeMs);

typedef AudioEngineOnAudioFocusChangeNative = Void Function(
    Pointer<Void> engine, Int32 focusState);
typedef AudioEngineOnAudioFocusChangeDart = void Function(
    Pointer<Void> engine, int focusState);

typedef AudioEngineSetSpeedNative = Void Function(
    Pointer<Void> engine, Float speed);
typedef AudioEngineSetSpeedDart = void Function(
    Pointer<Void> engine, double speed);

typedef AudioEngineGetSpeedNative = Float Function(Pointer<Void> engine);
typedef AudioEngineGetSpeedDart = double Function(Pointer<Void> engine);

typedef AudioEnginePreloadNextNative = Int32 Function(
    Pointer<Void> engine, Pointer<Utf8> filePath);
typedef AudioEnginePreloadNextDart = int Function(
    Pointer<Void> engine, Pointer<Utf8> filePath);

typedef AudioEngineSwitchToPreloadedNative = Int32 Function(
    Pointer<Void> engine);
typedef AudioEngineSwitchToPreloadedDart = int Function(Pointer<Void> engine);

typedef AudioEngineClearPreloadNative = Void Function(Pointer<Void> engine);
typedef AudioEngineClearPreloadDart = void Function(Pointer<Void> engine);

/// Callback types
typedef StateChangedCallbackNative = Void Function(Int32 state);
typedef StateChangedCallbackDart = void Function(int state);

typedef PositionChangedCallbackNative = Void Function(Double position);
typedef PositionChangedCallbackDart = void Function(double position);

typedef AyahEndedCallbackNative = Void Function();
typedef AyahEndedCallbackDart = void Function();

typedef ErrorCallbackNative = Void Function(Pointer<Utf8> error);
typedef ErrorCallbackDart = void Function(Pointer<Utf8> error);

typedef AudioEngineSetCallbacksNative = Void Function(
  Pointer<Void> engine,
  Pointer<NativeFunction<StateChangedCallbackNative>> onStateChanged,
  Pointer<NativeFunction<PositionChangedCallbackNative>> onPositionChanged,
  Pointer<NativeFunction<AyahEndedCallbackNative>> onAyahEnded,
  Pointer<NativeFunction<ErrorCallbackNative>> onError,
);
typedef AudioEngineSetCallbacksDart = void Function(
  Pointer<Void> engine,
  Pointer<NativeFunction<StateChangedCallbackNative>> onStateChanged,
  Pointer<NativeFunction<PositionChangedCallbackNative>> onPositionChanged,
  Pointer<NativeFunction<AyahEndedCallbackNative>> onAyahEnded,
  Pointer<NativeFunction<ErrorCallbackNative>> onError,
);

/// AudioEngineFFI
///
/// Dart wrapper for C++ audio engine
class AudioEngineFFI {
  late DynamicLibrary _lib;
  late Pointer<Void> _engine;

  // Function pointers
  late AudioEngineCreateDart _create;
  late AudioEngineDestroyDart _destroy;
  late AudioEngineLoadDart _load;
  late AudioEnginePlayDart _play;
  late AudioEnginePauseDart _pause;
  late AudioEngineStopDart _stop;
  late AudioEngineSeekDart _seek;
  late AudioEngineGetPositionDart _getPosition;
  late AudioEngineGetDurationDart _getDuration;
  late AudioEngineIsPlayingDart _isPlaying;
  late AudioEngineGetStateDart _getState;
  late AudioEngineSetVolumeDart _setVolume;
  late AudioEngineGetVolumeDart _getVolume;
  late AudioEngineDuckVolumeDart _duckVolume;
  late AudioEngineRestoreVolumeDart _restoreVolume;
  late AudioEngineOnAudioFocusChangeDart _onAudioFocusChange;
  late AudioEngineSetSpeedDart _setSpeed;
  late AudioEngineGetSpeedDart _getSpeed;
  late AudioEnginePreloadNextDart _preloadNext;
  late AudioEngineSwitchToPreloadedDart _switchToPreloaded;
  late AudioEngineClearPreloadDart _clearPreload;
  late AudioEngineSetCallbacksDart _setCallbacks;

  // Callback holders (prevent garbage collection)
  late Pointer<NativeFunction<StateChangedCallbackNative>> _stateChangedCallback;
  late Pointer<NativeFunction<PositionChangedCallbackNative>>
      _positionChangedCallback;
  late Pointer<NativeFunction<AyahEndedCallbackNative>> _ayahEndedCallback;
  late Pointer<NativeFunction<ErrorCallbackNative>> _errorCallback;

  // Dart callbacks
  void Function(PlaybackState state)? onStateChanged;
  void Function(double position)? onPositionChanged;
  void Function()? onAyahEnded;
  void Function(String error)? onError;

  /// Constructor
  ///
  /// Loads native library and initializes audio engine
  AudioEngineFFI() {
    _loadLibrary();
    _loadFunctions();
    _engine = _create();
    _setupCallbacks();
  }

  /// Load native library
  void _loadLibrary() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libquran_native.so');
    } else if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }

  /// Load FFI function pointers
  void _loadFunctions() {
    _create = _lib
        .lookup<NativeFunction<AudioEngineCreateNative>>('audio_engine_create')
        .asFunction();

    _destroy = _lib
        .lookup<NativeFunction<AudioEngineDestroyNative>>(
            'audio_engine_destroy')
        .asFunction();

    _load = _lib
        .lookup<NativeFunction<AudioEngineLoadNative>>('audio_engine_load')
        .asFunction();

    _play = _lib
        .lookup<NativeFunction<AudioEnginePlayNative>>('audio_engine_play')
        .asFunction();

    _pause = _lib
        .lookup<NativeFunction<AudioEnginePauseNative>>('audio_engine_pause')
        .asFunction();

    _stop = _lib
        .lookup<NativeFunction<AudioEngineStopNative>>('audio_engine_stop')
        .asFunction();

    _seek = _lib
        .lookup<NativeFunction<AudioEngineSeekNative>>('audio_engine_seek')
        .asFunction();

    _getPosition = _lib
        .lookup<NativeFunction<AudioEngineGetPositionNative>>(
            'audio_engine_get_position')
        .asFunction();

    _getDuration = _lib
        .lookup<NativeFunction<AudioEngineGetDurationNative>>(
            'audio_engine_get_duration')
        .asFunction();

    _isPlaying = _lib
        .lookup<NativeFunction<AudioEngineIsPlayingNative>>(
            'audio_engine_is_playing')
        .asFunction();

    _getState = _lib
        .lookup<NativeFunction<AudioEngineGetStateNative>>(
            'audio_engine_get_state')
        .asFunction();

    _setVolume = _lib
        .lookup<NativeFunction<AudioEngineSetVolumeNative>>(
            'audio_engine_set_volume')
        .asFunction();

    _getVolume = _lib
        .lookup<NativeFunction<AudioEngineGetVolumeNative>>(
            'audio_engine_get_volume')
        .asFunction();

    _duckVolume = _lib
        .lookup<NativeFunction<AudioEngineDuckVolumeNative>>(
            'audio_engine_duck_volume')
        .asFunction();

    _restoreVolume = _lib
        .lookup<NativeFunction<AudioEngineRestoreVolumeNative>>(
            'audio_engine_restore_volume')
        .asFunction();

    _onAudioFocusChange = _lib
        .lookup<NativeFunction<AudioEngineOnAudioFocusChangeNative>>(
            'audio_engine_on_audio_focus_change')
        .asFunction();

    _setSpeed = _lib
        .lookup<NativeFunction<AudioEngineSetSpeedNative>>(
            'audio_engine_set_speed')
        .asFunction();

    _getSpeed = _lib
        .lookup<NativeFunction<AudioEngineGetSpeedNative>>(
            'audio_engine_get_speed')
        .asFunction();

    _preloadNext = _lib
        .lookup<NativeFunction<AudioEnginePreloadNextNative>>(
            'audio_engine_preload_next')
        .asFunction();

    _switchToPreloaded = _lib
        .lookup<NativeFunction<AudioEngineSwitchToPreloadedNative>>(
            'audio_engine_switch_to_preloaded')
        .asFunction();

    _clearPreload = _lib
        .lookup<NativeFunction<AudioEngineClearPreloadNative>>(
            'audio_engine_clear_preload')
        .asFunction();

    _setCallbacks = _lib
        .lookup<NativeFunction<AudioEngineSetCallbacksNative>>(
            'audio_engine_set_callbacks')
        .asFunction();
  }

  /// Setup native callbacks
  void _setupCallbacks() {
    // State changed callback
    _stateChangedCallback = Pointer.fromFunction<StateChangedCallbackNative>(
      _onStateChangedNative,
    );

    // Position changed callback
    _positionChangedCallback =
        Pointer.fromFunction<PositionChangedCallbackNative>(
      _onPositionChangedNative,
    );

    // Ayah ended callback
    _ayahEndedCallback = Pointer.fromFunction<AyahEndedCallbackNative>(
      _onAyahEndedNative,
    );

    // Error callback
    _errorCallback = Pointer.fromFunction<ErrorCallbackNative>(
      _onErrorNative,
    );

    // Register callbacks with C++
    _setCallbacks(
      _engine,
      _stateChangedCallback,
      _positionChangedCallback,
      _ayahEndedCallback,
      _errorCallback,
    );
  }

  /// Native callback handlers
  static void _onStateChangedNative(int state) {
    // This is called from C++, need to find instance
    // For simplicity, using a global instance here
    // In production, use a registry pattern
    _instance?.onStateChanged?.call(PlaybackState.values[state]);
  }

  static void _onPositionChangedNative(double position) {
    _instance?.onPositionChanged?.call(position);
  }

  static void _onAyahEndedNative() {
    _instance?.onAyahEnded?.call();
  }

  static void _onErrorNative(Pointer<Utf8> error) {
    final errorMsg = error.toDartString();
    _instance?.onError?.call(errorMsg);
  }

  // Global instance (for callbacks)
  // In production, use a proper registry
  static AudioEngineFFI? _instance;

  /// Load audio file
  ///
  /// @param filePath Absolute path to MP3 file
  /// @param preload Load into buffer immediately
  /// @return Future that completes when loaded
  Future<bool> load(String filePath, {bool preload = false}) async {
    final pathPtr = filePath.toNativeUtf8();
    final result = _load(_engine, pathPtr, preload ? 1 : 0);
    malloc.free(pathPtr);
    return result == 1;
  }

  /// Start playback
  Future<bool> play() async {
    final result = _play(_engine);
    return result == 1;
  }

  /// Pause playback
  Future<bool> pause() async {
    final result = _pause(_engine);
    return result == 1;
  }

  /// Stop playback
  Future<bool> stop() async {
    final result = _stop(_engine);
    return result == 1;
  }

  /// Seek to position
  ///
  /// @param positionSeconds Position in seconds
  Future<bool> seekTo(double positionSeconds) async {
    final result = _seek(_engine, positionSeconds);
    return result == 1;
  }

  /// Get current playback position
  double get currentPosition => _getPosition(_engine);

  /// Get audio duration
  double get duration => _getDuration(_engine);

  /// Check if playing
  bool get isPlaying => _isPlaying(_engine) == 1;

  /// Get current state
  PlaybackState get state => PlaybackState.values[_getState(_engine)];

  /// Set volume (0.0 to 1.0)
  set volume(double vol) => _setVolume(_engine, vol);

  /// Get volume
  double get volume => _getVolume(_engine);

  /// Duck volume (reduce for UI sounds)
  ///
  /// @param duckLevel Target volume (e.g., 0.3 for 30%)
  /// @param fadeMs Fade duration in milliseconds
  void duckVolume(double duckLevel, {int fadeMs = 100}) {
    _duckVolume(_engine, duckLevel, fadeMs);
  }

  /// Restore volume to previous level
  ///
  /// @param fadeMs Fade duration in milliseconds
  void restoreVolume({int fadeMs = 500}) {
    _restoreVolume(_engine, fadeMs);
  }

  /// Handle audio focus change
  ///
  /// @param focusState New audio focus state
  void handleAudioFocusChange(AudioFocusState focusState) {
    _onAudioFocusChange(_engine, focusState.index);
  }

  /// Set playback speed (0.5x to 2.0x)
  set playbackSpeed(double speed) => _setSpeed(_engine, speed);

  /// Get playback speed
  double get playbackSpeed => _getSpeed(_engine);

  /// Preload next Ayah for gapless transition
  ///
  /// @param filePath Path to next audio file
  Future<bool> preloadNext(String filePath) async {
    final pathPtr = filePath.toNativeUtf8();
    final result = _preloadNext(_engine, pathPtr);
    malloc.free(pathPtr);
    return result == 1;
  }

  /// Switch to preloaded buffer (gapless)
  Future<bool> switchToPreloaded() async {
    final result = _switchToPreloaded(_engine);
    return result == 1;
  }

  /// Clear preload buffer
  void clearPreload() {
    _clearPreload(_engine);
  }

  /// Dispose engine
  void dispose() {
    _destroy(_engine);
    _instance = null;
  }
}

/// Example usage
void main() async {
  final engine = AudioEngineFFI();
  AudioEngineFFI._instance = engine;

  // Set callbacks
  engine.onStateChanged = (state) {
    print('State changed: $state');
  };

  engine.onPositionChanged = (position) {
    print('Position: ${position.toStringAsFixed(2)}s');
  };

  engine.onAyahEnded = () {
    print('Ayah ended');
  };

  engine.onError = (error) {
    print('Error: $error');
  };

  // Load and play
  final loaded = await engine.load('/path/to/ayah_001.mp3', preload: true);
  if (loaded) {
    await engine.play();

    // Preload next Ayah at 80% progress
    await Future.delayed(Duration(milliseconds: 500));
    await engine.preloadNext('/path/to/ayah_002.mp3');

    // Wait for Ayah to finish, then switch
    // (in real app, triggered by onAyahEnded callback)
    await Future.delayed(Duration(seconds: 5));
    await engine.switchToPreloaded();
  }

  // Cleanup
  engine.dispose();
}
