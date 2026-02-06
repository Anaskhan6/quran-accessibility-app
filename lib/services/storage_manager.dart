/// storage_manager.dart
///
/// Storage Manager
/// Quota tracking, eviction policy, and free space monitoring

import 'dart:async';
import 'dart:io';

// ============================================================================
// MODELS
// ============================================================================

/// Storage item
class StorageItem {
  final String id;
  final String path;
  final int sizeBytes;
  final DateTime downloadedAt;
  DateTime lastAccessedAt;
  int accessCount;

  StorageItem({
    required this.id,
    required this.path,
    required this.sizeBytes,
    required this.downloadedAt,
    DateTime? lastAccessedAt,
    this.accessCount = 0,
  }) : lastAccessedAt = lastAccessedAt ?? downloadedAt;

  void markAccessed() {
    lastAccessedAt = DateTime.now();
    accessCount++;
  }
}

/// Storage stats
class StorageStats {
  final int usedBytes;
  final int quotaBytes;
  final int freeBytes;
  final int itemCount;
  final double usagePercent;

  const StorageStats({
    required this.usedBytes,
    required this.quotaBytes,
    required this.freeBytes,
    required this.itemCount,
    required this.usagePercent,
  });

  bool get isNearLimit => usagePercent >= 0.9;
  bool get isOverLimit => usedBytes >= quotaBytes;
}

/// Eviction result
class EvictionResult {
  final int evictedCount;
  final int freedBytes;
  final List<String> evictedIds;

  const EvictionResult({
    required this.evictedCount,
    required this.freedBytes,
    required this.evictedIds,
  });
}

// ============================================================================
// CONFIGURATION
// ============================================================================

class StorageConfig {
  /// Max storage quota in bytes (default 2GB)
  final int quotaBytes;
  
  /// Warning threshold percent
  final double warningThreshold;
  
  /// Critical threshold percent
  final double criticalThreshold;
  
  /// Eviction target (free to this percent)
  final double evictionTarget;

  const StorageConfig({
    this.quotaBytes = 2 * 1024 * 1024 * 1024,
    this.warningThreshold = 0.8,
    this.criticalThreshold = 0.95,
    this.evictionTarget = 0.7,
  });
}

// ============================================================================
// STORAGE MANAGER
// ============================================================================

class StorageManager {
  final StorageConfig config;
  final String baseDir;
  
  final Map<String, StorageItem> _items = {};
  int _usedBytes = 0;
  
  final _statsController = StreamController<StorageStats>.broadcast();
  final _warningController = StreamController<String>.broadcast();
  
  Stream<StorageStats> get statsStream => _statsController.stream;
  Stream<String> get warningStream => _warningController.stream;
  
  int get usedBytes => _usedBytes;
  int get remainingBytes => config.quotaBytes - _usedBytes;

  StorageManager({
    required this.baseDir,
    this.config = const StorageConfig(),
  });

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Initialize - scan existing files
  Future<void> initialize() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      return;
    }
    
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        final id = entity.path.replaceFirst('$baseDir/', '');
        _items[id] = StorageItem(
          id: id,
          path: entity.path,
          sizeBytes: stat.size,
          downloadedAt: stat.modified,
          lastAccessedAt: stat.accessed,
        );
        _usedBytes += stat.size;
      }
    }
    
    _emitStats();
    _checkThresholds();
  }

  /// Register new item
  void registerItem(StorageItem item) {
    if (_items.containsKey(item.id)) {
      _usedBytes -= _items[item.id]!.sizeBytes;
    }
    _items[item.id] = item;
    _usedBytes += item.sizeBytes;
    _emitStats();
    _checkThresholds();
  }

  /// Mark item accessed
  void markAccessed(String id) {
    _items[id]?.markAccessed();
  }

  /// Check if item exists
  bool hasItem(String id) => _items.containsKey(id);

  /// Get item
  StorageItem? getItem(String id) => _items[id];

  /// Can fit new item
  bool canFit(int sizeBytes) {
    return _usedBytes + sizeBytes <= config.quotaBytes;
  }

  /// Delete item
  Future<bool> deleteItem(String id) async {
    final item = _items.remove(id);
    if (item == null) return false;
    
    try {
      final file = File(item.path);
      if (await file.exists()) {
        await file.delete();
      }
      _usedBytes -= item.sizeBytes;
      _emitStats();
      return true;
    } catch (e) {
      _items[id] = item; // Restore on failure
      return false;
    }
  }

  /// Evict LRU items to reach target
  Future<EvictionResult> evictLRU({int? targetFreeBytes}) async {
    final target = targetFreeBytes ?? 
        (config.quotaBytes * (1 - config.evictionTarget)).round();
    
    if (remainingBytes >= target) {
      return const EvictionResult(evictedCount: 0, freedBytes: 0, evictedIds: []);
    }
    
    // Sort by last accessed (oldest first)
    final sorted = _items.values.toList()
      ..sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));
    
    int freedBytes = 0;
    final evictedIds = <String>[];
    
    for (final item in sorted) {
      if (remainingBytes >= target) break;
      
      final success = await deleteItem(item.id);
      if (success) {
        freedBytes += item.sizeBytes;
        evictedIds.add(item.id);
      }
    }
    
    return EvictionResult(
      evictedCount: evictedIds.length,
      freedBytes: freedBytes,
      evictedIds: evictedIds,
    );
  }

  /// Get storage stats
  StorageStats getStats() {
    final freeSpace = config.quotaBytes - _usedBytes;
    return StorageStats(
      usedBytes: _usedBytes,
      quotaBytes: config.quotaBytes,
      freeBytes: freeSpace > 0 ? freeSpace : 0,
      itemCount: _items.length,
      usagePercent: _usedBytes / config.quotaBytes,
    );
  }

  /// Get items by reciter
  List<StorageItem> getItemsByReciter(int reciterId) {
    return _items.values
        .where((item) => item.id.contains('reciter_$reciterId'))
        .toList();
  }

  /// Get items by Surah
  List<StorageItem> getItemsBySurah(int surahId) {
    return _items.values
        .where((item) => item.id.contains('surah_$surahId'))
        .toList();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  void _emitStats() {
    _statsController.add(getStats());
  }

  void _checkThresholds() {
    final percent = _usedBytes / config.quotaBytes;
    
    if (percent >= config.criticalThreshold) {
      _warningController.add('Storage critically full. Free up space.');
    } else if (percent >= config.warningThreshold) {
      _warningController.add('Storage ${(percent * 100).round()}% full');
    }
  }

  Future<void> dispose() async {
    await _statsController.close();
    await _warningController.close();
  }
}
