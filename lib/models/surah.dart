/// surah.dart
///
/// Surah model with V3 schema fields
/// Includes checksum for integrity validation

class Surah {
  final int id;
  final String nameArabic;
  final String nameEnglish;
  final String transliteration;
  final int totalAyah;
  final String? revelationType; // 'Meccan' or 'Medinan'
  final String textChecksum;

  const Surah({
    required this.id,
    required this.nameArabic,
    required this.nameEnglish,
    required this.transliteration,
    required this.totalAyah,
    this.revelationType,
    required this.textChecksum,
  });

  /// Create from database map
  factory Surah.fromJson(Map<String, dynamic> json) {
    return Surah(
      id: json['id'] as int,
      nameArabic: json['name_arabic'] as String,
      nameEnglish: json['name_english'] as String,
      transliteration: json['transliteration'] as String,
      totalAyah: json['total_ayah'] as int,
      revelationType: json['revelation_type'] as String?,
      textChecksum: json['text_checksum'] as String,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name_arabic': nameArabic,
      'name_english': nameEnglish,
      'transliteration': transliteration,
      'total_ayah': totalAyah,
      'revelation_type': revelationType,
      'text_checksum': textChecksum,
    };
  }

  /// Accessibility-friendly description
  String get accessibilityLabel {
    return 'Surah $nameEnglish. $totalAyah Ayahs. ${revelationType ?? ""}';
  }

  @override
  String toString() => 'Surah($id: $nameEnglish)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Surah && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
