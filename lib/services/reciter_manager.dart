/// reciter_manager.dart
///
/// Reciter Offline Mapping
/// Multi-reciter support with fallback chain

import 'dart:async';
import 'storage_manager.dart';

// ============================================================================
// MODELS
// ============================================================================

/// Reciter info
class Reciter {
  final int id;
  final String name;
  final String nameArabic;
  final String style; // Murattal, Mujawwad
  final String baseUrl;
  final bool isDefault;

  const Reciter({
    required this.id,
    required this.name,
    required this.nameArabic,
    required this.style,
    required this.baseUrl,
    this.isDefault = false,
  });
}

/// Surah availability for reciter
class ReciterSurahStatus {
  final int reciterId;
  final int surahId;
  final bool isDownloaded;
  final bool isDownloading;
  final double downloadProgress;
  final int sizeBytes;

  const ReciterSurahStatus({
    required this.reciterId,
    required this.surahId,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0,
    this.sizeBytes = 0,
  });
}

/// Playback source resolution
class SourceResolution {
  final int reciterId;
  final String reciterName;
  final String audioPath;
  final bool isPreferred;
  final bool isFallback;

  const SourceResolution({
    required this.reciterId,
    required this.reciterName,
    required this.audioPath,
    this.isPreferred = true,
    this.isFallback = false,
  });
}

// ============================================================================
// RECITER MANAGER
// ============================================================================

class ReciterManager {
  final StorageManager _storageManager;
  final String audioBaseDir;
  
  final Map<int, Reciter> _reciters = {};
  int _preferredReciterId = 1;
  final List<int> _fallbackOrder = [];
  
  final _availabilityController = StreamController<Map<int, List<int>>>.broadcast();
  
  Stream<Map<int, List<int>>> get availabilityStream => _availabilityController.stream;
  
  int get preferredReciterId => _preferredReciterId;
  List<Reciter> get allReciters => _reciters.values.toList();

  ReciterManager({
    required StorageManager storageManager,
    required this.audioBaseDir,
  }) : _storageManager = storageManager {
    _initializeReciters();
  }

  void _initializeReciters() {
    // Default reciters
    const defaultReciters = [
      Reciter(
        id: 1,
        name: 'Abdul Basit',
        nameArabic: 'عبد الباسط عبد الصمد',
        style: 'Murattal',
        baseUrl: 'https://everyayah.com/data/Abdul_Basit_Murattal_64kbps',
        isDefault: true,
      ),
      Reciter(
        id: 2,
        name: 'Mishary Rashid',
        nameArabic: 'مشاري راشد العفاسي',
        style: 'Murattal',
        baseUrl: 'https://everyayah.com/data/Alafasy_64kbps',
      ),
      Reciter(
        id: 3,
        name: 'Husary',
        nameArabic: 'محمود خليل الحصري',
        style: 'Murattal',
        baseUrl: 'https://everyayah.com/data/Husary_64kbps',
      ),
    ];
    
    for (final reciter in defaultReciters) {
      _reciters[reciter.id] = reciter;
      if (reciter.isDefault) {
        _preferredReciterId = reciter.id;
      }
    }
    
    // Default fallback order
    _fallbackOrder.addAll([1, 2, 3]);
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Set preferred reciter
  void setPreferred(int reciterId) {
    if (_reciters.containsKey(reciterId)) {
      _preferredReciterId = reciterId;
    }
  }

  /// Get reciter by ID
  Reciter? getReciter(int id) => _reciters[id];

  /// Check if Surah is available for reciter
  bool isSurahAvailable(int surahId, int reciterId) {
    final itemId = _getItemId(surahId, reciterId);
    return _storageManager.hasItem(itemId);
  }

  /// Get available Surahs for reciter
  List<int> getAvailableSurahs(int reciterId) {
    final items = _storageManager.getItemsByReciter(reciterId);
    final surahs = <int>[];
    
    for (final item in items) {
      final match = RegExp(r'surah_(\d+)').firstMatch(item.id);
      if (match != null) {
        surahs.add(int.parse(match.group(1)!));
      }
    }
    
    return surahs..sort();
  }

  /// Resolve audio source with fallback
  SourceResolution? resolveSource(int surahId, int ayahNumber) {
    // Try preferred reciter first
    if (isSurahAvailable(surahId, _preferredReciterId)) {
      final path = _getAudioPath(surahId, ayahNumber, _preferredReciterId);
      final reciter = _reciters[_preferredReciterId]!;
      return SourceResolution(
        reciterId: _preferredReciterId,
        reciterName: reciter.name,
        audioPath: path,
        isPreferred: true,
      );
    }
    
    // Try fallback order
    for (final reciterId in _fallbackOrder) {
      if (reciterId == _preferredReciterId) continue;
      
      if (isSurahAvailable(surahId, reciterId)) {
        final path = _getAudioPath(surahId, ayahNumber, reciterId);
        final reciter = _reciters[reciterId]!;
        return SourceResolution(
          reciterId: reciterId,
          reciterName: reciter.name,
          audioPath: path,
          isPreferred: false,
          isFallback: true,
        );
      }
    }
    
    return null; // No offline source available
  }

  /// Get storage used by reciter
  int getReciterStorageBytes(int reciterId) {
    final items = _storageManager.getItemsByReciter(reciterId);
    return items.fold(0, (sum, item) => sum + item.sizeBytes);
  }

  /// Get Surah status for reciter
  ReciterSurahStatus getSurahStatus(int surahId, int reciterId) {
    final itemId = _getItemId(surahId, reciterId);
    final item = _storageManager.getItem(itemId);
    
    return ReciterSurahStatus(
      reciterId: reciterId,
      surahId: surahId,
      isDownloaded: item != null,
      sizeBytes: item?.sizeBytes ?? 0,
    );
  }

  /// Get URL for Surah ZIP
  String getSurahZipUrl(int surahId, int reciterId) {
    final reciter = _reciters[reciterId];
    if (reciter == null) return '';
    
    return '${reciter.baseUrl}/surah_$surahId.zip';
  }

  /// Get audio URL for single Ayah
  String getAyahUrl(int surahId, int ayahNumber, int reciterId) {
    final reciter = _reciters[reciterId];
    if (reciter == null) return '';
    
    // everyayah.com format: SSSAAA.mp3
    final surahStr = surahId.toString().padLeft(3, '0');
    final ayahStr = ayahNumber.toString().padLeft(3, '0');
    return '${reciter.baseUrl}/$surahStr$ayahStr.mp3';
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _getItemId(int surahId, int reciterId) {
    return 'surah_${surahId}_reciter_$reciterId';
  }

  String _getAudioPath(int surahId, int ayahNumber, int reciterId) {
    final surahStr = surahId.toString().padLeft(3, '0');
    final ayahStr = ayahNumber.toString().padLeft(3, '0');
    return '$audioBaseDir/reciter_$reciterId/$surahStr$ayahStr.mp3';
  }

  void _emitAvailability() {
    final availability = <int, List<int>>{};
    for (final reciterId in _reciters.keys) {
      availability[reciterId] = getAvailableSurahs(reciterId);
    }
    _availabilityController.add(availability);
  }

  Future<void> dispose() async {
    await _availabilityController.close();
  }
}
