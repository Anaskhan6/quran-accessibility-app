/// recitation_audio.dart
///
/// RecitationAudio model (normalized multi-reciter support)
/// Per V3 schema: separate from Ayah table

class RecitationAudio {
  final int id;
  final int ayahId;
  final int reciterId;
  final String? audioUrl;
  final String? localAudioPath;
  final double? durationSeconds;
  final String? audioChecksum;

  const RecitationAudio({
    required this.id,
    required this.ayahId,
    required this.reciterId,
    this.audioUrl,
    this.localAudioPath,
    this.durationSeconds,
    this.audioChecksum,
  });

  /// Create from database map
  factory RecitationAudio.fromJson(Map<String, dynamic> json) {
    return RecitationAudio(
      id: json['id'] as int,
      ayahId: json['ayah_id'] as int,
      reciterId: json['reciter_id'] as int,
      audioUrl: json['audio_url'] as String?,
      localAudioPath: json['local_audio_path'] as String?,
      durationSeconds: json['duration_seconds'] as double?,
      audioChecksum: json['audio_checksum'] as String?,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ayah_id': ayahId,
      'reciter_id': reciterId,
      'audio_url': audioUrl,
      'local_audio_path': localAudioPath,
      'duration_seconds': durationSeconds,
      'audio_checksum': audioChecksum,
    };
  }

  /// Check if audio is available offline
  bool get isDownloaded => localAudioPath != null;

  /// Get best available path (local preferred)
  String? get effectivePath => localAudioPath ?? audioUrl;

  @override
  String toString() => 'RecitationAudio(ayah=$ayahId, reciter=$reciterId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecitationAudio && 
      runtimeType == other.runtimeType && 
      id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Reciter model
class Reciter {
  final int id;
  final String name;
  final String? style; // 'Murattal', 'Mujawwad', etc.
  final int bitrate;
  final String languageCode;

  const Reciter({
    required this.id,
    required this.name,
    this.style,
    this.bitrate = 64,
    this.languageCode = 'ar',
  });

  /// Create from database map
  factory Reciter.fromJson(Map<String, dynamic> json) {
    return Reciter(
      id: json['id'] as int,
      name: json['name'] as String,
      style: json['style'] as String?,
      bitrate: json['bitrate'] as int? ?? 64,
      languageCode: json['language_code'] as String? ?? 'ar',
    );
  }

  /// Convert to database map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'style': style,
      'bitrate': bitrate,
      'language_code': languageCode,
    };
  }

  /// Accessibility-friendly description
  String get accessibilityLabel {
    final styleText = style != null ? '. $style style' : '';
    return 'Reciter $name$styleText';
  }

  @override
  String toString() => 'Reciter($id: $name)';
}
