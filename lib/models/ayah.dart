/// ayah.dart
///
/// Ayah model (text-only, normalized)
/// Per V3 schema: audio/translation data in separate tables

class Ayah {
  final int id;
  final int surahId;
  final int ayahNumber;
  final String textArabic;
  final String textChecksum;

  const Ayah({
    required this.id,
    required this.surahId,
    required this.ayahNumber,
    required this.textArabic,
    required this.textChecksum,
  });

  /// Create from database map
  factory Ayah.fromJson(Map<String, dynamic> json) {
    return Ayah(
      id: json['id'] as int,
      surahId: json['surah_id'] as int,
      ayahNumber: json['ayah_number'] as int,
      textArabic: json['text_arabic'] as String,
      textChecksum: json['text_checksum'] as String,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'surah_id': surahId,
      'ayah_number': ayahNumber,
      'text_arabic': textArabic,
      'text_checksum': textChecksum,
    };
  }

  /// Verse key (e.g., "2:255" for Ayatul Kursi)
  String get verseKey => '$surahId:$ayahNumber';

  /// Accessibility-friendly description
  String get accessibilityLabel => 'Ayah $ayahNumber';

  @override
  String toString() => 'Ayah($verseKey)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ayah && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Ayah with translation (joined query result)
class AyahWithTranslation extends Ayah {
  final String? translation;

  const AyahWithTranslation({
    required super.id,
    required super.surahId,
    required super.ayahNumber,
    required super.textArabic,
    required super.textChecksum,
    this.translation,
  });

  /// Create from joined query result
  factory AyahWithTranslation.fromJson(Map<String, dynamic> json) {
    return AyahWithTranslation(
      id: json['id'] as int,
      surahId: json['surah_id'] as int,
      ayahNumber: json['ayah_number'] as int,
      textArabic: json['text_arabic'] as String,
      textChecksum: json['text_checksum'] as String,
      translation: json['translation'] as String?,
    );
  }
}
