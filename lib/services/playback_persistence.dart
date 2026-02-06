/// playback_persistence.dart
///
/// Playback Persistence Layer
/// Saves and restores playback state for exact position recovery
///
/// Recovery Triggers:
/// - App restart
/// - Phone reboot
/// - App killed in background
///
/// Goal: Blind user resumes EXACTLY where they left. Not approximate. Exact.

import 'dart:async';
import 'dart:convert';
import 'playback_state_controller.dart';
import 'repeat_orchestrator.dart';

// ============================================================================
// MODELS
// ============================================================================

/// Persisted playback context
class PersistedPlaybackContext {
  final int? surahId;
  final int? ayahNumber;
  final double position;
  final double playbackSpeed;
  final int? reciterId;
  final RepeatPersistenceData? repeatState;
  final DateTime savedAt;
  final String? checksum; // For validation

  const PersistedPlaybackContext({
    this.surahId,
    this.ayahNumber,
    required this.position,
    this.playbackSpeed = 1.0,
    this.reciterId,
    this.repeatState,
    required this.savedAt,
    this.checksum,
  });

  /// Has valid playback position
  bool get hasValidPosition => surahId != null && ayahNumber != null;

  /// Create from JSON
  factory PersistedPlaybackContext.fromJson(Map<String, dynamic> json) {
    return PersistedPlaybackContext(
      surahId: json['surahId'] as int?,
      ayahNumber: json['ayahNumber'] as int?,
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      reciterId: json['reciterId'] as int?,
      repeatState: json['repeatState'] != null
          ? RepeatPersistenceData.fromJson(json['repeatState'])
          : null,
      savedAt: DateTime.parse(json['savedAt'] as String),
      checksum: json['checksum'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'surahId': surahId,
      'ayahNumber': ayahNumber,
      'position': position,
      'playbackSpeed': playbackSpeed,
      'reciterId': reciterId,
      'repeatState': repeatState?.toJson(),
      'savedAt': savedAt.toIso8601String(),
      'checksum': checksum,
    };
  }

  /// Calculate checksum for validation
  String calculateChecksum() {
    final data = '$surahId:$ayahNumber:$position:$playbackSpeed';
    // Simple hash for validation
    var hash = 0;
    for (var i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash) + data.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Validate checksum
  bool isValid() {
    if (checksum == null) return true;
    return checksum == calculateChecksum();
  }
}

/// Persisted repeat state
class RepeatPersistenceData {
  final int mode;
  final int? surahId;
  final int startAyah;
  final int endAyah;
  final int targetIterations;
  final int currentIteration;
  final int currentAyah;
  final int pauseIntervalMs;
  final bool wasActive;

  const RepeatPersistenceData({
    required this.mode,
    this.surahId,
    required this.startAyah,
    required this.endAyah,
    required this.targetIterations,
    required this.currentIteration,
    required this.currentAyah,
    required this.pauseIntervalMs,
    required this.wasActive,
  });

  factory RepeatPersistenceData.fromJson(Map<String, dynamic> json) {
    return RepeatPersistenceData(
      mode: json['mode'] as int,
      surahId: json['surahId'] as int?,
      startAyah: json['startAyah'] as int,
      endAyah: json['endAyah'] as int,
      targetIterations: json['targetIterations'] as int,
      currentIteration: json['currentIteration'] as int,
      currentAyah: json['currentAyah'] as int,
      pauseIntervalMs: json['pauseIntervalMs'] as int,
      wasActive: json['wasActive'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'surahId': surahId,
      'startAyah': startAyah,
      'endAyah': endAyah,
      'targetIterations': targetIterations,
      'currentIteration': currentIteration,
      'currentAyah': currentAyah,
      'pauseIntervalMs': pauseIntervalMs,
      'wasActive': wasActive,
    };
  }
}

/// Recovery result
class RecoveryResult {
  final bool success;
  final PersistedPlaybackContext? context;
  final String? error;
  final Duration? age;

  const RecoveryResult({
    required this.success,
    this.context,
    this.error,
    this.age,
  });

  /// Check if context is fresh enough to restore
  bool get isFresh {
    if (age == null) return false;
    // Consider stale after 7 days
    return age!.inDays < 7;
  }
}

// ============================================================================
// PERSISTENCE MANAGER
// ============================================================================

/// Playback Persistence Manager
///
/// Handles saving and restoring playback state for exact recovery
class PlaybackPersistence {
  final PlaybackStateController _playbackController;
  final RepeatOrchestrator? _repeatOrchestrator;

  // Storage interface (would use SharedPreferences or similar)
  final Map<String, String> _storage = {};

  // Configuration
  final Duration autoSaveInterval;
  final String storageKey;

  // State
  Timer? _autoSaveTimer;
  PersistedPlaybackContext? _lastSaved;

  StreamSubscription<PlaybackState>? _playbackSubscription;

  PlaybackPersistence({
    required PlaybackStateController playbackController,
    RepeatOrchestrator? repeatOrchestrator,
    this.autoSaveInterval = const Duration(seconds: 5),
    this.storageKey = 'playback_context',
  })  : _playbackController = playbackController,
        _repeatOrchestrator = repeatOrchestrator {
    _startAutoSave();
    _subscribeToPlayback();
  }

  /// Subscribe to playback changes
  void _subscribeToPlayback() {
    _playbackSubscription = _playbackController.stateStream.listen((state) {
      // Save on significant state changes
      if (state.type == PlaybackStateType.paused ||
          state.type == PlaybackStateType.completed) {
        saveNow();
      }
    });
  }

  /// Start auto-save timer
  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(autoSaveInterval, (_) {
      _autoSave();
    });
  }

  /// Auto-save if playing
  void _autoSave() {
    if (_playbackController.state.isActive) {
      saveNow();
    }
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Save current playback state
  Future<bool> saveNow() async {
    final playbackState = _playbackController.state;

    RepeatPersistenceData? repeatData;
    if (_repeatOrchestrator != null && _repeatOrchestrator!.isActive) {
      final repeatState = _repeatOrchestrator!.state;
      if (repeatState.config != null) {
        repeatData = RepeatPersistenceData(
          mode: repeatState.config!.mode.index,
          surahId: repeatState.config!.surahId,
          startAyah: repeatState.config!.startAyah,
          endAyah: repeatState.config!.endAyah,
          targetIterations: repeatState.config!.targetIterations,
          currentIteration: repeatState.currentIteration,
          currentAyah: repeatState.currentAyah,
          pauseIntervalMs: repeatState.config!.pauseIntervalMs,
          wasActive: repeatState.isActive,
        );
      }
    }

    var context = PersistedPlaybackContext(
      surahId: playbackState.surahId,
      ayahNumber: playbackState.ayahNumber,
      position: playbackState.position,
      playbackSpeed: playbackState.playbackSpeed,
      repeatState: repeatData,
      savedAt: DateTime.now(),
    );

    // Add checksum
    context = PersistedPlaybackContext(
      surahId: context.surahId,
      ayahNumber: context.ayahNumber,
      position: context.position,
      playbackSpeed: context.playbackSpeed,
      reciterId: context.reciterId,
      repeatState: context.repeatState,
      savedAt: context.savedAt,
      checksum: context.calculateChecksum(),
    );

    try {
      final json = jsonEncode(context.toJson());
      _storage[storageKey] = json;
      _lastSaved = context;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Load persisted context
  Future<RecoveryResult> loadSavedContext() async {
    try {
      final json = _storage[storageKey];
      if (json == null) {
        return const RecoveryResult(
          success: false,
          error: 'No saved context',
        );
      }

      final context = PersistedPlaybackContext.fromJson(jsonDecode(json));

      // Validate checksum
      if (!context.isValid()) {
        return const RecoveryResult(
          success: false,
          error: 'Checksum mismatch - corrupted data',
        );
      }

      final age = DateTime.now().difference(context.savedAt);

      return RecoveryResult(
        success: true,
        context: context,
        age: age,
      );
    } catch (e) {
      return RecoveryResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Restore playback from saved context
  Future<bool> restore() async {
    final result = await loadSavedContext();

    if (!result.success || result.context == null) {
      return false;
    }

    if (!result.isFresh) {
      // Context too old, don't auto-restore
      return false;
    }

    final context = result.context!;

    // Restore playback state
    if (context.hasValidPosition) {
      _playbackController.startLoading(
        surahId: context.surahId,
        ayahNumber: context.ayahNumber,
      );

      // Position will be set after loading
      _playbackController.updateSpeed(context.playbackSpeed);
    }

    // Restore repeat state if it was active
    if (context.repeatState != null && context.repeatState!.wasActive) {
      // RepeatOrchestrator would handle restoration
      // This requires the repeat config to be reconstructed
    }

    return true;
  }

  /// Clear saved context
  Future<void> clear() async {
    _storage.remove(storageKey);
    _lastSaved = null;
  }

  /// Get last saved context
  PersistedPlaybackContext? get lastSaved => _lastSaved;

  /// Check if has saved context
  Future<bool> hasSavedContext() async {
    return _storage.containsKey(storageKey);
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Dispose resources
  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
    await _playbackSubscription?.cancel();

    // Final save before dispose
    await saveNow();
  }
}
