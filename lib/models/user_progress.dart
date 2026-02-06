/// user_progress.dart
///
/// UserProgress model with repeat state management
/// Persists playback position and memorization settings

/// Repeat modes for memorization
enum RepeatMode {
  single,   // Single Ayah loop
  range,    // Range of Ayahs (5-10)
  infinite, // Loop forever
  count,    // Loop N times
}

class UserProgress {
  final int id;
  final int? lastSurah;
  final int? lastAyah;
  final int? activeTranslationId;
  final RepeatMode? repeatMode;
  final int repeatCount;
  final int repeatCurrent;
  final int? repeatStartAyah;
  final int? repeatEndAyah;
  final double playbackSpeed;
  final int pauseIntervalSeconds;
  final DateTime? lastUpdated;

  const UserProgress({
    required this.id,
    this.lastSurah,
    this.lastAyah,
    this.activeTranslationId,
    this.repeatMode,
    this.repeatCount = 1,
    this.repeatCurrent = 0,
    this.repeatStartAyah,
    this.repeatEndAyah,
    this.playbackSpeed = 1.0,
    this.pauseIntervalSeconds = 2,
    this.lastUpdated,
  });

  /// Create from database map
  factory UserProgress.fromJson(Map<String, dynamic> json) {
    return UserProgress(
      id: json['id'] as int,
      lastSurah: json['last_surah'] as int?,
      lastAyah: json['last_ayah'] as int?,
      activeTranslationId: json['active_translation_id'] as int?,
      repeatMode: _parseRepeatMode(json['repeat_mode'] as String?),
      repeatCount: json['repeat_count'] as int? ?? 1,
      repeatCurrent: json['repeat_current'] as int? ?? 0,
      repeatStartAyah: json['repeat_start_ayah'] as int?,
      repeatEndAyah: json['repeat_end_ayah'] as int?,
      playbackSpeed: (json['playback_speed'] as num?)?.toDouble() ?? 1.0,
      pauseIntervalSeconds: json['pause_interval_seconds'] as int? ?? 2,
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'] as String)
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'last_surah': lastSurah,
      'last_ayah': lastAyah,
      'active_translation_id': activeTranslationId,
      'repeat_mode': repeatMode?.name.toUpperCase(),
      'repeat_count': repeatCount,
      'repeat_current': repeatCurrent,
      'repeat_start_ayah': repeatStartAyah,
      'repeat_end_ayah': repeatEndAyah,
      'playback_speed': playbackSpeed,
      'pause_interval_seconds': pauseIntervalSeconds,
      'last_updated': lastUpdated?.toIso8601String(),
    };
  }

  /// Parse repeat mode from string
  static RepeatMode? _parseRepeatMode(String? mode) {
    if (mode == null) return null;
    switch (mode.toUpperCase()) {
      case 'SINGLE':
        return RepeatMode.single;
      case 'RANGE':
        return RepeatMode.range;
      case 'INFINITE':
        return RepeatMode.infinite;
      case 'COUNT':
        return RepeatMode.count;
      default:
        return null;
    }
  }

  /// Check if repeat mode is active
  bool get isRepeating => repeatMode != null;

  /// Check if more repeats remaining
  bool get hasMoreRepeats {
    if (repeatMode == RepeatMode.infinite) return true;
    if (repeatMode == RepeatMode.count) {
      return repeatCurrent < repeatCount;
    }
    return false;
  }

  /// Get remaining repeats (null for infinite)
  int? get remainingRepeats {
    if (repeatMode == RepeatMode.infinite) return null;
    if (repeatMode == RepeatMode.count) {
      return repeatCount - repeatCurrent;
    }
    return 0;
  }

  /// Accessibility announcement for repeat state
  String get repeatAnnouncement {
    if (!isRepeating) return '';
    
    switch (repeatMode!) {
      case RepeatMode.single:
        return 'Repeating current Ayah';
      case RepeatMode.range:
        return 'Repeating Ayah $repeatStartAyah to $repeatEndAyah';
      case RepeatMode.infinite:
        return 'Infinite repeat active';
      case RepeatMode.count:
        final remaining = remainingRepeats ?? 0;
        return 'Repeat ${repeatCurrent + 1} of $repeatCount. $remaining remaining';
    }
  }

  /// Create copy with updated fields
  UserProgress copyWith({
    int? lastSurah,
    int? lastAyah,
    int? activeTranslationId,
    RepeatMode? repeatMode,
    int? repeatCount,
    int? repeatCurrent,
    int? repeatStartAyah,
    int? repeatEndAyah,
    double? playbackSpeed,
    int? pauseIntervalSeconds,
  }) {
    return UserProgress(
      id: id,
      lastSurah: lastSurah ?? this.lastSurah,
      lastAyah: lastAyah ?? this.lastAyah,
      activeTranslationId: activeTranslationId ?? this.activeTranslationId,
      repeatMode: repeatMode ?? this.repeatMode,
      repeatCount: repeatCount ?? this.repeatCount,
      repeatCurrent: repeatCurrent ?? this.repeatCurrent,
      repeatStartAyah: repeatStartAyah ?? this.repeatStartAyah,
      repeatEndAyah: repeatEndAyah ?? this.repeatEndAyah,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      pauseIntervalSeconds: pauseIntervalSeconds ?? this.pauseIntervalSeconds,
      lastUpdated: DateTime.now(),
    );
  }

  @override
  String toString() => 'UserProgress(surah=$lastSurah, ayah=$lastAyah, repeat=$repeatMode)';
}
