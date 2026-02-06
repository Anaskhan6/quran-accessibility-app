/// audio_focus_manager.dart
///
/// Audio Focus Arbitration Layer
/// Audit refinements:
/// - Added TransientLossCanDuck
/// - Added resume delay buffer (500ms)

import 'dart:async';
import 'playback_state_controller.dart';

// ============================================================================
// ENUMS
// ============================================================================

enum AudioFocusType {
  fullFocus,
  duckFocus,
  /// Android-specific: brief assistant speech
  transientLossCanDuck,
  transientLoss,
  permanentLoss,
}

enum AudioFocusSource {
  unknown,
  phoneCall,
  voiceAssistant,
  screenReader,
  mediaPlayer,
  alarm,
  navigation,
  notification,
}

// ============================================================================
// MODELS
// ============================================================================

class AudioFocusEvent {
  final AudioFocusType type;
  final AudioFocusSource source;
  final DateTime timestamp;

  const AudioFocusEvent({required this.type, this.source = AudioFocusSource.unknown, required this.timestamp});
}

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

class AudioFocusManager {
  final PlaybackStateController _playbackController;

  AudioFocusType _currentFocus = AudioFocusType.fullFocus;
  SavedPlaybackPosition? _savedPosition;
  double _preDuckVolume = 1.0;
  bool _isPausedForFocus = false;
  DateTime? _focusLostAt;
  Timer? _resumeDelayTimer;

  // Configuration
  final double duckVolume;
  final Duration duckFadeDuration;
  final Duration restoreFadeDuration;
  /// AUDIT: Resume delay to avoid speech spam
  final Duration resumeDelayBuffer;

  final _focusController = StreamController<AudioFocusEvent>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  /// Announce resume only if delay exceeded
  final _announceResumeController = StreamController<bool>.broadcast();

  Stream<AudioFocusEvent> get focusStream => _focusController.stream;
  Stream<double> get volumeStream => _volumeController.stream;
  Stream<bool> get announceResumeStream => _announceResumeController.stream;
  AudioFocusType get currentFocus => _currentFocus;
  bool get isPausedForFocus => _isPausedForFocus;

  AudioFocusManager({
    required PlaybackStateController playbackController,
    this.duckVolume = 0.3,
    this.duckFadeDuration = const Duration(milliseconds: 100),
    this.restoreFadeDuration = const Duration(milliseconds: 500),
    this.resumeDelayBuffer = const Duration(milliseconds: 500), // AUDIT
  }) : _playbackController = playbackController;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  void onAudioFocusChange(AudioFocusType newFocus, {AudioFocusSource source = AudioFocusSource.unknown}) {
    final oldFocus = _currentFocus;
    _currentFocus = newFocus;

    _focusController.add(AudioFocusEvent(type: newFocus, source: source, timestamp: DateTime.now()));
    _handleFocusTransition(oldFocus, newFocus, source);
  }

  Future<bool> requestFocus() async {
    _currentFocus = AudioFocusType.fullFocus;
    return true;
  }

  void abandonFocus() {
    _currentFocus = AudioFocusType.permanentLoss;
    _handleStop();
  }

  void tryResume() {
    if (_isPausedForFocus && _savedPosition != null) {
      _handleResume();
    }
  }

  // ===========================================================================
  // FOCUS TRANSITIONS
  // ===========================================================================

  void _handleFocusTransition(AudioFocusType from, AudioFocusType to, AudioFocusSource source) {
    switch (to) {
      case AudioFocusType.fullFocus:
        _handleFullFocus(from);
        break;

      case AudioFocusType.duckFocus:
        _handleDuck(source);
        break;

      case AudioFocusType.transientLossCanDuck:
        // AUDIT: Brief assistant - duck but don't pause
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
    _resumeDelayTimer?.cancel();

    if (from == AudioFocusType.duckFocus || from == AudioFocusType.transientLossCanDuck) {
      _restoreVolume();
    } else if (from == AudioFocusType.transientLoss) {
      // AUDIT: Check if focus returned within delay buffer
      final focusLostDuration = _focusLostAt != null 
          ? DateTime.now().difference(_focusLostAt!) 
          : Duration.zero;

      if (focusLostDuration < resumeDelayBuffer) {
        // Silent resume - no announcement
        _handleResume(announce: false);
      } else {
        // Normal resume with announcement
        _handleResume(announce: true);
      }
    }
  }

  void _handleDuck(AudioFocusSource source) {
    _preDuckVolume = 1.0;
    _volumeController.add(duckVolume);
  }

  void _handleTransientLoss(AudioFocusSource source) {
    _focusLostAt = DateTime.now();
    _saveCurrentPosition();
    _playbackController.pause();
    _isPausedForFocus = true;
  }

  void _handlePermanentLoss(AudioFocusSource source) {
    _saveCurrentPosition();
    _handleStop();
  }

  void _handleResume({bool announce = true}) {
    if (_savedPosition == null) return;

    if (_savedPosition!.wasPlaying) {
      _playbackController.startPlaying(position: _savedPosition!.position);
    }

    _isPausedForFocus = false;
    _savedPosition = null;
    _focusLostAt = null;

    _announceResumeController.add(announce);
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

  void onPhoneCall(bool ringing) {
    onAudioFocusChange(ringing ? AudioFocusType.transientLoss : AudioFocusType.fullFocus, source: AudioFocusSource.phoneCall);
  }

  void onScreenReaderSpeaking(bool speaking) {
    onAudioFocusChange(speaking ? AudioFocusType.duckFocus : AudioFocusType.fullFocus, source: AudioFocusSource.screenReader);
  }

  void onVoiceAssistant(bool active) {
    // AUDIT: Use transientLossCanDuck for brief interactions
    onAudioFocusChange(active ? AudioFocusType.transientLossCanDuck : AudioFocusType.fullFocus, source: AudioFocusSource.voiceAssistant);
  }

  void onOtherMediaApp(bool playing) {
    if (playing) {
      onAudioFocusChange(AudioFocusType.permanentLoss, source: AudioFocusSource.mediaPlayer);
    }
  }

  SavedPlaybackPosition? getSavedPosition() => _savedPosition;
  void clearSavedPosition() => _savedPosition = null;

  Future<void> dispose() async {
    _resumeDelayTimer?.cancel();
    await _focusController.close();
    await _volumeController.close();
    await _announceResumeController.close();
  }
}
