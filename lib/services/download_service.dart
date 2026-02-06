/// download_service.dart
///
/// Unified Download Service
/// Orchestrates queue, downloader, extraction, integrity, storage

import 'dart:async';
import 'download_queue.dart';
import 'batch_downloader.dart';
import 'extraction_sandbox.dart';
import 'download_integrity.dart';
import 'storage_manager.dart';
import 'reciter_manager.dart';

// ============================================================================
// UNIFIED DOWNLOAD SERVICE
// ============================================================================

class DownloadService {
  final DownloadQueueManager _queue;
  final BatchDownloader _downloader;
  final ExtractionSandbox _extractor;
  final DownloadIntegrity _integrity;
  final StorageManager _storage;
  final ReciterManager _reciter;
  
  final _feedbackController = StreamController<String>.broadcast();
  
  Stream<DownloadItem> get itemStream => _queue.itemStream;
  Stream<QueueStats> get statsStream => _queue.statsStream;
  Stream<String> get feedbackStream => _feedbackController.stream;

  DownloadService({
    required DownloadQueueManager queue,
    required BatchDownloader downloader,
    required ExtractionSandbox extractor,
    required DownloadIntegrity integrity,
    required StorageManager storage,
    required ReciterManager reciter,
  })  : _queue = queue,
        _downloader = downloader,
        _extractor = extractor,
        _integrity = integrity,
        _storage = storage,
        _reciter = reciter {
    _setupExecutor();
  }

  void _setupExecutor() {
    _queue.executor = _executeDownload;
    
    // Forward progress
    _downloader.progressStream.listen((progress) {
      _queue.updateProgress(
        progress.id,
        progress.downloadedBytes,
        progress.totalBytes,
      );
    });
    
    // Forward storage warnings
    _storage.warningStream.listen((warning) {
      _feedbackController.add(warning);
    });
  }

  /// Execute download with full pipeline
  Future<bool> _executeDownload(DownloadItem item) async {
    final request = item.request;
    
    try {
      // 1. Check storage quota
      if (request.expectedSizeBytes != null) {
        if (!_storage.canFit(request.expectedSizeBytes!)) {
          final eviction = await _storage.evictLRU(
            targetFreeBytes: request.expectedSizeBytes,
          );
          if (eviction.freedBytes < request.expectedSizeBytes!) {
            _feedbackController.add('Insufficient storage space');
            return false;
          }
        }
      }
      
      // 2. Download
      final downloadSuccess = await _downloader.download(item);
      if (!downloadSuccess) {
        return false;
      }
      
      // 3. Validate checksum
      if (request.expectedChecksum != null) {
        final validation = await _integrity.validateFile(
          request.destinationPath,
          request.expectedChecksum!,
        );
        if (!validation.isValid) {
          _feedbackController.add('Download corrupted. Retrying...');
          await _downloader.clearResumeData(item.id);
          return false;
        }
      }
      
      // 4. Extract if ZIP
      if (request.destinationPath.endsWith('.zip')) {
        final subDir = request.surahId != null && request.reciterId != null
            ? 'reciter_${request.reciterId}'
            : null;
        
        final extraction = await _extractor.extract(
          request.destinationPath,
          subDir: subDir,
        );
        
        if (!extraction.success) {
          _feedbackController.add('Extraction failed');
          return false;
        }
        
        // Register extracted files
        for (final file in extraction.extractedFiles) {
          // Registration happens via storage manager
        }
      }
      
      // 5. Register with storage manager
      _storage.registerItem(StorageItem(
        id: item.id,
        path: request.destinationPath,
        sizeBytes: request.expectedSizeBytes ?? 0,
        downloadedAt: DateTime.now(),
      ));
      
      _feedbackController.add('Download complete');
      return true;
      
    } catch (e) {
      _feedbackController.add('Download failed: $e');
      return false;
    }
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Download Surah for reciter
  Future<String> downloadSurah({
    required int surahId,
    int? reciterId,
    DownloadPriority priority = DownloadPriority.userRequested,
  }) async {
    final actualReciterId = reciterId ?? _reciter.preferredReciterId;
    final url = _reciter.getSurahZipUrl(surahId, actualReciterId);
    
    final id = 'surah_${surahId}_reciter_$actualReciterId';
    final destPath = '${_storage.baseDir}/$id.zip';
    
    final request = DownloadRequest(
      id: id,
      url: url,
      destinationPath: destPath,
      priority: priority,
      surahId: surahId,
      reciterId: actualReciterId,
    );
    
    _feedbackController.add('Downloading Surah $surahId');
    return _queue.enqueue(request);
  }

  /// Download multiple Surahs
  Future<List<String>> downloadSurahs({
    required List<int> surahIds,
    int? reciterId,
  }) async {
    final ids = <String>[];
    for (final surahId in surahIds) {
      final id = await downloadSurah(
        surahId: surahId,
        reciterId: reciterId,
        priority: DownloadPriority.userRequested,
      );
      ids.add(id);
    }
    return ids;
  }

  /// Pause download
  void pause(String id) => _queue.pause(id);

  /// Resume download
  void resume(String id) => _queue.resume(id);

  /// Cancel download
  void cancel(String id) {
    _downloader.cancel(id);
    _queue.cancel(id);
  }

  /// Pause all
  void pauseAll() => _queue.pauseAll();

  /// Resume all
  void resumeAll() => _queue.resumeAll();

  /// Cancel all
  void cancelAll() => _queue.cancelAll();

  /// Get stats
  QueueStats getStats() => _queue.getStats();

  /// Check if Surah available offline
  bool isSurahOffline(int surahId, {int? reciterId}) {
    final actualReciterId = reciterId ?? _reciter.preferredReciterId;
    return _reciter.isSurahAvailable(surahId, actualReciterId);
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> dispose() async {
    await _queue.dispose();
    await _downloader.dispose();
    await _extractor.dispose();
    await _integrity.dispose();
    await _storage.dispose();
    await _reciter.dispose();
    await _feedbackController.close();
  }
}
