/// accessibility_announcer.dart
///
/// Accessibility Feedback Synchronization
/// Maps playback callbacks to speech prompts with stability delay

import 'dart:async';
import 'playback_state_controller.dart';
import 'repeat_orchestrator.dart';

// ============================================================================
// MODELS
// ============================================================================

enum AnnouncementPriority { low, normal, high, critical }

class Announcement {
  final String message;
  final AnnouncementPriority priority;
  final DateTime createdAt;

  Announcement({required this.message, this.priority = AnnouncementPriority.normal}) : createdAt = DateTime.now();
}

// ============================================================================
// ANNOUNCER
// ============================================================================

class AccessibilityAnnouncer {
  final PlaybackStateController _playbackController;
  final RepeatOrchestrator? _repeatOrchestrator;
  final Duration stabilityDelay;
  final int maxQueueSize;

  final List<Announcement> _queue = [];
  bool _isAnnouncing = false;
  Timer? _stabilityTimer;
  PlaybackState? _pendingState;

  final _announcementController = StreamController<Announcement>.broadcast();
  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<RepeatEventData>? _repeatSubscription;

  Stream<Announcement> get announcementStream => _announcementController.stream;

  AccessibilityAnnouncer({
    required PlaybackStateController playbackController,
    RepeatOrchestrator? repeatOrchestrator,
    this.stabilityDelay = const Duration(milliseconds: 100),
    this.maxQueueSize = 5,
  })  : _playbackController = playbackController,
        _repeatOrchestrator = repeatOrchestrator {
    _subscribeToEvents();
  }

  void _subscribeToEvents() {
    _playbackSubscription = _playbackController.stateStream.listen(_handlePlaybackChange);
    if (_repeatOrchestrator != null) {
      _repeatSubscription = _repeatOrchestrator!.eventStream.listen(_handleRepeatEvent);
    }
  }

  void _handlePlaybackChange(PlaybackState state) {
    _pendingState = state;
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer(stabilityDelay, () {
      _announcePlaybackState(_pendingState!);
      _pendingState = null;
    });
  }

  void _announcePlaybackState(PlaybackState state) {
    String? message;
    switch (state.type) {
      case PlaybackStateType.playing:
        if (state.surahId != null && state.ayahNumber != null) {
          message = 'Playing Surah ${state.surahId}, Ayah ${state.ayahNumber}';
        }
        break;
      case PlaybackStateType.paused: message = 'Paused'; break;
      case PlaybackStateType.loading: message = 'Loading'; break;
      case PlaybackStateType.completed: message = 'Completed'; break;
      case PlaybackStateType.error: message = 'Error: ${state.errorMessage ?? "Unknown"}'; break;
      default: break;
    }
    if (message != null) announce(message);
  }

  void _handleRepeatEvent(RepeatEventData event) {
    String? message;
    switch (event.event) {
      case RepeatEvent.started:
        final cfg = event.state.config;
        message = cfg != null && !cfg.isInfinite ? 'Repeat started, ${cfg.targetIterations} times' : 'Repeat started';
        break;
      case RepeatEvent.iterationAdvanced: message = event.state.announcement; break;
      case RepeatEvent.completed: message = 'Repeat complete'; break;
      case RepeatEvent.cancelled: message = 'Repeat cancelled'; break;
      case RepeatEvent.resumed: message = 'Repeat resumed'; break;
      case RepeatEvent.suspendedForSeek: message = 'Repeat paused. Resume after seek?'; break;
      case RepeatEvent.rangeAdvanced: message = 'Ayah ${event.state.currentAyah}'; break;
      default: break;
    }
    if (message != null) announce(message);
  }

  void announce(String message, {AnnouncementPriority priority = AnnouncementPriority.normal}) {
    _enqueue(Announcement(message: message, priority: priority));
  }

  void announceSeekCompleted(int ayahNumber) => announce('Jumped to Ayah $ayahNumber', priority: AnnouncementPriority.high);
  void announceSurahChange(String surahName) => announce('Surah $surahName', priority: AnnouncementPriority.high);
  void announceSpeedChange(double speed) => announce('Speed ${(speed * 100).round()} percent');
  void announceVolumeChange(double volume) => announce('Volume ${(volume * 100).round()} percent');
  void clearQueue() => _queue.clear();

  void _enqueue(Announcement announcement) {
    if (announcement.priority == AnnouncementPriority.critical) {
      _queue.insert(0, announcement);
    } else if (announcement.priority == AnnouncementPriority.high) {
      final idx = _queue.indexWhere((a) => a.priority.index < AnnouncementPriority.high.index);
      _queue.insert(idx == -1 ? _queue.length : idx, announcement);
    } else {
      if (_queue.length >= maxQueueSize) return;
      _queue.add(announcement);
    }
    _processQueue();
  }

  void _processQueue() {
    if (_isAnnouncing || _queue.isEmpty) return;
    _isAnnouncing = true;
    final announcement = _queue.removeAt(0);
    _announcementController.add(announcement);
    Future.delayed(const Duration(milliseconds: 500), () { _isAnnouncing = false; _processQueue(); });
  }

  Future<void> dispose() async {
    _stabilityTimer?.cancel();
    await _playbackSubscription?.cancel();
    await _repeatSubscription?.cancel();
    await _announcementController.close();
  }
}
