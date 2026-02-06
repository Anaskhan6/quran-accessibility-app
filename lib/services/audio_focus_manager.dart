/// audio_focus_manager.dart
///
/// Audio Focus Arbitration Layer
/// Handles system audio focus events and adjusts playback accordingly
///
/// Focus States:
/// - FullFocus: Normal playback
/// - DuckFocus: Volume 30%, continue playing
/// - TransientLoss: Pause, save position
/// - PermanentLoss: Stop, save state

import 'dart:async';
import 'playback_state_controller.dart';

// ============================================================================
// ENUMS
// ============================================================================

/// Audio focus type
enum AudioFocusType {
  /// Full audio focus - normal playback
  fullFocus,

  /// Duck focus - reduce volume, continue playing
  duckFocus,

  /// Transient loss - pause, expect to resume soon
  transientLoss,

  /// Permanent loss - stop, save state
  permanentLoss,
}

/// Audio focus source (what caused focus change)
enum AudioFocusSource {
  /// Unknown source
  unknown,

  /// Incoming phone call
  phoneCall,

  /// Voice assistant (Google Assistant, etc)
  voiceAssistant,

  /// Screen reader (TalkBack)
  screenReader,

  /// Another media app
  mediaPlayer,

  /// Alarm or timer
  alarm,

  /// Navigation
  navigation,

  /// Notification sound
  notification,
}

// ============================================================================
// MODELS
// ============================================================================

/// Audio focus event
class AudioFocusEvent {
  final AudioFocusType type;
  final AudioFocusSource source;
  final DateTime timestamp;

  const AudioFocusEvent({
    required this.type,
    this.source = AudioFocusSource.unknown,
    required this.timestamp,
  });

  @override
  String toString() => 'FocusEvent($type from $source)';
}

/// Saved playback position for resume
class SavedPlaybackPosition {
  final int? surahId;
  final int? ayahNumber;
  final double position;
  final bool wasPlaying;
  final DateTime savedAt;

  const SavedPlaybackPosition({
    this.surahId,
    this.ayahNumber,
    required this.position,
    required this.wasPlaying,
    required this.savedAt,
  });
}

// ============================================================================
// MANAGER
// ============================================================================

/// Audio Focus Manager
///
/// Arbitrates audio focus events and adjusts playback behavior
class AudioFocusManager {
  final PlaybackStateController _playbackController;

  // State
  AudioFocusType _currentFocus = AudioFocusType.fullFocus;
  SavedPlaybackPosition? _savedPosition;
  double _preDuckVolume = 1.0;
  bool _isPausedForFocus = false;

  // Configuration
  final double duckVolume;
  final Duration duckFadeDuration;
  final Duration restoreFadeDuration;

  // Streams
  final _focusController = StreamController<AudioFocusEvent>.broadcast();
  final _volumeController = StreamController<double>.broadcast();

  /// Audio focus event stream
  Stream<AudioFocusEvent> get focusStream => _focusController.stream;

  /// Volume change stream (for FFI to apply)
  Stream<double> get volumeStream => _volumeController.stream;

  /// Current focus state
  AudioFocusType get currentFocus => _currentFocus;

  /// Whether paused due to focus loss
  bool get isPausedForFocus => _isPausedForFocus;

  AudioFocusManager({
    required PlaybackStateController playbackController,
    this.duckVolume = 0.3,
    this.duckFadeDuration = const Duration(milliseconds: 100),
    this.restoreFadeDuration = const Duration(milliseconds: 500),
  }) : _playbackController = playbackController;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Handle audio focus change from system
  void onAudioFocusChange(
    AudioFocusType newFocus, {
    AudioFocusSource source = AudioFocusSource.unknown,
  }) {
    final oldFocus = _currentFocus;
    _currentFocus = newFocus;

    _focusController.add(AudioFocusEvent(
      type: newFocus,
      source: source,
      timestamp: DateTime.now(),
    ));

    _handleFocusTransition(oldFocus, newFocus, source);
  }

  /// Request audio focus
  Future<bool> requestFocus() async {
    // Platform channel would request actual focus here
    // For now, assume success
    _currentFocus = AudioFocusType.fullFocus;
    return true;
  }

  /// Abandon audio focus
  void abandonFocus() {
    _currentFocus = AudioFocusType.permanentLoss;
    _handleStop();
  }

  /// Resume after transient loss (if applicable)
  void tryResume() {
    if (_isPausedForFocus && _savedPosition != null) {
      _handleResume();
    }
  }

  // ===========================================================================
  // FOCUS TRANSITIONS
  // ===========================================================================

  void _handleFocusTransition(
    AudioFocusType from,
    AudioFocusType to,
    AudioFocusSource source,
  ) {
    switch (to) {
      case AudioFocusType.fullFocus:
        _handleFullFocus(from);
        break;

      case AudioFocusType.duckFocus:
        _handleDuck(source);
        break;

      case AudioFocusType.transientLoss:
        _handleTransientLoss(source);
        break;

      case AudioFocusType.permanentLoss:
        _handlePermanentLoss(source);
        break;
    }
  }

  void _handleFullFocus(AudioFocusType from) {
    if (from == AudioFocusType.duckFocus) {
      // Restore volume
      _restoreVolume();
    } else if (from == AudioFocusType.transientLoss) {
      // Resume playback
      _handleResume();
    }
  }

  void _handleDuck(AudioFocusSource source) {
    // Save current volume
    _preDuckVolume = 1.0; // Would get from audio engine

    // Duck volume
    _volumeController.add(duckVolume);

    // For screen reader, we want to duck but not pause
    // Continue playback at reduced volume
  }

  void _handleTransientLoss(AudioFocusSource source) {
    // Save current state
    _saveCurrentPosition();

    // Pause playback
    _playbackController.pause();
    _isPausedForFocus = true;
  }

  void _handlePermanentLoss(AudioFocusSource source) {
    // Save state for possible recovery
    _saveCurrentPosition();

    // Stop playback
    _handleStop();
  }

  void _handleResume() {
    if (_savedPosition == null) return;

    if (_savedPosition!.wasPlaying) {
      _playbackController.startPlaying(position: _savedPosition!.position);
    }

    _isPausedForFocus = false;
    _savedPosition = null;
  }

  void _handleStop() {
    _playbackController.stop();
    _isPausedForFocus = false;
  }

  void _restoreVolume() {
    _volumeController.add(_preDuckVolume);
  }

  void _saveCurrentPosition() {
    final state = _playbackController.state;

    _savedPosition = SavedPlaybackPosition(
      surahId: state.surahId,
      ayahNumber: state.ayahNumber,
      position: state.position,
      wasPlaying: state.isActive,
      savedAt: DateTime.now(),
    );
  }

  // ===========================================================================
  // SPECIAL CASES
  // ===========================================================================

  /// Handle incoming phone call
  void onPhoneCall(bool ringing) {
    if (ringing) {
      onAudioFocusChange(
        AudioFocusType.transientLoss,
        source: AudioFocusSource.phoneCall,
      );
    } else {
      onAudioFocusChange(
        AudioFocusType.fullFocus,
        source: AudioFocusSource.phoneCall,
      );
    }
  }

  /// Handle TalkBack speaking
  void onScreenReaderSpeaking(bool speaking) {
    if (speaking) {
      onAudioFocusChange(
        AudioFocusType.duckFocus,
        source: AudioFocusSource.screenReader,
      );
    } else {
      onAudioFocusChange(
        AudioFocusType.fullFocus,
        source: AudioFocusSource.screenReader,
      );
    }
  }

  /// Handle voice assistant
  void onVoiceAssistant(bool active) {
    if (active) {
      onAudioFocusChange(
        AudioFocusType.transientLoss,
        source: AudioFocusSource.voiceAssistant,
      );
    } else {
      onAudioFocusChange(
        AudioFocusType.fullFocus,
        source: AudioFocusSource.voiceAssistant,
      );
    }
  }

  /// Handle another media app
  void onOtherMediaApp(bool playing) {
    if (playing) {
      onAudioFocusChange(
        AudioFocusType.permanentLoss,
        source: AudioFocusSource.mediaPlayer,
      );
    }
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Get saved position for recovery
  SavedPlaybackPosition? getSavedPosition() => _savedPosition;

  /// Clear saved position
  void clearSavedPosition() {
    _savedPosition = null;
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _focusController.close();
    await _volumeController.close();
  }
}
