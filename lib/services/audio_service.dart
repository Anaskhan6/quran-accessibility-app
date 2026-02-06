/// audio_service.dart
///
/// High-level audio orchestration service
/// Wraps FFI engine with Flutter-friendly API
/// Handles state persistence, repeat loops, and accessibility

import 'dart:async';
import '../database/database_helper.dart';
import '../models/user_progress.dart';

/// Playback state (mirrors native engine)
enum AudioPlaybackState {
  idle,
  loading,
  playing,
  paused,
  stopped,
  repeating,
  error,
}

/// Audio service configuration
class AudioConfig {
  final double defaultSpeed;
  final int defaultPauseInterval;
  final bool autoAnnounce;

  const AudioConfig({
    this.defaultSpeed = 1.0,
    this.defaultPauseInterval = 2,
    this.autoAnnounce = true,
  });
}

/// AudioService
///
/// Orchestrates Quran audio playback with:
/// - State persistence across sessions
/// - Repeat loop management
/// - Accessibility announcements
/// - Gapless Ayah transitions
class AudioService {
  static AudioService? _instance;
  
  final DatabaseHelper _db;
  final AudioConfig config;

  // State
  AudioPlaybackState _state = AudioPlaybackState.idle;
  int? _currentSurah;
  int? _currentAyah;
  int? _currentReciter;
  double _position = 0.0;
  double _duration = 0.0;
  double _volume = 1.0;
  double _speed = 1.0;

  // Repeat state
  RepeatMode? _repeatMode;
  int _repeatCount = 1;
  int _repeatCurrent = 0;
  int? _repeatStartAyah;
  int? _repeatEndAyah;

  // Stream controllers
  final _stateController = StreamController<AudioPlaybackState>.broadcast();
  final _positionController = StreamController<double>.broadcast();
  final _ayahController = StreamController<int>.broadcast();
  final _announcementController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Playback state changes
  Stream<AudioPlaybackState> get onStateChanged => _stateController.stream;
  
  /// Position updates
  Stream<double> get onPositionChanged => _positionController.stream;
  
  /// Current Ayah changes
  Stream<int> get onAyahChanged => _ayahController.stream;
  
  /// Accessibility announcements
  Stream<String> get onAnnouncement => _announcementController.stream;
  
  /// Error events
  Stream<String> get onError => _errorController.stream;

  AudioService._internal({
    DatabaseHelper? database,
    this.config = const AudioConfig(),
  }) : _db = database ?? DatabaseHelper.instance;

  /// Get singleton instance
  static AudioService get instance {
    _instance ??= AudioService._internal();
    return _instance!;
  }

  /// Create with custom config
  static AudioService create({
    DatabaseHelper? database,
    AudioConfig config = const AudioConfig(),
  }) {
    _instance = AudioService._internal(database: database, config: config);
    return _instance!;
  }

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  /// Current playback state
  AudioPlaybackState get state => _state;
  
  /// Current Surah ID
  int? get currentSurah => _currentSurah;
  
  /// Current Ayah number
  int? get currentAyah => _currentAyah;
  
  /// Current position in seconds
  double get position => _position;
  
  /// Total duration in seconds
  double get duration => _duration;
  
  /// Current volume (0.0 - 1.0)
  double get volume => _volume;
  
  /// Current playback speed
  double get speed => _speed;
  
  /// Whether currently playing
  bool get isPlaying => _state == AudioPlaybackState.playing;
  
  /// Whether repeat is active
  bool get isRepeating => _repeatMode != null;

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  /// Initialize audio service
  Future<void> init() async {
    // Load saved state
    await _loadSavedState();
    
    _speed = config.defaultSpeed;
    _updateState(AudioPlaybackState.idle);
  }

  /// Load saved playback state
  Future<void> _loadSavedState() async {
    final progress = await _db.getUserProgress();
    if (progress == null) return;

    final userProgress = UserProgress.fromJson(progress);
    _currentSurah = userProgress.lastSurah;
    _currentAyah = userProgress.lastAyah;
    _speed = userProgress.playbackSpeed;
    _repeatMode = userProgress.repeatMode;
    _repeatCount = userProgress.repeatCount;
    _repeatCurrent = userProgress.repeatCurrent;
    _repeatStartAyah = userProgress.repeatStartAyah;
    _repeatEndAyah = userProgress.repeatEndAyah;
  }

  /// Save current state
  Future<void> _saveState() async {
    await _db.updateUserProgress({
      'last_surah': _currentSurah,
      'last_ayah': _currentAyah,
      'playback_speed': _speed,
      'repeat_mode': _repeatMode?.name.toUpperCase(),
      'repeat_count': _repeatCount,
      'repeat_current': _repeatCurrent,
      'repeat_start_ayah': _repeatStartAyah,
      'repeat_end_ayah': _repeatEndAyah,
    });
  }

  // ===========================================================================
  // PLAYBACK CONTROL
  // ===========================================================================

  /// Play specific Ayah
  Future<bool> playAyah({
    required int surahId,
    required int ayahNumber,
    int? reciterId,
  }) async {
    _updateState(AudioPlaybackState.loading);
    
    _currentSurah = surahId;
    _currentAyah = ayahNumber;
    _currentReciter = reciterId ?? 1;
    
    // Get audio path from database
    final audioPath = await _db.getAudioPath(
      surahId, 
      ayahNumber, 
      _currentReciter!,
    );
    
    if (audioPath == null) {
      _handleError('Audio not found for $surahId:$ayahNumber');
      return false;
    }
    
    // TODO: Load via FFI engine
    // final success = await AudioEngineFFI.instance.loadAudio(audioPath);
    
    _updateState(AudioPlaybackState.playing);
    _ayahController.add(ayahNumber);
    
    if (config.autoAnnounce) {
      _announce('Playing Surah $surahId, Ayah $ayahNumber');
    }
    
    await _saveState();
    return true;
  }

  /// Resume playback
  Future<bool> play() async {
    if (_currentSurah == null || _currentAyah == null) {
      return false;
    }
    
    // TODO: Resume via FFI engine
    // AudioEngineFFI.instance.play();
    
    _updateState(AudioPlaybackState.playing);
    return true;
  }

  /// Pause playback
  Future<void> pause() async {
    // TODO: Pause via FFI engine
    // AudioEngineFFI.instance.pause();
    
    _updateState(AudioPlaybackState.paused);
    await _saveState();
  }

  /// Stop playback
  Future<void> stop() async {
    // TODO: Stop via FFI engine
    // AudioEngineFFI.instance.stop();
    
    _updateState(AudioPlaybackState.stopped);
    await _saveState();
  }

  /// Seek to position
  Future<void> seekTo(double seconds) async {
    // TODO: Seek via FFI engine
    // AudioEngineFFI.instance.seekTo(seconds);
    
    _position = seconds;
    _positionController.add(_position);
  }

  /// Skip to next Ayah
  Future<void> nextAyah() async {
    if (_currentSurah == null || _currentAyah == null) return;
    
    // Get Surah info to check bounds
    final surah = await _db.getSurah(_currentSurah!);
    if (surah == null) return;
    
    final totalAyah = surah['total_ayah'] as int;
    
    if (_currentAyah! < totalAyah) {
      await playAyah(
        surahId: _currentSurah!,
        ayahNumber: _currentAyah! + 1,
        reciterId: _currentReciter,
      );
    } else {
      // End of Surah
      _announce('End of Surah');
      await stop();
    }
  }

  /// Skip to previous Ayah
  Future<void> previousAyah() async {
    if (_currentSurah == null || _currentAyah == null) return;
    
    if (_currentAyah! > 1) {
      await playAyah(
        surahId: _currentSurah!,
        ayahNumber: _currentAyah! - 1,
        reciterId: _currentReciter,
      );
    } else {
      // Start of Surah - restart
      await seekTo(0);
    }
  }

  // ===========================================================================
  // VOLUME & SPEED
  // ===========================================================================

  /// Set volume (0.0 - 1.0)
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    // TODO: Set via FFI engine
    // AudioEngineFFI.instance.volume = _volume;
  }

  /// Duck volume for TalkBack
  void duckVolume() {
    // TODO: Duck via FFI engine
    // AudioEngineFFI.instance.duckVolume();
    _announce('Volume ducked');
  }

  /// Restore volume
  void restoreVolume() {
    // TODO: Restore via FFI engine
    // AudioEngineFFI.instance.restoreVolume();
  }

  /// Set playback speed (0.5 - 2.0)
  void setSpeed(double speed) {
    _speed = speed.clamp(0.5, 2.0);
    // TODO: Set via FFI engine
    // AudioEngineFFI.instance.playbackSpeed = _speed;
    _announce('Speed set to ${(_speed * 100).round()} percent');
  }

  // ===========================================================================
  // REPEAT MODE
  // ===========================================================================

  /// Set repeat mode
  Future<void> setRepeatMode(RepeatMode mode, {
    int count = 1,
    int? startAyah,
    int? endAyah,
  }) async {
    _repeatMode = mode;
    _repeatCount = count;
    _repeatCurrent = 0;
    _repeatStartAyah = startAyah ?? _currentAyah;
    _repeatEndAyah = endAyah ?? _currentAyah;
    
    await _db.saveRepeatState(
      mode: mode.name.toUpperCase(),
      count: count,
      current: 0,
      startAyah: _repeatStartAyah,
      endAyah: _repeatEndAyah,
    );
    
    String announcement;
    switch (mode) {
      case RepeatMode.single:
        announcement = 'Repeat single Ayah';
        break;
      case RepeatMode.range:
        announcement = 'Repeat Ayah $_repeatStartAyah to $_repeatEndAyah';
        break;
      case RepeatMode.infinite:
        announcement = 'Infinite repeat enabled';
        break;
      case RepeatMode.count:
        announcement = 'Repeat $count times';
        break;
    }
    _announce(announcement);
  }

  /// Clear repeat mode
  Future<void> clearRepeat() async {
    _repeatMode = null;
    _repeatCount = 1;
    _repeatCurrent = 0;
    _repeatStartAyah = null;
    _repeatEndAyah = null;
    
    await _db.clearRepeatState();
    _announce('Repeat cleared');
  }

  /// Handle repeat logic when Ayah ends
  Future<void> _handleRepeat() async {
    if (_repeatMode == null) return;
    
    switch (_repeatMode!) {
      case RepeatMode.single:
        // Replay same Ayah
        await seekTo(0);
        await play();
        break;
        
      case RepeatMode.range:
        if (_currentAyah! < _repeatEndAyah!) {
          await nextAyah();
        } else {
          // Back to start
          await playAyah(
            surahId: _currentSurah!,
            ayahNumber: _repeatStartAyah!,
            reciterId: _currentReciter,
          );
        }
        break;
        
      case RepeatMode.infinite:
        await seekTo(0);
        await play();
        break;
        
      case RepeatMode.count:
        _repeatCurrent++;
        if (_repeatCurrent < _repeatCount) {
          await seekTo(0);
          await play();
          _announce('Repeat ${_repeatCurrent + 1} of $_repeatCount');
        } else {
          await clearRepeat();
          _announce('Repeat complete');
        }
        break;
    }
  }

  // ===========================================================================
  // PRELOADING
  // ===========================================================================

  /// Preload next Ayah for gapless transition
  Future<void> preloadNext() async {
    if (_currentSurah == null || _currentAyah == null) return;
    
    // Get next ayah audio path
    final surah = await _db.getSurah(_currentSurah!);
    if (surah == null) return;
    
    final totalAyah = surah['total_ayah'] as int;
    if (_currentAyah! >= totalAyah) return;
    
    final nextAyah = _currentAyah! + 1;
    final audioPath = await _db.getAudioPath(
      _currentSurah!, 
      nextAyah, 
      _currentReciter ?? 1,
    );
    
    if (audioPath != null) {
      // TODO: Preload via FFI engine
      // await AudioEngineFFI.instance.preloadNext(audioPath);
    }
  }

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  /// Update state and notify listeners
  void _updateState(AudioPlaybackState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Handle error
  void _handleError(String message) {
    _updateState(AudioPlaybackState.error);
    _errorController.add(message);
    _db.logError('AUDIO_ERROR', message);
  }

  /// Announce for accessibility
  void _announce(String message) {
    if (config.autoAnnounce) {
      _announcementController.add(message);
    }
  }

  /// Cleanup
  Future<void> dispose() async {
    await _saveState();
    await _stateController.close();
    await _positionController.close();
    await _ayahController.close();
    await _announcementController.close();
    await _errorController.close();
  }
}
