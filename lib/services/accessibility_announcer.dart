/// accessibility_announcer.dart
///
/// Accessibility Feedback Synchronization
/// Maps playback callbacks to speech prompts
///
/// Timing Rule:
/// Feedback fires AFTER playback state stabilizes, not before.
/// This prevents blind users from getting false confirmations.

import 'dart:async';
import 'playback_state_controller.dart';
import 'repeat_orchestrator.dart';

// ============================================================================
// MODELS
// ============================================================================

/// Announcement priority
enum AnnouncementPriority {
  /// Low priority - can be skipped if queue full
  low,

  /// Normal priority - queued in order
  normal,

  /// High priority - interrupts current
  high,

  /// Critical - always announced immediately
  critical,
}

/// Announcement request
class Announcement {
  final String message;
  final AnnouncementPriority priority;
  final bool interruptible;
  final Duration? delay;
  final DateTime createdAt;

  Announcement({
    required this.message,
    this.priority = AnnouncementPriority.normal,
    this.interruptible = true,
    this.delay,
  }) : createdAt = DateTime.now();

  @override
  String toString() => 'Announcement($message, priority=$priority)';
}

/// Announcement result
enum AnnouncementResult {
  announced,
  queued,
  skipped,
  interrupted,
}

// ============================================================================
// ANNOUNCER
// ============================================================================

/// Accessibility Announcer
///
/// Synchronizes speech feedback with playback events.
/// Waits for state stability before announcing.
class AccessibilityAnnouncer {
  final PlaybackStateController _playbackController;
  final RepeatOrchestrator? _repeatOrchestrator;

  // Configuration
  final Duration stabilityDelay;
  final int maxQueueSize;

  // State
  final List<Announcement> _queue = [];
  bool _isAnnouncing = false;
  Timer? _stabilityTimer;
  PlaybackState? _pendingState;

  // Streams
  final _announcementController = StreamController<Announcement>.broadcast();
  final _resultController = StreamController<AnnouncementResult>.broadcast();

  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<RepeatEventData>? _repeatSubscription;

  /// Stream of announcements to be spoken
  Stream<Announcement> get announcementStream => _announcementController.stream;

  /// Announcement results
  Stream<AnnouncementResult> get resultStream => _resultController.stream;

  AccessibilityAnnouncer({
    required PlaybackStateController playbackController,
    RepeatOrchestrator? repeatOrchestrator,
    this.stabilityDelay = const Duration(milliseconds: 100),
    this.maxQueueSize = 5,
  })  : _playbackController = playbackController,
        _repeatOrchestrator = repeatOrchestrator {
    _subscribeToEvents();
  }

  /// Subscribe to playback and repeat events
  void _subscribeToEvents() {
    _playbackSubscription = _playbackController.stateStream.listen((state) {
      _handlePlaybackChange(state);
    });

    if (_repeatOrchestrator != null) {
      _repeatSubscription = _repeatOrchestrator!.eventStream.listen((event) {
        _handleRepeatEvent(event);
      });
    }
  }

  // ===========================================================================
  // EVENT HANDLERS
  // ===========================================================================

  /// Handle playback state changes
  void _handlePlaybackChange(PlaybackState state) {
    // Wait for stability before announcing
    _pendingState = state;
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer(stabilityDelay, () {
      _announcePlaybackState(_pendingState!);
      _pendingState = null;
    });
  }

  /// Announce playback state
  void _announcePlaybackState(PlaybackState state) {
    String? message;

    switch (state.type) {
      case PlaybackStateType.playing:
        if (state.surahId != null) {
          message = _buildPlayingAnnouncement(state);
        }
        break;

      case PlaybackStateType.paused:
        message = 'Paused';
        break;

      case PlaybackStateType.loading:
        message = 'Loading';
        break;

      case PlaybackStateType.completed:
        message = 'Completed';
        break;

      case PlaybackStateType.error:
        message = 'Error: ${state.errorMessage ?? "Unknown error"}';
        break;

      case PlaybackStateType.seeking:
        // Announced via SeekCompleted callback
        break;

      case PlaybackStateType.buffering:
        // No announcement for buffering
        break;

      case PlaybackStateType.idle:
      case PlaybackStateType.repeating:
        // No announcement
        break;
    }

    if (message != null) {
      announce(message);
    }
  }

  /// Build playing announcement
  String _buildPlayingAnnouncement(PlaybackState state) {
    final surahId = state.surahId;
    final ayahNumber = state.ayahNumber;

    if (surahId != null && ayahNumber != null) {
      return 'Playing Surah $surahId, Ayah $ayahNumber';
    } else if (surahId != null) {
      return 'Playing Surah $surahId';
    }
    return 'Playing';
  }

  /// Handle repeat events
  void _handleRepeatEvent(RepeatEventData event) {
    String? message;

    switch (event.event) {
      case RepeatEvent.started:
        final state = event.state;
        if (state.config != null) {
          if (state.config!.isInfinite) {
            message = 'Repeat started';
          } else {
            message = 'Repeat started, ${state.config!.targetIterations} times';
          }
        }
        break;

      case RepeatEvent.iterationAdvanced:
        message = event.state.announcement;
        break;

      case RepeatEvent.completed:
        message = 'Repeat complete';
        break;

      case RepeatEvent.cancelled:
        message = 'Repeat cancelled';
        break;

      case RepeatEvent.paused:
        // No announcement - normal pause handles this
        break;

      case RepeatEvent.resumed:
        message = 'Repeat resumed';
        break;

      case RepeatEvent.interrupted:
        message = 'Repeat paused';
        break;

      case RepeatEvent.restored:
        message = 'Repeat restored';
        break;

      case RepeatEvent.rangeAdvanced:
        // Announce Ayah change
        message = 'Ayah ${event.state.currentAyah}';
        break;
    }

    if (message != null) {
      announce(message);
    }
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Announce a message
  void announce(
    String message, {
    AnnouncementPriority priority = AnnouncementPriority.normal,
  }) {
    final announcement = Announcement(
      message: message,
      priority: priority,
    );

    _enqueue(announcement);
  }

  /// Announce seek completion
  void announceSeekCompleted(int ayahNumber) {
    announce(
      'Jumped to Ayah $ayahNumber',
      priority: AnnouncementPriority.high,
    );
  }

  /// Announce Surah change
  void announceSurahChange(String surahName) {
    announce(
      'Surah $surahName',
      priority: AnnouncementPriority.high,
    );
  }

  /// Announce speed change
  void announceSpeedChange(double speed) {
    final percent = (speed * 100).round();
    announce('Speed $percent percent');
  }

  /// Announce volume change
  void announceVolumeChange(double volume) {
    final percent = (volume * 100).round();
    announce('Volume $percent percent');
  }

  /// Clear announcement queue
  void clearQueue() {
    _queue.clear();
  }

  /// Cancel current announcement
  void cancel() {
    _isAnnouncing = false;
    clearQueue();
  }

  // ===========================================================================
  // QUEUE MANAGEMENT
  // ===========================================================================

  void _enqueue(Announcement announcement) {
    // Handle priority
    if (announcement.priority == AnnouncementPriority.critical) {
      _interrupt();
      _queue.insert(0, announcement);
    } else if (announcement.priority == AnnouncementPriority.high) {
      // Insert after critical but before normal
      final insertIndex = _queue.indexWhere(
        (a) => a.priority.index < AnnouncementPriority.high.index,
      );
      if (insertIndex == -1) {
        _queue.add(announcement);
      } else {
        _queue.insert(insertIndex, announcement);
      }
    } else {
      // Check queue size
      if (_queue.length >= maxQueueSize) {
        _resultController.add(AnnouncementResult.skipped);
        return;
      }
      _queue.add(announcement);
    }

    _processQueue();
  }

  void _interrupt() {
    if (_isAnnouncing) {
      _resultController.add(AnnouncementResult.interrupted);
      _isAnnouncing = false;
    }
  }

  void _processQueue() {
    if (_isAnnouncing || _queue.isEmpty) return;

    _isAnnouncing = true;
    final announcement = _queue.removeAt(0);

    _announcementController.add(announcement);
    _resultController.add(AnnouncementResult.announced);

    // Simulate announcement duration
    Future.delayed(const Duration(milliseconds: 500), () {
      _isAnnouncing = false;
      _processQueue();
    });
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Dispose resources
  Future<void> dispose() async {
    _stabilityTimer?.cancel();
    await _playbackSubscription?.cancel();
    await _repeatSubscription?.cancel();
    await _announcementController.close();
    await _resultController.close();
  }
}
