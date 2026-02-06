/// playback_persistence.dart
///
/// Playback Persistence Layer
/// Audit refinement: Full repeat struct preservation

import 'dart:async';
import 'dart:convert';
import 'playback_state_controller.dart';
import 'repeat_orchestrator.dart';

// ============================================================================
// MODELS
// ============================================================================

class PersistedPlaybackContext {
  final int? surahId;
  final int? ayahNumber;
  final double position;
  final double playbackSpeed;
  final int? reciterId;
  final RepeatPersistenceData? repeatState;
  final DateTime savedAt;
  final String? checksum;

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

  bool get hasValidPosition => surahId != null && ayahNumber != null;

  factory PersistedPlaybackContext.fromJson(Map<String, dynamic> json) {
    return PersistedPlaybackContext(
      surahId: json['surahId'] as int?,
      ayahNumber: json['ayahNumber'] as int?,
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      reciterId: json['reciterId'] as int?,
      repeatState: json['repeatState'] != null ? RepeatPersistenceData.fromJson(json['repeatState']) : null,
      savedAt: DateTime.parse(json['savedAt'] as String),
      checksum: json['checksum'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'surahId': surahId,
    'ayahNumber': ayahNumber,
    'position': position,
    'playbackSpeed': playbackSpeed,
    'reciterId': reciterId,
    'repeatState': repeatState?.toJson(),
    'savedAt': savedAt.toIso8601String(),
    'checksum': checksum,
  };

  String calculateChecksum() {
    final data = '$surahId:$ayahNumber:$position:$playbackSpeed';
    var hash = 0;
    for (var i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash) + data.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  bool isValid() => checksum == null || checksum == calculateChecksum();
}

/// AUDIT: Full repeat struct for exact mid-session restoration
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
  final bool wasSuspendedForSeek;

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
    this.wasSuspendedForSeek = false,
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
      wasSuspendedForSeek: json['wasSuspendedForSeek'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'surahId': surahId,
    'startAyah': startAyah,
    'endAyah': endAyah,
    'targetIterations': targetIterations,
    'currentIteration': currentIteration,
    'currentAyah': currentAyah,
    'pauseIntervalMs': pauseIntervalMs,
    'wasActive': wasActive,
    'wasSuspendedForSeek': wasSuspendedForSeek,
  };
}

class RecoveryResult {
  final bool success;
  final PersistedPlaybackContext? context;
  final String? error;
  final Duration? age;

  const RecoveryResult({required this.success, this.context, this.error, this.age});

  bool get isFresh => age != null && age!.inDays < 7;
}

// ============================================================================
// PERSISTENCE
// ============================================================================

class PlaybackPersistence {
  final PlaybackStateController _playbackController;
  final RepeatOrchestrator? _repeatOrchestrator;

  final Map<String, String> _storage = {};
  final Duration autoSaveInterval;
  final String storageKey;

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

  void _subscribeToPlayback() {
    _playbackSubscription = _playbackController.stateStream.listen((state) {
      if (state.type == PlaybackStateType.paused || state.type == PlaybackStateType.completed) {
        saveNow();
      }
    });
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(autoSaveInterval, (_) => _autoSave());
  }

  void _autoSave() {
    if (_playbackController.state.isActive) saveNow();
  }

  Future<bool> saveNow() async {
    final playbackState = _playbackController.state;

    RepeatPersistenceData? repeatData;
    if (_repeatOrchestrator != null && (_repeatOrchestrator!.isActive || _repeatOrchestrator!.isSuspendedForSeek)) {
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
          wasSuspendedForSeek: repeatState.isSuspendedForSeek,
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
      _storage[storageKey] = jsonEncode(context.toJson());
      _lastSaved = context;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<RecoveryResult> loadSavedContext() async {
    try {
      final json = _storage[storageKey];
      if (json == null) return const RecoveryResult(success: false, error: 'No saved context');

      final context = PersistedPlaybackContext.fromJson(jsonDecode(json));
      if (!context.isValid()) return const RecoveryResult(success: false, error: 'Checksum mismatch');

      return RecoveryResult(success: true, context: context, age: DateTime.now().difference(context.savedAt));
    } catch (e) {
      return RecoveryResult(success: false, error: e.toString());
    }
  }

  Future<bool> restore() async {
    final result = await loadSavedContext();
    if (!result.success || result.context == null || !result.isFresh) return false;

    final context = result.context!;
    if (context.hasValidPosition) {
      _playbackController.startLoading(surahId: context.surahId, ayahNumber: context.ayahNumber);
      _playbackController.updateSpeed(context.playbackSpeed);
    }
    return true;
  }

  Future<void> clear() async {
    _storage.remove(storageKey);
    _lastSaved = null;
  }

  PersistedPlaybackContext? get lastSaved => _lastSaved;
  Future<bool> hasSavedContext() async => _storage.containsKey(storageKey);

  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
    await _playbackSubscription?.cancel();
    await saveNow();
  }
}
